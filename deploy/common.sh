#!/usr/bin/env bash
# Funções compartilhadas pelos scripts de operação das duas VMs.
# Carregado por /opt/todo/ops.sh (não executar diretamente).
#
# Regra de ouro: nenhuma função imprime senhas. Segredos são lidos do Secrets
# Manager direto para arquivos com permissão restrita.

set -euo pipefail

TODO_DIR=/opt/todo
SECRETS_DIR=$TODO_DIR/secrets
RELEASES_LOG=$TODO_DIR/releases.log
COMPOSE=(docker compose --project-directory "$TODO_DIR" -f "$TODO_DIR/compose.yaml")

# Na GCP as variáveis da instância vêm de arquivo (gravado pelo pipeline);
# no LocalStack elas já estão no ambiente da VM.
if [[ -z ${TODO_ROLE:-} && -f $TODO_DIR/instancia.env ]]; then
  # shellcheck source=/dev/null
  . "$TODO_DIR/instancia.env"
fi
NUVEM=${TODO_CLOUD:-aws}

log()  { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
erro() { printf '[%s] ERRO: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
falhar() { erro "$*"; exit 1; }

# "Metadados da instância": variáveis definidas pelo Terraform na VM
# (TODO_*), equivalentes às tags/metadados de uma EC2.
atributo() {
  local nome="TODO_${1^^}"
  nome=${nome//-/_}
  [[ -n ${!nome:-} ]] || falhar "variável da instância $nome não definida"
  printf '%s' "${!nome}"
}
ip_privado() { atributo private-ip; }

# --- GCP -------------------------------------------------------------------
# Token temporário da conta de serviço da VM, obtido dos metadados. Vai para o
# curl por arquivo de configuração (nunca na linha de comando, visível no ps).
gcp_token() {
  curl -fsS --retry 3 -H 'Metadata-Flavor: Google' \
    http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token | jq -er .access_token
}
gcp_curl() {
  local t
  t=$(gcp_token) || return 1
  curl -fsS --retry 3 -K <(printf 'header = "Authorization: Bearer %s"\n' "$t") "$@"
}

# Lê um segredo para a saída padrão.
ler_segredo() {
  if [[ $NUVEM == gcp ]]; then
    gcp_curl "https://secretmanager.googleapis.com/v1/projects/$(atributo project)/secrets/$1/versions/latest:access" \
      | jq -er .payload.data | base64 -d
  else
    aws secretsmanager get-secret-value --secret-id "$1" --query SecretString --output text
  fi
}

# Baixa as imagens do registro (na GCP, login temporário no Artifact Registry)
baixar_imagens() {
  if [[ $NUVEM == gcp ]]; then
    gcp_token | docker login -u oauth2accesstoken --password-stdin "https://$(atributo registry-host)" >/dev/null 2>&1 \
      || falhar "login no registro de imagens falhou"
  fi
  "${COMPOSE[@]}" pull --quiet
}

# Armazenamento de backups (S3 ou Cloud Storage) com a mesma interface.
GCS=https://storage.googleapis.com
url_objeto() { jq -rn --arg n "$1" '$n|@uri'; }

#   objeto_copiar <origem> <destino>   ("-" = saída padrão)
objeto_copiar() {
  local origem=$1 destino=$2 nome
  if [[ $NUVEM != gcp ]]; then
    aws s3 cp --only-show-errors "$origem" "$destino"
  elif [[ $destino == gs://* ]]; then
    nome=${destino#gs://*/}
    [[ $destino == */ ]] && nome+=$(basename "$origem")
    # ifGenerationMatch=0: falha se o objeto já existir
    gcp_curl -X POST -H 'Content-Type: application/gzip' --data-binary "@$origem" \
      "$GCS/upload/storage/v1/b/$(atributo backup-bucket)/o?uploadType=media&ifGenerationMatch=0&name=$(url_objeto "$nome")" >/dev/null
  else
    gcp_curl -o "$destino" "$GCS/storage/v1/b/$(atributo backup-bucket)/o/$(url_objeto "${origem#gs://*/}")?alt=media"
  fi
}

#   objeto_listar <prefixo>   linhas "data hora tamanho nome", como "aws s3 ls"
objeto_listar() {
  if [[ $NUVEM != gcp ]]; then
    aws s3 ls "$1"
  else
    gcp_curl "$GCS/storage/v1/b/$(atributo backup-bucket)/o?maxResults=1000&prefix=$(url_objeto "${1#gs://*/}")" \
      | jq -r '.items[]? | [(.timeCreated[0:19] | sub("T";" ")), .size, (.name | split("/") | last)] | join(" ")'
  fi
}

# Grava um segredo em arquivo, sem passar pelo terminal.
#   gravar_segredo <nome-do-segredo> <arquivo> <dono> <modo>
gravar_segredo() {
  local nome=$1 destino=$2 dono=$3 modo=$4 tmp
  install -d -m 700 "$SECRETS_DIR"
  tmp=$(mktemp "$SECRETS_DIR/.tmp.XXXXXX")
  if ! ler_segredo "$nome" >"$tmp" 2>/dev/null; then
    rm -f "$tmp"
    falhar "não foi possível ler o segredo '$nome' (verifique se ele existe e se a VM tem acesso)"
  fi
  # Remove quebra de linha final, se houver
  printf '%s' "$(cat "$tmp")" >"$tmp"
  chown "$dono" "$tmp"
  chmod "$modo" "$tmp"
  limpar_ponto_montagem "$destino"
  mv -f "$tmp" "$destino"
}

# Se um contêiner antigo subiu antes do deploy (ex.: VM recriada com o disco
# do Docker preservado), o Docker cria DIRETÓRIOS vazios no lugar dos arquivos
# montados que ainda não existiam. Remove esses diretórios antes de gravar.
limpar_ponto_montagem() {
  if [[ -d $1 ]]; then
    rmdir "$1" 2>/dev/null || rm -rf "$1"
  fi
}

registrar_release() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$RELEASES_LOG"
}

mostrar_releases() {
  log "Últimas versões implantadas nesta VM:"
  if [[ -f $RELEASES_LOG ]]; then tail -n 5 "$RELEASES_LOG"; else echo "(nenhuma)"; fi
}

# Impede duas operações de escrita ao mesmo tempo (ex.: backup durante restore)
travar() {
  [[ ${TODO_LOCK:-} == 1 ]] && return 0
  exec 9>/var/lock/todo-ops.lock
  flock -w 300 9 || falhar "outra operação está em andamento nesta VM"
  TODO_LOCK=1
}

cmd_logs() {
  local servico=${1:-} linhas=${2:-200}
  [[ $servico == todos ]] && servico=""
  # shellcheck disable=SC2086
  "${COMPOSE[@]}" logs --no-color --timestamps --tail "$linhas" $servico
}

cmd_restart() {
  local servico=${1:-}
  [[ $servico == todos ]] && servico=""
  log "Reiniciando ${servico:-todos os serviços}"
  # shellcheck disable=SC2086
  "${COMPOSE[@]}" restart $servico
  "${COMPOSE[@]}" up -d --wait --wait-timeout 180
  "${COMPOSE[@]}" ps
}
