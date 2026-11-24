#!/usr/bin/env bash
# Operação da VM da APLICAÇÃO. Instalado em /opt/todo/ops.sh.
# Uso (de fora): ./scripts/pipeline.sh <rotina>   |   dentro da VM: /opt/todo/ops.sh <comando>
#
#   deploy <img-frontend> <img-backend>   implanta/atualiza a aplicação
#   status                                serviços, saúde da API e do banco
#   health                                consulta /health (API + conexão ao banco)
#   logs [servico|todos] [linhas]         logs (caddy, frontend, backend)
#   restart [servico|todos]               reinicia serviços (NÃO apaga dados)
#   ca                                    certificado raiz da CA interna do HTTPS

# shellcheck source=deploy/common.sh
source "$(dirname "$(readlink -f "$0")")/common.sh"

# Consulta /health por dentro da VM, passando pelo Nginx como um visitante faria
consultar_saude() {
  "${COMPOSE[@]}" exec -T frontend wget -q -O - http://127.0.0.1/health 2>/dev/null
}

aguardar_saude() {
  local resp
  for i in $(seq 1 30); do
    if resp=$(consultar_saude) && [[ $resp == *'"status":"ok"'* ]]; then
      log "Saúde OK: $resp"
      return 0
    fi
    sleep 4
    [[ $i == 10 ]] && log "Aguardando a API conectar ao banco..."
  done
  erro "API não ficou saudável. Última resposta: ${resp:-sem resposta}"
  "${COMPOSE[@]}" logs --tail 40 backend >&2 || true
  return 1
}

cmd_deploy() {
  local frontend=${1:?informe a imagem do frontend} backend=${2:?informe a imagem do backend}
  local db_host site
  travar
  db_host=$(atributo db-host)
  site=$(atributo site-address)

  log "Preparando a conexão com o banco ($db_host, rede privada)"
  gravar_segredo "$(atributo secret-app)" "$SECRETS_DIR/.app_pw" root:root 0400
  ( umask 077
    printf 'mongodb://todo_app:%s@%s:27017/todo-app?authSource=todo-app' \
      "$(cat "$SECRETS_DIR/.app_pw")" "$db_host" >"$SECRETS_DIR/mongo_uri.tmp" )
  rm -f "$SECRETS_DIR/.app_pw"
  # 1000 = usuário "node" da imagem da API
  chown 1000:1000 "$SECRETS_DIR/mongo_uri.tmp"
  chmod 0400 "$SECRETS_DIR/mongo_uri.tmp"
  limpar_ponto_montagem "$SECRETS_DIR/mongo_uri"
  mv -f "$SECRETS_DIR/mongo_uri.tmp" "$SECRETS_DIR/mongo_uri"

  cat >"$TODO_DIR/.env" <<EOF
FRONTEND_IMAGE=$frontend
BACKEND_IMAGE=$backend
SITE_ADDRESS=$site
TLS_DIRETIVA="${TODO_TLS_DIRETIVA:-tls internal}"
EOF
  chmod 600 "$TODO_DIR/.env"

  log "Preparando imagens"
  baixar_imagens

  log "Subindo a aplicação"
  "${COMPOSE[@]}" up -d --remove-orphans --wait --wait-timeout 240
  aguardar_saude

  registrar_release "frontend=$frontend backend=$backend"
  docker image prune -f >/dev/null 2>&1 || true
  log "Aplicação publicada em https://$site"
  "${COMPOSE[@]}" ps
}

cmd_status() {
  echo "== Instância $(atributo instance-id) | IP privado $(ip_privado) | IP público $(atributo public-ip)"
  echo
  echo "== Serviços"
  "${COMPOSE[@]}" ps
  echo
  echo "== Saúde (API + conexão com o banco)"
  consultar_saude || echo "sem resposta do /health"
  echo
  echo "== Endereço"
  echo "https://$(atributo site-address)"
  echo
  mostrar_releases
}

comando=${1:-}
shift || true
case $comando in
  deploy)  cmd_deploy "$@" ;;
  boot)    "${COMPOSE[@]}" up -d ;;
  ca)      "${COMPOSE[@]}" exec -T caddy cat /data/caddy/pki/authorities/local/root.crt ;;
  status)  cmd_status ;;
  health)  consultar_saude; echo ;;
  logs)    cmd_logs "$@" ;;
  restart) travar; cmd_restart "$@"; aguardar_saude ;;
  *) sed -n '2,11p' "$0"; exit 2 ;;
esac
