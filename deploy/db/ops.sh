#!/usr/bin/env bash
# Operação da VM do BANCO (MongoDB). Instalado em /opt/todo/ops.sh.
# Uso (de fora): ./scripts/pipeline.sh <rotina>   |   dentro da VM: /opt/todo/ops.sh <comando>
#
#   deploy <imagem>        aplica/atualiza o MongoDB (dados preservados)
#   status                 contêiner, saúde, rede, disco, contagem de tarefas, backups
#   logs [linhas]          últimos logs do MongoDB
#   restart                reinicia o MongoDB
#   backup [rotulo]        gera backup e envia ao S3
#   backups                lista os backups disponíveis
#   restore-test [objeto]  restaura um backup em contêiner ISOLADO e confere
#   restore <objeto>       restaura um backup NA PRODUÇÃO (faz backup antes)
#   reset-list             apaga a lista e recria a de demonstração (faz backup antes)
#   export                 escreve o backup mais recente na saída (cópia fora da nuvem)

# shellcheck source=deploy/common.sh
source "$(dirname "$(readlink -f "$0")")/common.sh"

DATA_DISK=/mnt/mongo-data
LOCAL_BACKUPS=$DATA_DISK/backups
CONTAINER=todo-mongo
TOOLS_ARGS=(--config /run/todo/mongotools.yaml --username root --authenticationDatabase admin)

bucket() { atributo backup-bucket; }
prefixo_s3() { if [[ $NUVEM == gcp ]]; then echo "gs://$(bucket)/mongo/"; else echo "s3://$(bucket)/mongo/"; fi; }
# Arquivo do cron: busybox (VM do LocalStack) ou cron.d (Ubuntu na GCP)
if [[ $NUVEM == gcp ]]; then AGENDA=/etc/cron.d/todo-backup CRON_USUARIO="root "; else AGENDA=/etc/crontabs/root CRON_USUARIO=""; fi

# Prelúdio JavaScript: autentica como root lendo a senha do arquivo de segredo
# DENTRO do contêiner. A senha não passa pela linha de comando nem pelos logs.
JS_AUTH="db.getSiblingDB('admin').auth('root', require('fs').readFileSync('/run/secrets/mongo_root_password','utf8').trim());"

mongo_eval() {
  docker exec "$CONTAINER" mongosh --quiet --norc --eval "$JS_AUTH $1"
}

# Na PRIMEIRA inicialização (volume vazio), a imagem oficial sobe um mongod
# temporário para rodar o init-mongo.js, desliga e sobe o definitivo. O
# healthcheck pode passar no temporário; por isso, antes de usar o banco,
# espera a mensagem de fim da inicialização (se houve) e um ping autenticado.
aguardar_mongo() {
  local i
  for i in $(seq 1 60); do
    if docker logs "$CONTAINER" 2>&1 | grep -q 'MongoDB init process complete' \
       || ! docker logs "$CONTAINER" 2>&1 | grep -q 'initdb.d'; then
      mongo_eval "quit(db.adminCommand('ping').ok ? 0 : 1)" >/dev/null 2>&1 && return 0
    fi
    sleep 2
    [[ $i == 10 ]] && log "Aguardando o MongoDB concluir a inicialização..."
  done
  falhar "MongoDB não ficou pronto (veja: logs-banco)"
}

contar_tarefas() {
  mongo_eval "print(db.getSiblingDB('todo-app').todos.countDocuments())"
}

garantir_disco() {
  mountpoint -q "$DATA_DISK" || falhar "volume de dados (EBS) não montado em $DATA_DISK"
  install -d -o 999 -g 999 -m 700 "$DATA_DISK/db"
  install -d -m 700 "$LOCAL_BACKUPS"
}

# Equivalente ao Security Group todo-db-sg: a porta 27017 só aceita conexões
# vindas do IP privado da VM da aplicação. Todo o resto é descartado.
aplicar_firewall() {
  local permitido
  permitido=$(atributo mongo-allowed-from)
  iptables -N TODO-MONGO 2>/dev/null || iptables -F TODO-MONGO
  iptables -A TODO-MONGO -s "$permitido" -j RETURN
  iptables -A TODO-MONGO -j DROP
  iptables -C DOCKER-USER -p tcp --dport 27017 -j TODO-MONGO 2>/dev/null \
    || iptables -I DOCKER-USER -p tcp --dport 27017 -j TODO-MONGO
  log "Firewall: 27017 liberada somente para $permitido"
}

# ---------------------------------------------------------------------------
cmd_deploy() {
  local imagem=${1:?informe a imagem do banco}
  travar
  garantir_disco

  log "Preparando segredos em $SECRETS_DIR"
  # 999 = usuário mongodb dentro da imagem oficial
  gravar_segredo "$(atributo secret-root)" "$SECRETS_DIR/mongo_root_password" 999:999 0400
  gravar_segredo "$(atributo secret-app)"  "$SECRETS_DIR/mongo_app_password"  999:999 0400
  limpar_ponto_montagem "$SECRETS_DIR/mongotools.yaml"
  ( umask 077; printf 'password: %s\n' "$(cat "$SECRETS_DIR/mongo_root_password")" >"$SECRETS_DIR/mongotools.yaml" )

  cat >"$TODO_DIR/.env" <<EOF
MONGO_IMAGE=$imagem
PRIVATE_IP=$(ip_privado)
EOF
  chmod 600 "$TODO_DIR/.env"

  # Backup antes de trocar a versão, se já houver banco rodando
  if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    log "Banco em execução: backup preventivo antes da atualização"
    cmd_backup pre-deploy || erro "backup preventivo falhou; prosseguindo com a atualização"
  fi

  log "Preparando imagem $imagem"
  baixar_imagens

  log "Subindo o MongoDB (o volume em $DATA_DISK/db é mantido)"
  "${COMPOSE[@]}" up -d --wait --wait-timeout 240
  aplicar_firewall
  aguardar_mongo

  log "Garantindo o usuário da aplicação (todo_app, somente leitura/escrita em todo-app)"
  mongo_eval "
    const pw = require('fs').readFileSync('/run/secrets/mongo_app_password','utf8').trim();
    const d = db.getSiblingDB('todo-app');
    const roles = [{ role: 'readWrite', db: 'todo-app' }];
    if (d.getUser('todo_app')) { d.updateUser('todo_app', { pwd: pw, roles }); print('usuário todo_app atualizado'); }
    else { d.createUser({ user: 'todo_app', pwd: pw, roles }); print('usuário todo_app criado'); }
  "

  instalar_agendamento_backup
  registrar_release "mongo=$imagem"
  log "Tarefas no banco: $(contar_tarefas)"
  "${COMPOSE[@]}" ps
}

# Reinício da VM: religa o banco e reaplica o firewall
cmd_boot() {
  "${COMPOSE[@]}" up -d --wait --wait-timeout 240
  aplicar_firewall
  aguardar_mongo
  instalar_agendamento_backup
}

instalar_agendamento_backup() {
  # O cron não herda as variáveis da instância (TODO_*, AWS_*): grava-as num arquivo
  # (na GCP o pipeline já gravou esse arquivo)
  if [[ $NUVEM != gcp ]]; then
    env | grep -E '^(TODO_|AWS_)' | sed -E 's/^([^=]+)=(.*)$/export \1="\2"/' >"$TODO_DIR/instancia.env"
    chmod 600 "$TODO_DIR/instancia.env"
  fi
  if ! grep -qF 'ops.sh backup agendado' "$AGENDA" 2>/dev/null; then
    echo "0 */6 * * * ${CRON_USUARIO}. $TODO_DIR/instancia.env && $TODO_DIR/ops.sh backup agendado >>/var/log/todo-backup.log 2>&1" \
      >>"$AGENDA"
  fi
  log "Backup automático: a cada 6 horas (cron da VM)"
}

# ---------------------------------------------------------------------------
cmd_status() {
  echo "== Instância $(atributo instance-id) | IP privado $(ip_privado) | sem IP público"
  echo
  echo "== Contêiner"
  "${COMPOSE[@]}" ps
  echo
  echo "== Saúde"
  local saude
  saude=$(docker inspect -f '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo "ausente")
  echo "MongoDB: $saude"
  [[ $saude == healthy ]] && echo "Tarefas cadastradas: $(contar_tarefas)"
  echo
  echo "== Rede (deve escutar apenas em $(ip_privado):27017)"
  ss -ltnH 'sport = :27017' | awk '{print $4}'
  echo "Firewall:"
  iptables -S TODO-MONGO 2>/dev/null | sed 's/^/  /' || echo "  (não aplicado)"
  echo
  echo "== Volume de dados (EBS)"
  df -h "$DATA_DISK" | tail -n 1
  echo
  echo "== Backups"
  grep -F 'backup agendado' "$AGENDA" >/dev/null 2>&1 && echo "Agendamento: a cada 6 horas" || echo "Agendamento: AUSENTE"
  cmd_backups | tail -n 3
  echo
  mostrar_releases
}

# ---------------------------------------------------------------------------
cmd_backup() {
  local rotulo=${1:-manual} ts arquivo
  travar
  garantir_disco
  ts=$(date -u +%Y%m%dT%H%M%SZ)
  arquivo="$LOCAL_BACKUPS/todo-$ts-$rotulo.archive.gz"

  log "Gerando backup do banco todo-app ($rotulo)"
  docker exec "$CONTAINER" mongodump "${TOOLS_ARGS[@]}" --db todo-app --archive --gzip --quiet >"$arquivo"
  [[ -s $arquivo ]] || falhar "backup vazio"

  log "Enviando para $(prefixo_s3)"
  objeto_copiar "$arquivo" "$(prefixo_s3)"
  log "Backup concluído: $(basename "$arquivo") ($(du -h "$arquivo" | cut -f1))"

  # Mantém só os 5 mais recentes no volume local; a retenção oficial é no S3.
  # O nome começa com a data (todo-AAAAMMDDTHHMMSSZ-...), então ordenar pelo nome basta.
  find "$LOCAL_BACKUPS" -name 'todo-*.archive.gz' | sort -r | tail -n +6 | xargs -r rm -f
}

cmd_backups() {
  objeto_listar "$(prefixo_s3)" 2>/dev/null | grep 'archive.gz' | sort || echo "(nenhum backup no S3)"
}

# Resolve "latest" ou um nome de arquivo para o caminho s3:// completo
resolver_backup() {
  local alvo=${1:-latest} nome
  if [[ $alvo == latest || -z $alvo ]]; then
    nome=$(objeto_listar "$(prefixo_s3)" 2>/dev/null | awk '/archive.gz/ {print $4}' | sort | tail -n 1)
    if [[ -n $nome ]]; then echo "$(prefixo_s3)$nome"; fi
  elif [[ $alvo == s3://* || $alvo == gs://* ]]; then
    echo "$alvo"
  else
    echo "$(prefixo_s3)$alvo"
  fi
}

baixar_backup() {
  local origem=$1 tmp
  tmp=$(mktemp -d)
  objeto_copiar "$origem" "$tmp/backup.archive.gz" || falhar "não foi possível baixar $origem"
  echo "$tmp/backup.archive.gz"
}

# ---------------------------------------------------------------------------
# Restauração de TESTE: sobe um MongoDB temporário, sem rede e sem porta,
# restaura o backup nele e confere o conteúdo. A produção não é tocada.
cmd_restore_test() {
  local origem arquivo dir_teste nome=todo-restore-test imagem prod teste
  origem=$(resolver_backup "${1:-latest}")
  [[ -n $origem ]] || falhar "nenhum backup encontrado"
  log "Restauração de teste do backup: $origem"
  arquivo=$(baixar_backup "$origem")

  imagem=$(docker inspect -f '{{.Config.Image}}' "$CONTAINER")
  dir_teste=$(mktemp -d -p "$DATA_DISK" restore-test.XXXXXX)
  docker rm -f "$nome" >/dev/null 2>&1 || true
  # shellcheck disable=SC2064
  trap "docker rm -f $nome >/dev/null 2>&1; rm -rf '$dir_teste' '$(dirname "$arquivo")'" EXIT

  log "Subindo MongoDB isolado (--network none, sem portas, dados temporários)"
  # --no-healthcheck: o da imagem (mongosh a cada 15 s) esgotava a memória da VM
  docker run -d --name "$nome" --network none --no-healthcheck --entrypoint mongod \
    -v "$dir_teste:/data/db" "$imagem" --bind_ip 127.0.0.1 --quiet --wiredTigerCacheSizeGB 0.25 >/dev/null
  # Espera a porta abrir, sem iniciar um mongosh a cada tentativa
  for _ in $(seq 1 60); do
    docker exec "$nome" bash -c 'exec 3<>/dev/tcp/127.0.0.1/27017' 2>/dev/null && break
    sleep 2
  done

  docker exec -i "$nome" mongorestore --archive --gzip --drop --quiet <"$arquivo"
  teste=$(docker exec "$nome" mongosh --quiet --eval "print(db.getSiblingDB('todo-app').todos.countDocuments())")
  prod=$(contar_tarefas)

  echo
  echo "== Resultado da restauração de teste"
  echo "Backup:                       $(basename "$origem")"
  echo "Tarefas no backup restaurado: $teste"
  echo "Tarefas na produção agora:    $prod (não alterada)"
  echo "Amostra do backup restaurado:"
  docker exec "$nome" mongosh --quiet --eval \
    "db.getSiblingDB('todo-app').todos.find({}, {_id:0, text:1, completed:1}).limit(5).forEach(t => print(' - ' + (t.completed ? '[x] ' : '[ ] ') + t.text))"
  [[ $teste =~ ^[0-9]+$ ]] || falhar "restauração de teste não retornou contagem válida"
  log "Restauração de teste OK; contêiner temporário removido"
}

# Restauração NA PRODUÇÃO: substitui a coleção atual pelo conteúdo do backup.
cmd_restore() {
  local origem arquivo
  [[ -n ${1:-} ]] || falhar "informe o backup (nome do arquivo ou 'latest')"
  travar
  origem=$(resolver_backup "$1")
  [[ -n $origem ]] || falhar "nenhum backup encontrado"
  # Baixa ANTES do backup de segurança, para "latest" não apontar para ele
  arquivo=$(baixar_backup "$origem")
  log "Backup de segurança antes de restaurar"
  cmd_backup pre-restore
  log "Restaurando $origem NA PRODUÇÃO"
  docker exec -i "$CONTAINER" mongorestore "${TOOLS_ARGS[@]}" --nsInclude 'todo-app.*' --drop --archive --gzip --quiet <"$arquivo"
  rm -rf "$(dirname "$arquivo")"
  log "Restauração concluída. Tarefas agora: $(contar_tarefas)"
}

# Prepara uma lista nova de demonstração (ação intencional, com backup antes).
cmd_reset_list() {
  travar
  log "Backup de segurança antes de limpar a lista"
  cmd_backup pre-reset
  mongo_eval "
    load('/opt/todo/demo-todos.js');
    const t = db.getSiblingDB('todo-app').todos;
    const removidas = t.deleteMany({}).deletedCount;
    t.insertMany(DEMO_TODOS);
    print('Tarefas removidas: ' + removidas + ' | lista de demonstração recriada com ' + t.countDocuments() + ' tarefas');
  "
}

# Envia o backup mais recente pela saída padrão (o pipeline grava fora da nuvem)
cmd_export() {
  local origem
  origem=$(resolver_backup latest)
  [[ -n $origem ]] || falhar "nenhum backup encontrado"
  objeto_copiar "$origem" -
}

# ---------------------------------------------------------------------------
comando=${1:-}
shift || true
case $comando in
  deploy)        cmd_deploy "$@" ;;
  boot)          cmd_boot ;;
  status)        cmd_status ;;
  logs)          cmd_logs mongo "${1:-200}" ;;
  restart)       travar; cmd_restart mongo; aplicar_firewall; aguardar_mongo ;;
  backup)        cmd_backup "$@" ;;
  backups)       cmd_backups ;;
  restore-test)  cmd_restore_test "$@" ;;
  restore)       cmd_restore "$@" ;;
  reset-list)    cmd_reset_list ;;
  export)        cmd_export ;;
  *) sed -n '2,15p' "$0"; exit 2 ;;
esac
