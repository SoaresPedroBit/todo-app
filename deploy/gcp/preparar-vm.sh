#!/usr/bin/env bash
# Prepara uma VM Ubuntu 24.04 da GCP. Executado pelo pipeline por SSH, como
# root, e idempotente: rodar de novo não altera o que já está pronto.
#
#   preparar-vm.sh app|db
set -euo pipefail

papel=${1:?informe app ou db}
DISCO=/dev/disk/by-id/google-mongo-data
PONTO=/mnt/mongo-data

export DEBIAN_FRONTEND=noninteractive

# No primeiro boot o cloud-init ainda pode estar usando o apt
cloud-init status --wait >/dev/null 2>&1 || true

# A e2-micro tem 1 GB de memória: swap evita que o sistema mate o MongoDB
if ! swapon --show=NAME --noheadings | grep -qx /swapfile; then
  echo "Criando swap de 1 GB"
  [[ -f /swapfile ]] || fallocate -l 1G /swapfile
  chmod 600 /swapfile
  mkswap -q /swapfile 2>/dev/null || true
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >>/etc/fstab
fi

if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
  echo "Instalando Docker e utilitários"
  apt-get -o DPkg::Lock::Timeout=300 update -qq
  apt-get -o DPkg::Lock::Timeout=300 install -y -qq \
    docker.io docker-compose-v2 jq cron curl netcat-openbsd iptables >/dev/null
fi
systemctl enable --now docker cron >/dev/null 2>&1

install -d -m 755 /opt/todo

if [[ $papel == db ]]; then
  for _ in $(seq 1 60); do [[ -b $DISCO ]] && break; sleep 5; done
  [[ -b $DISCO ]] || { echo "disco de dados não encontrado em $DISCO" >&2; exit 1; }

  # Formata SOMENTE um disco sem sistema de arquivos. "blkid -p" devolve 2 quando
  # não encontra nada; qualquer outro erro interrompe, para nunca apagar dados.
  rc=0
  blkid -p "$DISCO" >/dev/null 2>&1 || rc=$?
  case $rc in
    0) echo "Disco de dados já formatado" ;;
    2) echo "Formatando disco novo"; mkfs.ext4 -q -L todo-mongo "$DISCO" ;;
    *) echo "não foi possível examinar $DISCO (blkid: $rc)" >&2; exit 1 ;;
  esac
  install -d "$PONTO"
  uuid=$(blkid -s UUID -o value "$DISCO")
  grep -q "$uuid" /etc/fstab || echo "UUID=$uuid $PONTO ext4 defaults,nofail 0 2" >>/etc/fstab
  systemctl daemon-reload
  mountpoint -q "$PONTO" || mount "$PONTO"

  # Sem o disco montado o Docker não deve subir (evita um banco vazio no disco errado)
  install -d /etc/systemd/system/docker.service.d
  printf '[Unit]\nRequiresMountsFor=%s\n' "$PONTO" >/etc/systemd/system/docker.service.d/disco.conf

  # Depois de reiniciar a VM, religa o banco e reaplica o firewall do Docker
  cat >/etc/systemd/system/todo-boot.service <<'EOF'
[Unit]
Description=ToDo App: religa os servicos apos o boot
Wants=network-online.target
After=docker.service network-online.target
Requires=docker.service
ConditionPathExists=/opt/todo/.env

[Service]
Type=oneshot
ExecStart=/opt/todo/ops.sh boot

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable todo-boot.service >/dev/null 2>&1
fi

echo "VM $papel pronta: $(docker --version)"
