#!/usr/bin/env bash
# =============================================================================
# Pipelines do ToDo App no Google Cloud (duas VMs reais).
# Pré-requisitos: Docker, gcloud autenticado, Git Bash/Linux (ssh, curl,
# openssl), Node.js e infra/gcp/terraform.tfvars (veja terraform.tfvars.example).
#
#   ./scripts/pipeline-gcp.sh ajuda
#
# O ambiente LocalStack continua em ./scripts/pipeline.sh, independente deste.
# =============================================================================
set -euo pipefail
export MSYS_NO_PATHCONV=1
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

RAIZ=$(cd "$(dirname "$0")/.." && pwd)
cd "$RAIZ"
RAIZ_DOCKER=$( (pwd -W 2>/dev/null || pwd) | tr -d '\r')

LOCAL=$RAIZ/.local/gcp # não versionado
SEGREDOS=$LOCAL/segredos
EVIDENCIAS=$RAIZ/.local/evidencias
CHAVE=$LOCAL/ssh/id_ed25519
SSH_CFG=$LOCAL/ssh/config
TFVARS=infra/gcp/terraform.tfvars
TF_IMAGE=hashicorp/terraform:1.9.8
APIS=(compute iap secretmanager artifactregistry iam storage cloudresourcemanager)

etapa() { printf '\n==> %s\n' "$*"; }
ok()    { printf '  [OK] %s\n' "$*"; }
falha() { printf '  [FALHA] %s\n' "$*" >&2; }
morrer() { falha "$*"; exit 1; }
dir_privado() { mkdir -p "$1"; chmod 700 "$1" 2>/dev/null || true; }

# Valor de uma variável do terraform.tfvars
tfvar() {
  local v
  v=$(sed -nE "s/^ *$1 *= *\"([^\"]*)\".*/\1/p" "$TFVARS" 2>/dev/null | tail -n 1)
  echo "${v:-${2:-}}"
}
PROJETO=$(tfvar project_id)
REGIAO=$(tfvar region us-east1)
ZONA=$(tfvar zone us-east1-b)
BUCKET_ESTADO=${PROJETO}-todo-tfstate

# No Git Bash, o script do gcloud precisa da conversão de caminhos desligada acima
gcloud() { env -u MSYS_NO_PATHCONV gcloud "$@"; }
gc() { gcloud --project "$PROJETO" --quiet "$@"; }

# O token do gcloud (1 hora) segue por variável de ambiente, fora da linha de comando
tf() {
  GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token | tr -d '\r')
  export GOOGLE_OAUTH_ACCESS_TOKEN
  docker run --rm -i -v "$RAIZ_DOCKER:/work" -w /work/infra/gcp \
    -e GOOGLE_OAUTH_ACCESS_TOKEN -e TF_IN_AUTOMATION=1 -e TF_INPUT=0 \
    -e TF_VAR_ssh_public_key="$(cat "$CHAVE.pub" 2>/dev/null)" "$TF_IMAGE" "$@"
}
saida() { tf output -raw "$1"; }

vm()  { local papel=$1; shift; ssh -F "$SSH_CFG" "todo-$papel" "$@"; }
# ssh -n: não consome a entrada padrão do script
ops() { local papel=$1; shift; ssh -n -F "$SSH_CFG" "todo-$papel" sudo /opt/todo/ops.sh "$@"; }

confirmar() {
  local palavra=$1 msg=$2 resp
  [[ ${CONFIRMAR:-} == "$palavra" ]] && return 0
  [[ -t 0 ]] || morrer "$msg Para executar sem terminal, defina CONFIRMAR=$palavra."
  printf '%s\nDigite %s para continuar: ' "$msg" "$palavra"
  read -r resp
  [[ $resp == "$palavra" ]] || morrer "cancelado"
}

# ---------------------------------------------------------------------------
cmd_verificar() {
  etapa "Pré-requisitos"
  local c
  for c in docker gcloud ssh ssh-keygen curl openssl node; do
    command -v "$c" >/dev/null && ok "$c" || morrer "falta o comando $c"
  done
  [[ -s $TFVARS ]] || morrer "falta o arquivo $TFVARS"
  [[ $PROJETO =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ && $PROJETO != *xxxxx ]] || morrer "project_id inválido em $TFVARS"
  gcloud projects describe "$PROJETO" --format='value(lifecycleState)' 2>/dev/null | grep -q ACTIVE \
    || morrer "projeto $PROJETO não encontrado ou sem acesso"
  ok "projeto $PROJETO"
  # No GitHub Actions a identidade não enxerga o faturamento (nem precisa)
  if [[ -z ${GITHUB_ACTIONS:-} ]]; then
    [[ $(gcloud billing projects describe "$PROJETO" --format='value(billingEnabled)' 2>/dev/null | tr -d '\r') == True ]] \
      || morrer "o projeto $PROJETO não tem faturamento vinculado (o Compute Engine exige)"
    ok "faturamento vinculado"
  fi
  preparar_local
}

# Chave SSH e senhas: geradas aqui, guardadas em .local/gcp e nunca exibidas
preparar_local() {
  dir_privado "$LOCAL/ssh"
  dir_privado "$SEGREDOS"
  # Em CI a chave vem de um segredo do GitHub: gerar outra trocaria o acesso às VMs
  [[ -s $CHAVE || -z ${GITHUB_ACTIONS:-} ]] || morrer "chave SSH ausente (segredo TODO_SSH_KEY)"
  [[ -s $CHAVE ]] || ssh-keygen -q -t ed25519 -N '' -C todo-app -f "$CHAVE"
  local s
  for s in mongo-root-password mongo-app-password; do
    [[ -s $SEGREDOS/$s ]] || (umask 077; openssl rand -hex 24 | tr -cd '0-9a-f' >"$SEGREDOS/$s")
  done
  ok "chave SSH e senhas em .local/gcp"
}

# Uma vez por projeto: ativa as APIs e cria o bucket do estado do Terraform
cmd_bootstrap() {
  cmd_verificar
  confirmar PREPARAR "Isto ATIVA APIs e cria um bucket privado para o estado no projeto $PROJETO."
  etapa "Ativando APIs"
  gc services enable "${APIS[@]/%/.googleapis.com}"
  etapa "Bucket do estado ($BUCKET_ESTADO)"
  if gc storage buckets describe "gs://$BUCKET_ESTADO" >/dev/null 2>&1; then
    ok "já existe"
  else
    gc storage buckets create "gs://$BUCKET_ESTADO" --location="$REGIAO" \
      --uniform-bucket-level-access --public-access-prevention
  fi
  gc storage buckets update "gs://$BUCKET_ESTADO" --versioning
  ok "versionamento ligado"
}

cmd_validar() {
  etapa "Terraform e scripts (GCP)"
  local dir
  for dir in infra/gcp infra/gcp-ci; do
    docker run --rm -v "$RAIZ_DOCKER:/work" -w "/work/$dir" "$TF_IMAGE" fmt -check -recursive -diff
    docker run --rm -v "$RAIZ_DOCKER:/work" -w "/work/$dir" -e TF_DATA_DIR=/tmp/tf --entrypoint sh "$TF_IMAGE" \
      -c 'terraform init -backend=false -input=false >/dev/null && terraform validate'
  done
  docker run --rm -v "$RAIZ_DOCKER:/mnt" -w /mnt koalaman/shellcheck:stable -x -S warning \
    deploy/common.sh deploy/app/ops.sh deploy/db/ops.sh deploy/gcp/preparar-vm.sh scripts/pipeline-gcp.sh
  ok "validado"
}

tf_init() { tf init -input=false -reconfigure -backend-config="bucket=$BUCKET_ESTADO" >/dev/null; }

cmd_planejar() {
  cmd_verificar
  etapa "Terraform plan (nada é executado)"
  tf_init
  tf plan -out=tfplan
}

# Aplica exatamente o plano já exibido por "planejar"
cmd_provisionar() {
  [[ -s infra/gcp/tfplan ]] || morrer "rode antes: planejar (e confira o plano)"
  confirmar CRIAR "Isto CRIA ou ALTERA recursos no projeto $PROJETO conforme o plano exibido (pode gerar cobrança)."
  etapa "Terraform apply"
  tf apply tfplan
  rm -f infra/gcp/tfplan
  publicar_segredos
  cmd_preparar
  etapa "Inventário"
  tf output -json inventario
}

# O valor vai por stdin: não aparece em argumentos nem no estado do Terraform
publicar_segredos() {
  etapa "Segredos do MongoDB (Secret Manager)"
  local s
  for s in mongo-root-password mongo-app-password; do
    if [[ -n $(gc secrets versions list "todo-$s" --filter='state=ENABLED' --limit=1 --format='value(name)') ]]; then
      ok "todo-$s: já tem valor"
    else
      gc secrets versions add "todo-$s" --data-file=- <"$SEGREDOS/$s" >/dev/null
      ok "todo-$s: criado"
    fi
  done
}

# O gcloud no Windows imprime um erro inofensivo ao fechar o túnel: vai para iap.log
# SSH por dentro do IAP: exige login Google com permissão; porta 22 fechada na internet
gerar_ssh_config() {
  cat >"$SSH_CFG" <<EOF
Host todo-*
  User todo
  IdentityFile "$CHAVE"
  IdentitiesOnly yes
  ProxyCommand env -u MSYS_NO_PATHCONV gcloud compute start-iap-tunnel %h 22 --listen-on-stdin --project=$PROJETO --zone=$ZONA --verbosity=error 2>>"$LOCAL/ssh/iap.log"
  UserKnownHostsFile "$LOCAL/ssh/known_hosts"
  StrictHostKeyChecking accept-new
  ConnectTimeout 40
  ServerAliveInterval 20
EOF
}

cmd_preparar() {
  etapa "Preparando as VMs (Docker, swap, disco de dados)"
  gerar_ssh_config
  local papel i
  for papel in app db; do
    for i in $(seq 1 20); do
      vm "$papel" true </dev/null >/dev/null 2>&1 && break
      (( i < 20 )) || morrer "sem SSH em todo-$papel (confira a permissão de IAP da sua conta)"
      sleep 10
    done
    vm "$papel" "sudo bash -s -- $papel" <deploy/gcp/preparar-vm.sh
  done
}

# Arquivos de operação e variáveis da instância
sincronizar() {
  local papel=$1
  tar -C deploy -cf - common.sh -C "$papel" . \
    | vm "$papel" 'sudo tar --no-same-owner -xf - -C /opt/todo && sudo chmod 755 /opt/todo/ops.sh /opt/todo/common.sh'
  {
    echo "export TODO_CLOUD=gcp TODO_ROLE=$papel TODO_PROJECT=$PROJETO"
    echo "export TODO_REGISTRY_HOST=${REGIAO}-docker.pkg.dev"
    echo "export TODO_INSTANCE_ID=$(saida "${papel}_instance_id")"
    echo "export TODO_PRIVATE_IP=$(saida "${papel}_private_ip")"
    echo "export TODO_SECRET_APP=todo-mongo-app-password"
    if [[ $papel == app ]]; then
      echo "export TODO_PUBLIC_IP=$(saida app_public_ip)"
      echo "export TODO_DB_HOST=$(saida db_private_ip)"
      echo "export TODO_SITE_ADDRESS=$(saida site_address)"
      echo "export TODO_TLS_DIRETIVA='# certificado publico automatico'"
    else
      echo "export TODO_MONGO_ALLOWED_FROM=$(saida app_private_ip)"
      echo "export TODO_SECRET_ROOT=todo-mongo-root-password"
      echo "export TODO_BACKUP_BUCKET=$(saida backup_bucket)"
    fi
  } | vm "$papel" 'sudo sh -c "umask 077; cat >/opt/todo/instancia.env"'
}

versao_atual() {
  local v
  v=$(git rev-parse --short=7 HEAD 2>/dev/null || echo semgit)
  [[ -z $(git status --porcelain -- frontend backend banco-de-dados 2>/dev/null) ]] || v="$v-local$(date +%m%d%H%M)"
  echo "$v"
}
# Muda só quando banco-de-dados/ muda: atualizar a aplicação não reinicia o MongoDB
tag_banco() { echo "db-$(cat banco-de-dados/Dockerfile banco-de-dados/*.js | sha256sum | cut -c1-10)"; }

imagem_existe() { gc artifacts docker images describe "$1" >/dev/null 2>&1; }

publicar_imagem() {
  local pasta=$1 img=$2
  if imagem_existe "$img"; then ok "${img##*/} (já publicada)"; return 0; fi
  docker buildx build -q --platform linux/amd64 --provenance=false --load -t "$img" "./$pasta" >/dev/null
  docker push -q "$img" >/dev/null
  ok "${img##*/}"
}

cmd_implantar() {
  local versao=${1:-} rollback="" reg imgdb url
  gerar_ssh_config
  reg=$(saida registry)
  imgdb="$reg/mongo:$(tag_banco)"
  if [[ -n $versao ]]; then
    rollback=1
    imagem_existe "$reg/frontend:$versao" && imagem_existe "$reg/backend:$versao" \
      || morrer "versão $versao não encontrada no registro (veja: versoes)"
  else
    versao=$(versao_atual)
    etapa "Construindo e publicando imagens ($versao)"
    gcloud auth print-access-token | tr -d '\r\n' \
      | docker login -u oauth2accesstoken --password-stdin "https://${REGIAO}-docker.pkg.dev" >/dev/null 2>&1 \
      || morrer "login no Artifact Registry falhou"
    publicar_imagem frontend "$reg/frontend:$versao"
    publicar_imagem backend "$reg/backend:$versao"
    publicar_imagem banco-de-dados "$imgdb"
  fi

  etapa "Banco: implantar"
  if [[ -n $rollback ]]; then
    echo "Rollback da aplicação: o banco permanece como está (os dados não voltam no tempo)"
  else
    sincronizar db
    ops db deploy "$imgdb"
  fi
  etapa "Aplicação: implantar"
  sincronizar app
  ops app deploy "$reg/frontend:$versao" "$reg/backend:$versao"

  printf '%s versao=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$versao" >>"$LOCAL/releases.log"
  url=$(saida app_url)
  etapa "Verificação pelo endereço público"
  aguardar_saude "$url" 180
  ./scripts/smoke-test.sh "$url"
  ok "Versão $versao no ar em $url"
}

cmd_versoes() {
  etapa "Versões no registro (disponíveis para rollback)"
  gc artifacts docker tags list "$(saida registry)/frontend" --format='table(tag)'
  etapa "Histórico de implantações"
  tail -n 10 "$LOCAL/releases.log" 2>/dev/null || echo "(nenhuma)"
}

aguardar_saude() {
  local url=$1 limite=${2:-90} resp=""
  for _ in $(seq 1 $((limite / 3))); do
    resp=$(curl -fsS --max-time 10 "$url/health" 2>/dev/null || true)
    [[ $resp == *'"banco":"ok"'* ]] && return 0
    sleep 3
  done
  morrer "aplicação não ficou saudável em $url: ${resp:-sem resposta}"
}

cmd_backup() {
  ops db backup manual
  dir_privado "$RAIZ/.local/backups"
  local destino
  destino="$RAIZ/.local/backups/gcp-$(date -u +%Y%m%dT%H%M%SZ).archive.gz"
  ops db export >"$destino"
  [[ -s $destino ]] || { rm -f "$destino"; morrer "exportação vazia"; }
  ok "Cópia fora da nuvem: $destino"
}

# ---------------------------------------------------------------------------
# Evidências
# ---------------------------------------------------------------------------
porta_aberta() { timeout 6 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; }

cmd_isolamento() {
  local pub db ip_db erros=0 saude escuta
  gerar_ssh_config
  pub=$(saida app_public_ip)
  db=$(saida db_private_ip)
  etapa "ACE-03 · Isolamento do banco"
  checar() { if [[ $1 == 0 ]]; then ok "$2"; else falha "$2"; erros=$((erros + 1)); fi; }
  # Pergunta à própria GCP (não ao estado) e exige resposta: sem resposta, reprova
  ip_db=$(gc compute instances describe todo-db --zone="$ZONA" --format='json(networkInterfaces)' || true)
  if [[ $ip_db != *networkIP* ]]; then checar 1 "não foi possível consultar a VM do banco"
  elif [[ $ip_db == *natIP* || $ip_db == *accessConfigs* ]]; then checar 1 "VM do banco tem IP público"
  else checar 0 "VM do banco sem IP público (privado: $db)"; fi
  gc compute firewall-rules list --filter='network:todo-vpc' \
    --format='table(name,direction,sourceRanges.list(),sourceServiceAccounts.list(),allowed[].map().firewall_rule().list())'
  porta_aberta "$pub" 27017 && checar 1 "27017 responde na internet" || checar 0 "27017 fechada na internet ($pub)"
  porta_aberta "$pub" 22 && checar 1 "22 responde na internet" || checar 0 "22 fechada na internet ($pub)"
  porta_aberta "$db" 27017 && checar 1 "banco responde a esta máquina" || checar 0 "banco inacessível desta máquina ($db)"
  porta_aberta "$pub" 443 && checar 0 "443 responde (o teste de porta funciona)" || checar 1 "443 não responde"
  vm app "nc -z -w 4 $db 27017" </dev/null && checar 0 "VM da aplicação alcança o banco pela rede privada" || checar 1 "VM da aplicação não alcança o banco"
  escuta=$(vm db "sudo ss -ltnH 'sport = :27017' | awk '{print \$4}' | sort -u | xargs" </dev/null || true)
  [[ $escuta == "$db:27017" ]] && checar 0 "MongoDB escuta apenas em $escuta" || checar 1 "MongoDB escuta em: $escuta"
  saude=$(ops app health || true)
  [[ $saude == *'"banco":"ok"'* ]] && checar 0 "API conectada ao banco" || checar 1 "API sem banco: $saude"
  (( erros == 0 )) || return 1
}

cmd_aceite() {
  mkdir -p "$EVIDENCIAS"
  local log rc
  gerar_ssh_config
  log="$EVIDENCIAS/aceite-gcp-$(date -u +%Y%m%dT%H%M%SZ).log"
  # Subshell próprio com "set -e": qualquer verificação que falhe reprova o aceite
  set +e
  ( set -e; aceite_execucao ) 2>&1 | tee "$log"
  rc=${PIPESTATUS[0]}
  set -e
  echo "Evidências salvas em $log"
  if (( rc == 0 )); then ok "aceite concluído"; else falha "aceite reprovado"; fi
  return "$rc"
}

aceite_execucao() {
  local url marca id atual conteineres
  url=$(saida app_url)
  echo "Relatório de aceite (GCP) - $(date -u '+%Y-%m-%d %H:%M UTC') - $(git rev-parse --short HEAD) - $url"

  etapa "ACE-02 · Inventário"
  tf output -json inventario
  conteineres=$(vm db "sudo docker ps --format '{{.Names}}'" </dev/null)
  grep -qx todo-mongo <<<"$conteineres"
  ok "MongoDB na VM do banco"
  conteineres=$(vm app "sudo docker ps --format '{{.Names}}'" </dev/null)
  if grep -qi mongo <<<"$conteineres"; then morrer "MongoDB na VM da aplicação"; fi
  ok "nenhum MongoDB na VM da aplicação"

  cmd_isolamento

  etapa "ACE-04 · Aplicação pública por HTTPS"
  ./scripts/smoke-test.sh "$url" --completo
  curl -sS -w 'HTTP -> %{http_code} %{redirect_url}\n' "${url/https:/http:}/" | tail -n 1

  etapa "ACE-05 · Persistência"
  marca="persistencia-$(date +%s)"
  id=$(curl -fsS -X POST -H 'Content-Type: application/json' -d "{\"text\":\"$marca\"}" "$url/todos" | sed -E 's/.*"_id":"([^"]+)".*/\1/')
  curl -fsS -X PATCH "$url/todos/$id" >/dev/null
  concluida() { curl -fsS "$url/todos" | tr '}' '\n' | grep "$marca" | grep -q '"completed":true'; }
  vm db "cd /opt/todo && sudo docker compose up -d --force-recreate --wait mongo && sudo /opt/todo/ops.sh boot" </dev/null >/dev/null 2>&1
  aguardar_saude "$url"
  concluida
  ok "preservada após recriar o contêiner do banco"
  vm db "sudo systemctl reboot" </dev/null >/dev/null 2>&1 || true
  sleep 40
  aguardar_saude "$url" 300
  concluida
  ok "preservada após reiniciar a VM do banco"
  atual=$(vm app "sudo sh -c '. /opt/todo/.env; echo \$FRONTEND_IMAGE \$BACKEND_IMAGE'" </dev/null)
  # shellcheck disable=SC2086
  ops app deploy $atual >/dev/null
  concluida
  ok "preservada após atualizar a aplicação"
  curl -fsS -X DELETE "$url/todos/$id" >/dev/null

  etapa "ACE-07 · Backup e restauração isolada"
  vm db "cat /etc/cron.d/todo-backup" </dev/null
  ops db backup aceite
  ops db restore-test latest

  etapa "ACE-08 · Operação e credenciais"
  ops app health
  ops app logs backend 5
  local s valor papel registros
  for s in todo-mongo-root-password todo-mongo-app-password; do
    # Valor real em uso, direto do Secret Manager; vazio invalidaria a busca
    valor=$(gc secrets versions access latest --secret="$s" | tr -d '\r\n')
    [[ ${#valor} -ge 20 ]] || morrer "não foi possível ler $s para a verificação"
    if git grep -qF "$valor"; then morrer "senha no código versionado"; fi
    for papel in app db; do
      registros=$(vm "$papel" "cd /opt/todo && sudo docker compose logs --no-color 2>&1" </dev/null)
      if grep -qF "$valor" <<<"$registros"; then morrer "senha nos logs de $papel"; fi
    done
    if grep -rqF "$valor" "$EVIDENCIAS"; then morrer "senha nas evidências"; fi
  done
  ok "nenhuma senha no código, nos logs ou nas evidências"
}

# ---------------------------------------------------------------------------
# Custos: pausar entre o ensaio e a feira
# ---------------------------------------------------------------------------
# O NAT só serve para instalar pacotes na VM do banco. A escolha fica gravada em
# nat.auto.tfvars (não versionado), para os próximos planos não a desfazerem.
cmd_nat() {
  local valor
  case ${1:-} in
    ligar) valor=true ;;
    desligar) valor=false ;;
    *) morrer "uso: nat ligar|desligar" ;;
  esac
  tf_init
  echo "saida_internet_banco = $valor" >infra/gcp/nat.auto.tfvars
  etapa "NAT do banco: $1"
  tf apply -auto-approve -target=google_compute_router.todo -target=google_compute_router_nat.todo
  # O apply parcial não atualiza as saídas (inventário); este só relê a situação real
  tf apply -refresh-only -auto-approve >/dev/null
}

cmd_pausar() {
  confirmar PAUSAR "Isto DESLIGA as duas VMs e o NAT: a aplicação sai do ar. Os dados são mantidos."
  gerar_ssh_config
  cmd_backup
  # Aplicação primeiro, para ninguém gravar enquanto o banco desliga
  gc compute instances stop todo-app --zone="$ZONA"
  gc compute instances stop todo-db --zone="$ZONA"
  cmd_nat desligar
  echo "ATENÇÃO: com a VM desligada, o IP reservado cobra cerca de 0,01 dólar por hora."
  echo "Dentro da cota grátis, deixar ligado sai mais barato do que pausar."
}

cmd_retomar() {
  gc compute instances start todo-db todo-app --zone="$ZONA"
  aguardar_saude "$(saida app_url)" 300
  ok "no ar em $(saida app_url)"
}

# ---------------------------------------------------------------------------
cmd_desativar() {
  confirmar DESTRUIR "Isto REMOVE do projeto $PROJETO as VMs, a rede, o disco de dados e TODOS os backups do bucket."
  gerar_ssh_config
  etapa "Backup final (cópia local)"
  cmd_backup
  etapa "Terraform destroy"
  tf_init
  tf destroy -auto-approve
  etapa "O que permanece"
  echo "  - Nesta máquina: .local/backups (dados) e .local/gcp (senhas e chave SSH)"
  echo "  - Na GCP: o bucket do estado gs://$BUCKET_ESTADO e o projeto $PROJETO."
  echo "    Para garantir custo zero, encerre o projeto: gcloud projects delete $PROJETO"
}

cmd_ajuda() {
  cat <<'EOF'
Uso: ./scripts/pipeline-gcp.sh <rotina> [argumentos]

  verificar               pré-requisitos; gera chave SSH e senhas
  bootstrap               ativa APIs e cria o bucket do estado (pede PREPARAR)
  validar                 terraform fmt/validate e shellcheck
  planejar                terraform plan
  provisionar             aplica o plano exibido e prepara as VMs (pede CRIAR)
  preparar                refaz a preparação das VMs
  implantar [versao]      constrói, publica e implanta; com versao = rollback
  versoes                 versões disponíveis e histórico
  status                  estado das duas VMs
  logs-app [serviço] [n]  logs da aplicação
  logs-banco [n]          logs do MongoDB
  reiniciar-app [serviço] reinicia a aplicação
  reiniciar-banco         reinicia o MongoDB
  backup | backups        gera (nuvem + cópia local) | lista
  restaurar-teste [nome]  restaura em ambiente isolado
  restaurar [nome]        restaura NA PRODUÇÃO (pede RESTAURAR)
  limpar-lista            nova lista de demonstração (pede LIMPAR)
  verificar-isolamento    evidências do ACE-03
  aceite                  critérios de aceite, com relatório
  nat ligar|desligar      saída de internet da VM do banco
  pausar                  desliga VMs e NAT, mantém os dados (pede PAUSAR)
  retomar                 religa as VMs e confere a saúde
  desativar               remove tudo (pede DESTRUIR)
EOF
}

rotina=${1:-ajuda}
shift || true
case $rotina in
  verificar)            cmd_verificar ;;
  bootstrap)            cmd_bootstrap ;;
  validar)              cmd_validar ;;
  planejar)             cmd_planejar ;;
  provisionar)          cmd_provisionar ;;
  preparar)             cmd_preparar ;;
  implantar)            cmd_implantar "$@" ;;
  versoes)              cmd_versoes ;;
  status)               ops app status; ops db status ;;
  logs-app)             ops app logs "${1:-todos}" "${2:-200}" ;;
  logs-banco)           ops db logs "${1:-200}" ;;
  reiniciar-app)        ops app restart "${1:-todos}" ;;
  reiniciar-banco)      ops db restart; ops app health ;;
  backup)               cmd_backup ;;
  backups)              ops db backups ;;
  restaurar-teste)      ops db restore-test "${1:-latest}" ;;
  restaurar)            confirmar RESTAURAR "Isto SUBSTITUI os dados de produção (um backup é feito antes)."
                        ops db restore "${1:-latest}"; ops app health ;;
  limpar-lista)         confirmar LIMPAR "Isto APAGA a lista atual (um backup é feito antes)."
                        ops db reset-list ;;
  verificar-isolamento) cmd_isolamento ;;
  aceite)               cmd_aceite ;;
  nat)                  cmd_nat "$@" ;;
  pausar)               cmd_pausar ;;
  retomar)              cmd_retomar ;;
  desativar)            cmd_desativar ;;
  ajuda|-h|--help)      cmd_ajuda ;;
  *) cmd_ajuda; exit 2 ;;
esac
