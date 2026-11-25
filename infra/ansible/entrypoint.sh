#!/usr/bin/env bash
# Copia a chave para um local com permissão restrita: em volumes do Windows ela
# chega como 0777, e o ssh recusa chaves legíveis por outros.
set -euo pipefail
install -d -m 700 /root/.ssh
if [[ -f /chaves/id_ed25519 ]]; then
  install -m 600 /chaves/id_ed25519 /root/.ssh/id_ed25519
fi
if [[ -f /chaves/known_hosts ]]; then
  install -m 600 /chaves/known_hosts /root/.ssh/known_hosts
fi
exec "$@"
