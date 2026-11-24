#!/usr/bin/env bash
# Teste de fumaça do ToDo App por um endereço público (o mesmo caminho do visitante).
#
#   ./scripts/smoke-test.sh <url-base> [--completo]
#
# Padrão (somente leitura): página inicial, /health e GET /todos.
# --completo: também cadastra, conclui, reabre e exclui uma tarefa própria do
#             teste (usado no CI; em produção altera a lista por instantes).

set -euo pipefail

BASE=${1:?uso: $0 <url-base> [--completo]}
BASE=${BASE%/}
MODO=${2:-}
CURL=(curl -fsS --max-time 15 --retry 3 --retry-delay 3 --retry-all-errors)
# HTTPS com CA própria (ambiente LocalStack): valida a cadeia em vez de ignorá-la
if [[ -n ${SMOKE_CACERT:-} ]]; then CURL+=(--cacert "$SMOKE_CACERT" --ssl-no-revoke); fi

ok()    { printf '  [OK] %s\n' "$*"; }
falha() { printf '  [FALHA] %s\n' "$*" >&2; exit 1; }
command -v node >/dev/null || { echo "smoke-test precisa do Node.js (https://nodejs.org)" >&2; exit 1; }
json()  { node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{const o=JSON.parse(s);console.log($1)})"; }

echo "Teste de fumaça em $BASE"

pagina=$("${CURL[@]}" "$BASE/")
[[ $pagina == *'<div id="root">'* ]] || falha "página inicial não contém a aplicação React"
ok "GET / entrega a interface"

saude=$("${CURL[@]}" "$BASE/health")
[[ $(json 'o.status' <<<"$saude") == ok && $(json 'o.banco' <<<"$saude") == ok ]] \
  || falha "/health não está ok: $saude"
ok "GET /health: API e banco ok"

total=$("${CURL[@]}" "$BASE/todos" | json 'o.length')
ok "GET /todos: $total tarefa(s)"

if [[ $MODO == --completo ]]; then
  texto="teste-automatico-$(date +%s)"
  criada=$("${CURL[@]}" -X POST -H 'Content-Type: application/json' -d "{\"text\":\"$texto\"}" "$BASE/todos")
  id=$(json 'o._id' <<<"$criada")
  [[ $(json 'o.completed' <<<"$criada") == false ]] || falha "tarefa não foi criada pendente"
  ok "POST /todos: tarefa criada ($id)"

  "${CURL[@]}" "$BASE/todos" | json "o.some(t=>t._id==='$id')" | grep -q true || falha "tarefa não aparece na lista"
  ok "GET /todos: tarefa listada"

  [[ $("${CURL[@]}" -X PATCH "$BASE/todos/$id" | json 'o.completed') == true ]] || falha "não concluiu"
  ok "PATCH /todos/:id: concluída"
  [[ $("${CURL[@]}" -X PATCH "$BASE/todos/$id" | json 'o.completed') == false ]] || falha "não reabriu"
  ok "PATCH /todos/:id: reaberta"

  "${CURL[@]}" -X DELETE "$BASE/todos/$id" >/dev/null
  "${CURL[@]}" "$BASE/todos" | json "o.some(t=>t._id==='$id')" | grep -q false || falha "tarefa não foi excluída"
  ok "DELETE /todos/:id: excluída"

  # Código HTTP lido da última linha (sem "-o /dev/null", que o curl do Windows não entende)
  codigo=$(curl -s ${SMOKE_CACERT:+--cacert "$SMOKE_CACERT" --ssl-no-revoke} -w '\n%{http_code}' \
    -X POST -H 'Content-Type: application/json' -d '{}' "$BASE/todos" | tail -n 1)
  [[ $codigo == 400 ]] || falha "POST sem texto deveria retornar 400 (veio $codigo)"
  ok "POST /todos sem texto: 400"
fi

echo "Teste de fumaça concluído com sucesso"
