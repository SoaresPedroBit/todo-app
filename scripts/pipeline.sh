#!/usr/bin/env bash
# =============================================================================
# Pipelines do ToDo App no ambiente LocalStack.
# Pré-requisitos: Docker (Desktop) e Git Bash/Linux. O Terraform roda em contêiner.
#
#   ./scripts/pipeline.sh ajuda
#
# Mesmo script usado localmente pelos alunos e no GitHub Actions.
# =============================================================================
set -euo pipefail
export MSYS_NO_PATHCONV=1 # Git Bash: não converter caminhos passados ao Docker

RAIZ=$(cd "$(dirname "$0")/.." && pwd)
cd "$RAIZ"
# Caminho do repositório no formato que o Docker entende (Windows ou Linux)
RAIZ_DOCKER=$( (pwd -W 2>/dev/null || pwd) | tr -d '\r')

LOCAL=$RAIZ/.local                   # dados locais NÃO versionados
SEGREDOS=$LOCAL/segredos
EVIDENCIAS=$LOCAL/evidencias
LS_COMPOSE=infra/localstack/compose.yaml
TF_IMAGE=hashicorp/terraform:1.9.8
REG_PUSH=localhost:5001              # registro visto desta máquina
REG_VM=todo-registry:5000            # o mesmo registro visto pelas VMs
CA_FILE=$LOCAL/caddy-root.crt
# Caminho da CA no formato que o curl entende (no Windows, C:/...)
CA_CURL=$(cygpath -m "$CA_FILE" 2>/dev/null || echo "$CA_FILE")
SECRET_ROOT=todo/mongo-root-password
SECRET_APP=todo/mongo-app-password

# ---------------------------------------------------------------------------
cor() { [[ -t 1 ]] && printf '\033[%sm' "$1" || true; }
etapa() { printf '\n%s==> %s%s\n' "$(cor '1;34')" "$*" "$(cor 0)"; }
ok()    { printf '  %s[OK]%s %s\n' "$(cor 32)" "$(cor 0)" "$*"; }
falha() { printf '  %s[FALHA]%s %s\n' "$(cor 31)" "$(cor 0)" "$*" >&2; }
morrer() { falha "$*"; exit 1; }
# Diretório privado (no Windows/NTFS o chmod pode não se aplicar; não é erro)
dir_privado() { mkdir -p "$1"; chmod 700 "$1" 2>/dev/null || true; }

awsl() { docker exec todo-localstack awslocal "$@"; }

tf() {
  docker run --rm -i \
    --network todo-servicos \
    -v "$RAIZ_DOCKER:/work" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -w /work/infra/terraform \
    -e TF_IN_AUTOMATION=1 -e TF_INPUT=0 \
    -e TF_VAR_site_address="${SITE_ADDRESS:-localhost}" \
    -e TF_VAR_http_port="${HTTP_PORT:-80}" \
    -e TF_VAR_https_port="${HTTPS_PORT:-443}" \
    "$TF_IMAGE" "$@"
}

vm_existe() { docker inspect "todo-vm-$1" >/dev/null 2>&1; }
ops() { local papel=$1; shift; docker exec "todo-vm-$papel" /opt/todo/ops.sh "$@"; }

confirmar() {
  local palavra=$1 msg=$2 resp
  [[ ${CONFIRMAR:-} == "$palavra" ]] && return 0
  [[ -t 0 ]] || morrer "$msg Para executar sem terminal, defina CONFIRMAR=$palavra."
  printf '%s\nDigite %s para continuar: ' "$msg" "$palavra"
  read -r resp
  [[ $resp == "$palavra" ]] || morrer "cancelado"
}

url_app() {
  local porta=${HTTPS_PORT:-443}
  if [[ $porta == 443 ]]; then echo "https://${SITE_ADDRESS:-localhost}"; else echo "https://${SITE_ADDRESS:-localhost}:$porta"; fi
}

# =============================================================================
# Base: LocalStack + registro + segredos
# =============================================================================
garantir_localstack() {
  if ! docker inspect -f '{{.State.Health.Status}}' todo-localstack 2>/dev/null | grep -q healthy; then
    cmd_subir_localstack
  fi
  # LocalStack Community não persiste: se reiniciou, os segredos precisam voltar
  awsl secretsmanager describe-secret --secret-id "$SECRET_ROOT" >/dev/null 2>&1 || criar_segredos
}

cmd_subir_localstack() {
  etapa "Subindo LocalStack e registro de imagens"
  docker compose -f "$LS_COMPOSE" up -d --wait --wait-timeout 180
  ok "LocalStack $(curl -fsS localhost:4566/_localstack/info | sed -E 's/.*"version": "([^"]+)".*/\1/')"
  criar_segredos
}

# Senhas geradas aqui, guardadas em .local/segredos (fora do Git, fora do estado
# do Terraform) e carregadas no Secrets Manager. Nunca são exibidas.
criar_segredos() {
  etapa "Segredos do MongoDB (Secrets Manager)"
  dir_privado "$SEGREDOS"
  local nome arquivo
  for nome in "$SECRET_ROOT" "$SECRET_APP"; do
    arquivo="$SEGREDOS/${nome##*/}"
    if [[ ! -s $arquivo ]]; then
      # tr remove \r\n (o openssl do Windows termina a linha com CRLF)
      (umask 077; openssl rand -hex 24 | tr -cd '0-9a-f' >"$arquivo")
    fi
    if awsl secretsmanager describe-secret --secret-id "$nome" >/dev/null 2>&1; then
      ok "$nome: já existe"
    else
      # Valor via stdin -> arquivo temporário no contêiner; não aparece em argumentos
      docker exec -i todo-localstack sh -c 'umask 077; cat >/tmp/s && awslocal secretsmanager create-secret --name "$0" --secret-string file:///tmp/s >/dev/null; rc=$?; rm -f /tmp/s; exit $rc' "$nome" <"$arquivo"
      ok "$nome: criado"
    fi
  done
}

# =============================================================================
# Validar
# =============================================================================
cmd_validar() {
  etapa "Backend: dependências e verificação"
  docker run --rm -v "$RAIZ_DOCKER/backend:/app" -w /app node:22-alpine \
    sh -c "npm ci --no-audit --no-fund --loglevel=error && npm test" && ok backend

  etapa "Frontend: testes"
  docker run --rm -e CI=true -v "$RAIZ_DOCKER/frontend:/app" -w /app node:22-alpine \
    sh -c "npm ci --no-audit --no-fund --loglevel=error && npm test -- --watchAll=false" && ok frontend

  etapa "Scripts (shellcheck)"
  docker run --rm -v "$RAIZ_DOCKER:/mnt" -w /mnt koalaman/shellcheck:stable -x -S warning \
    deploy/common.sh deploy/app/ops.sh deploy/db/ops.sh scripts/pipeline.sh scripts/smoke-test.sh \
    scripts/verificar-isolamento.sh infra/vm-image/entrypoint.sh && ok shellcheck

  etapa "Terraform (formatação e validação)"
  docker run --rm -v "$RAIZ_DOCKER:/work" -w /work/infra/terraform "$TF_IMAGE" fmt -check -recursive -diff
  docker run --rm -v "$RAIZ_DOCKER:/work" -w /work/infra/terraform "$TF_IMAGE" \
    init -backend=false -input=false >/dev/null
  docker run --rm -v "$RAIZ_DOCKER:/work" -w /work/infra/terraform "$TF_IMAGE" validate && ok terraform

  etapa "Arquivos Compose"
  [[ -f .env ]] || cp .env.example .env
  docker compose -f docker-compose.yaml config -q
  MONGO_IMAGE=x PRIVATE_IP=10.0.0.1 docker compose -f deploy/db/compose.yaml config -q
  FRONTEND_IMAGE=x BACKEND_IMAGE=y SITE_ADDRESS=z docker compose -f deploy/app/compose.yaml config -q
  docker compose -f "$LS_COMPOSE" config -q
  ok compose
}

# =============================================================================
# Infraestrutura (Terraform)
# =============================================================================
tf_init() { tf init -input=false >/dev/null; }

guardar_estado() {
  local f=infra/terraform/estado/terraform.tfstate
  [[ -s $f ]] || return 0
  mkdir -p "$LOCAL/estado-backups"
  cp "$f" "$LOCAL/estado-backups/terraform.tfstate.$(date -u +%Y%m%dT%H%M%SZ)"
  # mantém os 20 mais recentes
  find "$LOCAL/estado-backups" -name 'terraform.tfstate.*' | sort -r | tail -n +21 | xargs -r rm -f
}

cmd_planejar() {
  garantir_localstack
  etapa "Terraform plan (alterações previstas, nada é executado)"
  tf_init
  tf plan -out=tfplan
}

cmd_provisionar() {
  garantir_localstack
  etapa "Terraform: planejar e aplicar"
  tf_init
  guardar_estado
  tf plan -out=tfplan
  tf apply -auto-approve tfplan
  rm -f infra/terraform/tfplan
  aguardar_vms
  etapa "Inventário"
  tf output -json inventario
}

aguardar_vms() {
  etapa "Aguardando as VMs inicializarem (Docker interno)"
  local papel
  for papel in db app; do
    for _ in $(seq 1 60); do
      docker exec "todo-vm-$papel" docker info >/dev/null 2>&1 && break
      sleep 2
    done
    docker exec "todo-vm-$papel" docker info >/dev/null 2>&1 || morrer "VM $papel não inicializou (docker logs todo-vm-$papel)"
    ok "todo-vm-$papel pronta"
  done
}

# =============================================================================
# Entrega da aplicação
# =============================================================================
versao_atual() {
  local v
  v=$(git rev-parse --short=7 HEAD 2>/dev/null || echo semgit)
  # Alterações não commitadas geram versão própria, para nunca sobrescrever uma versão publicada
  if [[ -n $(git status --porcelain -- frontend backend banco-de-dados 2>/dev/null) ]]; then
    v="$v-local$(date +%m%d%H%M)"
  fi
  echo "$v"
}

tag_banco() {
  # Muda só quando banco-de-dados/ muda: atualizar a aplicação não reinicia o MongoDB
  echo "db-$(cat banco-de-dados/Dockerfile banco-de-dados/*.js | sha256sum | cut -c1-10)"
}

# Existência de uma tag no registro (aceita manifestos Docker v2 e OCI, que o BuildKit gera)
imagem_existe() {
  curl -fsS -I "http://$REG_PUSH/v2/todo/$1/manifests/$2" \
    -H 'Accept: application/vnd.oci.image.index.v1+json' \
    -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
    -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
    -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' >/dev/null 2>&1
}

construir_publicar() {
  local versao=$1 tagdb=$2 svc
  etapa "Construindo e publicando imagens (versão $versao)"
  for svc in frontend backend; do
    docker build -q -t "$REG_PUSH/todo/$svc:$versao" \
      --label org.opencontainers.image.revision="$(git rev-parse HEAD 2>/dev/null || echo local)" "./$svc" >/dev/null
    docker push -q "$REG_PUSH/todo/$svc:$versao" >/dev/null
    ok "$svc:$versao"
  done
  if imagem_existe mongo "$tagdb"; then
    ok "mongo:$tagdb (já publicada, banco-de-dados/ sem mudanças)"
  else
    docker build -q -t "$REG_PUSH/todo/mongo:$tagdb" ./banco-de-dados >/dev/null
    docker push -q "$REG_PUSH/todo/mongo:$tagdb" >/dev/null
    ok "mongo:$tagdb"
  fi
}

# Copia os arquivos de operação para /opt/todo na VM.
sincronizar() {
  local papel=$1 arquivos
  arquivos=$(cd "deploy/$papel" && ls -A | tr '\n' ' ')
  # VM recriada com o disco do Docker preservado: contêineres antigos sobem no
  # boot e o Docker cria DIRETÓRIOS no lugar dos arquivos montados que ainda não
  # existiam (Caddyfile, segredos...). Remove-os antes de copiar.
  docker exec "todo-vm-$papel" sh -c 'cd /opt/todo && for f in common.sh '"$arquivos"'; do [ -d "$f" ] && rm -rf "$f"; done; true'
  tar -C deploy -cf - common.sh -C "$papel" . \
    | docker exec -i "todo-vm-$papel" sh -c 'tar -xf - -C /opt/todo && chmod 755 /opt/todo/ops.sh /opt/todo/common.sh'
}

cmd_implantar() {
  local versao=${1:-} tagdb
  garantir_localstack
  vm_existe app && vm_existe db || morrer "infraestrutura não provisionada (rode: provisionar)"

  if [[ -z $versao ]]; then
    versao=$(versao_atual)
    tagdb=$(tag_banco)
    construir_publicar "$versao" "$tagdb"
  else
    # Rollback/reimplantação de versão já publicada: nada é reconstruído
    imagem_existe frontend "$versao" && imagem_existe backend "$versao" \
      || morrer "versão $versao não encontrada no registro (veja: versoes)"
    tagdb=""
  fi

  etapa "Banco: implantar"
  sincronizar db
  if [[ -n $tagdb ]]; then
    ops db deploy "$REG_VM/todo/mongo:$tagdb"
  else
    echo "Rollback da aplicação: o banco permanece na imagem atual (os dados não voltam no tempo)"
  fi

  etapa "Aplicação: implantar"
  sincronizar app
  ops app deploy "$REG_VM/todo/frontend:$versao" "$REG_VM/todo/backend:$versao"

  mkdir -p "$LOCAL"
  printf '%s versao=%s banco=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$versao" "${tagdb:-inalterado}" >>"$LOCAL/releases.log"

  cmd_exportar_ca >/dev/null
  etapa "Verificação pelo endereço HTTPS"
  SMOKE_CACERT=$CA_CURL ./scripts/smoke-test.sh "$(url_app)"
  echo
  ok "Versão $versao no ar em $(url_app)"
}

cmd_versoes() {
  etapa "Versões publicadas no registro"
  curl -fsS "http://$REG_PUSH/v2/todo/frontend/tags/list" | tr -d '{}"[]' | sed 's/,/ /g; s/name:todo\/frontend tags://'
  echo
  etapa "Histórico de implantações (mais recente por último)"
  tail -n 10 "$LOCAL/releases.log" 2>/dev/null || echo "(nenhuma)"
}

cmd_exportar_ca() {
  mkdir -p "$LOCAL"
  for _ in $(seq 1 20); do
    ops app ca >"$CA_FILE.tmp" 2>/dev/null && [[ -s $CA_FILE.tmp ]] && break
    sleep 2
  done
  [[ -s $CA_FILE.tmp ]] || morrer "não foi possível obter a CA do HTTPS"
  mv -f "$CA_FILE.tmp" "$CA_FILE"
  echo "CA raiz do HTTPS salva em $CA_FILE"
  echo "Para o navegador confiar (Windows): certutil -user -addstore Root \"$(cygpath -w "$CA_FILE" 2>/dev/null || echo "$CA_FILE")\""
}

# =============================================================================
# Operação
# =============================================================================
cmd_status() {
  etapa "LocalStack"
  docker compose -f "$LS_COMPOSE" ps --format 'table {{.Name}}\t{{.Status}}'
  etapa "VM da aplicação"; ops app status
  etapa "VM do banco";      ops db status
}

cmd_exportar_backup() {
  dir_privado "$LOCAL/backups"
  local destino
  destino="$LOCAL/backups/todo-$(date -u +%Y%m%dT%H%M%SZ)-exportado.archive.gz"
  docker exec todo-vm-db /opt/todo/ops.sh export >"$destino"
  [[ -s $destino ]] || { rm -f "$destino"; morrer "exportação vazia"; }
  ok "Cópia fora da nuvem: $destino"
}

cmd_backup() {
  ops db backup manual
  # LocalStack Community perde o S3 ao reiniciar: guarda também uma cópia local
  cmd_exportar_backup
}

cmd_limpar_lista() {
  confirmar LIMPAR "Isto APAGA a lista atual e recria a lista de demonstração (um backup é feito antes)."
  ops db reset-list
}

cmd_restaurar() {
  local alvo=${1:-latest}
  confirmar RESTAURAR "Isto SUBSTITUI os dados de produção pelo backup '$alvo' (um backup é feito antes)."
  ops db restore "$alvo"
  ops app health
}

# =============================================================================
# Critérios de aceite (evidências)
# =============================================================================
tarefa_existe() { curl -fsS --cacert "$CA_CURL" --ssl-no-revoke "$(url_app)/todos" | grep -q "\"$1\""; }

cmd_aceite() {
  mkdir -p "$EVIDENCIAS"
  local log
  log="$EVIDENCIAS/aceite-$(date -u +%Y%m%dT%H%M%SZ).log"
  {
    echo "Relatório de aceite - $(date -u '+%Y-%m-%d %H:%M UTC') - versão $(git rev-parse --short HEAD 2>/dev/null)"
    aceite_execucao
  } 2>&1 | tee "$log"
  local rc=${PIPESTATUS[0]}
  echo
  echo "Evidências salvas em $log"
  return "$rc"
}

aceite_execucao() {
  cmd_exportar_ca >/dev/null
  local url marca
  url=$(url_app)

  etapa "ACE-02 · Inventário (2 instâncias, banco em servidor exclusivo)"
  tf output -json inventario
  awsl ec2 describe-instances --filters Name=tag:Projeto,Values=todo-app Name=instance-state-name,Values=running \
    --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,InstanceId,InstanceType,PrivateIpAddress,PublicIpAddress||`-`]' --output table
  docker exec todo-vm-db docker ps --format '{{.Names}}' | grep -qx todo-mongo && ok "MongoDB roda sozinho na VM do banco"
  ! docker exec todo-vm-app docker ps --format '{{.Names}}' | grep -qi mongo && ok "nenhum MongoDB na VM da aplicação"

  etapa "ACE-03 · Isolamento"
  ./scripts/verificar-isolamento.sh

  etapa "ACE-04 · Aplicação pelo HTTPS: cadastrar, listar, concluir, reabrir, excluir"
  SMOKE_CACERT=$CA_CURL ./scripts/smoke-test.sh "$url" --completo
  # (sem "-o /dev/null": o curl do Windows não entende esse caminho)
  curl -sS -w '\n  HTTP -> %{http_code} redireciona para %{redirect_url}\n' "http://${SITE_ADDRESS:-localhost}:${HTTP_PORT:-80}/" | tail -n 1

  etapa "ACE-05 · Persistência"
  marca="persistencia-$(date +%s)"
  curl -fsS --cacert "$CA_CURL" --ssl-no-revoke -X POST -H 'Content-Type: application/json' -d "{\"text\":\"$marca\"}" "$url/todos" >/dev/null
  local id
  id=$(curl -fsS --cacert "$CA_CURL" --ssl-no-revoke "$url/todos" | tr '}' '\n' | grep "$marca" | sed -E 's/.*"_id":"([^"]+)".*/\1/')
  curl -fsS --cacert "$CA_CURL" --ssl-no-revoke -X PATCH "$url/todos/$id" >/dev/null # estado: concluída
  ok "tarefa '$marca' criada e concluída"

  docker exec todo-vm-db sh -c 'cd /opt/todo && docker compose up -d --force-recreate --wait mongo' >/dev/null 2>&1
  docker exec todo-vm-db /opt/todo/ops.sh boot >/dev/null
  aguardar_saude
  tarefa_existe "$marca" && ok "preservada após RECRIAR o contêiner do banco (volume mantido)"

  docker restart todo-vm-db >/dev/null
  aguardar_saude 90
  tarefa_existe "$marca" && ok "preservada após REINICIAR a VM do banco"

  local atual
  atual=$(docker exec todo-vm-app sh -c '. /opt/todo/.env; echo "$FRONTEND_IMAGE $BACKEND_IMAGE"')
  # shellcheck disable=SC2086
  ops app deploy $atual >/dev/null
  curl -fsS --cacert "$CA_CURL" --ssl-no-revoke "$url/todos" | tr '}' '\n' | grep "$marca" | grep -q '"completed":true' \
    && ok "preservada (com estado concluída) após ATUALIZAR a aplicação"
  curl -fsS --cacert "$CA_CURL" --ssl-no-revoke -X DELETE "$url/todos/$id" >/dev/null

  etapa "ACE-07 · Backup automatizado e restauração isolada"
  docker exec todo-vm-db grep -F 'backup agendado' /etc/crontabs/root | sed 's/^/  agendamento: /'
  ops db backup aceite
  ops db restore-test latest

  etapa "ACE-08 · Operação e credenciais"
  ops app health && echo
  ops app logs backend 5
  verificar_credenciais
}

aguardar_saude() {
  local limite=${1:-60} resp
  for _ in $(seq 1 $((limite / 3))); do
    resp=$(curl -fsS --cacert "$CA_CURL" --ssl-no-revoke "$(url_app)/health" 2>/dev/null || true)
    [[ $resp == *'"banco":"ok"'* ]] && return 0
    sleep 3
  done
  morrer "aplicação não ficou saudável: ${resp:-sem resposta}"
}

# Procura as senhas reais no código versionado, nos logs das VMs e nas evidências
verificar_credenciais() {
  local achou=0 s valor
  for s in "$SEGREDOS"/*; do
    valor=$(cat "$s")
    if git grep -qF "$valor" 2>/dev/null; then falha "senha encontrada no código versionado"; achou=1; fi
    if docker exec todo-vm-app sh -c 'cd /opt/todo && docker compose logs --no-color 2>&1' | grep -qF "$valor"; then falha "senha nos logs da aplicação"; achou=1; fi
    if docker exec todo-vm-db sh -c 'cd /opt/todo && docker compose logs --no-color 2>&1' | grep -qF "$valor"; then falha "senha nos logs do banco"; achou=1; fi
    if grep -rqF "$valor" "$EVIDENCIAS" 2>/dev/null; then falha "senha nas evidências"; achou=1; fi
  done
  (( achou == 0 )) && ok "nenhuma senha no código, nos logs das VMs ou nas evidências"
}

# =============================================================================
# Desativar
# =============================================================================
cmd_desativar() {
  confirmar DESTRUIR "Isto REMOVE as VMs, a rede, o volume de dados e o bucket de backups."
  if vm_existe db && docker exec todo-vm-db docker ps -q --filter name=todo-mongo | grep -q .; then
    etapa "Backup final"
    cmd_backup
  fi
  garantir_localstack
  etapa "Terraform destroy"
  tf_init
  guardar_estado
  tf destroy -auto-approve
  etapa "O que permanece nesta máquina"
  echo "  - LocalStack e registro de imagens (parar: ./scripts/pipeline.sh parar-localstack)"
  echo "  - Backups exportados: $LOCAL/backups/ ($(find "$LOCAL/backups" -type f 2>/dev/null | wc -l) arquivo(s))"
  echo "  - Senhas: $SEGREDOS/ (apague para descartá-las)"
  echo "  - Cópias do estado do Terraform: $LOCAL/estado-backups/"
  echo "  - Imagens no registro local (volume todo-nuvem_registry-data)"
  echo "  Custo em nuvem: nenhum (ambiente 100% local)."
}

cmd_parar_localstack() {
  etapa "Parando LocalStack e registro"
  docker compose -f "$LS_COMPOSE" down
  echo "Atenção: o LocalStack Community não guarda estado. Ao subir de novo, rode 'provisionar' para recriar os recursos AWS."
}

# =============================================================================
cmd_ajuda() {
  cat <<'EOF'
Uso: ./scripts/pipeline.sh <rotina> [argumentos]

Infraestrutura
  subir-localstack        sobe LocalStack + registro e cria os segredos
  validar                 testes, shellcheck, terraform validate, compose
  planejar                terraform plan (mostra o que vai mudar)
  provisionar             terraform apply (VPC, SGs, EC2, EBS, S3, IAM + VMs)
  desativar               backup final + terraform destroy  (pede DESTRUIR)
  parar-localstack        desliga o LocalStack

Aplicação
  implantar [versao]      constrói, publica e implanta; com versao = rollback
  versoes                 versões publicadas e histórico de implantações

Operação
  status                  serviços, saúde, rede, disco, backups das duas VMs
  logs-app [serviço] [n]  logs da aplicação (caddy, frontend, backend, todos)
  logs-banco [n]          logs do MongoDB
  reiniciar-app [serviço] reinicia serviços da aplicação (não apaga dados)
  reiniciar-banco         reinicia o MongoDB (não apaga dados)
  backup                  backup agora (S3 + cópia em .local/backups)
  backups                 lista backups no S3
  restaurar-teste [nome]  restaura em ambiente isolado e confere
  restaurar [nome]        restaura NA PRODUÇÃO (pede RESTAURAR)
  limpar-lista            nova lista de demonstração (pede LIMPAR)
  exportar-ca             salva a CA do HTTPS para instalar no navegador

Evidências
  verificar-isolamento    prova que o MongoDB só é acessível pela API
  aceite                  roda os critérios de aceite e salva o relatório
  ciclo-completo          subir-localstack + provisionar + implantar + aceite
EOF
}

rotina=${1:-ajuda}
shift || true
case $rotina in
  subir-localstack)     cmd_subir_localstack ;;
  validar)              cmd_validar ;;
  planejar)             cmd_planejar ;;
  provisionar)          cmd_provisionar ;;
  implantar)            cmd_implantar "$@" ;;
  versoes)              cmd_versoes ;;
  status)               cmd_status ;;
  logs-app)             ops app logs "${1:-todos}" "${2:-200}" ;;
  logs-banco)           ops db logs "${1:-200}" ;;
  reiniciar-app)        ops app restart "${1:-todos}" ;;
  reiniciar-banco)      ops db restart; ops app health; echo ;;
  backup)               cmd_backup ;;
  backups)              ops db backups ;;
  restaurar-teste)      ops db restore-test "${1:-latest}" ;;
  restaurar)            cmd_restaurar "$@" ;;
  limpar-lista)         cmd_limpar_lista ;;
  exportar-ca)          cmd_exportar_ca ;;
  exportar-backup)      cmd_exportar_backup ;;
  verificar-isolamento) ./scripts/verificar-isolamento.sh ;;
  aceite)               cmd_aceite ;;
  ciclo-completo)       cmd_subir_localstack; cmd_provisionar; cmd_implantar; cmd_aceite ;;
  desativar)            cmd_desativar ;;
  parar-localstack)     cmd_parar_localstack ;;
  ajuda|-h|--help)      cmd_ajuda ;;
  *) cmd_ajuda; exit 2 ;;
esac
