#!/usr/bin/env bash
# "Boot" da VM: equivale ao user-data/startup script de uma EC2 real.
# Sobe o Docker Engine da VM, o agendador (cron) e, se a aplicação já tinha sido
# implantada, sobe os serviços de novo (reinício da VM).
set -euo pipefail

echo "[boot] VM ${TODO_ROLE:-?} (${TODO_INSTANCE_ID:-sem id}) IP privado ${TODO_PRIVATE_IP:-?}"

# Registro de imagens local sem TLS (equivalente ao ECR)
mkdir -p /etc/docker
cat >/etc/docker/daemon.json <<EOF
{
  "insecure-registries": ["${TODO_REGISTRY:-todo-registry:5000}"],
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF

# Disco de dados (EBS) da VM do banco: o diretório do MongoDB pertence ao uid 999
if [[ ${TODO_ROLE:-} == db ]]; then
  install -d -o 999 -g 999 -m 700 /mnt/mongo-data/db
  install -d -m 700 /mnt/mongo-data/backups
fi

# Agendador (backups automáticos são instalados aqui pelo ops.sh)
crond -b -L /var/log/cron.log

# Ao subir o Docker, religa a aplicação se ela já estava implantada
(
  for _ in $(seq 1 60); do docker info >/dev/null 2>&1 && break; sleep 1; done
  if [[ -x /opt/todo/ops.sh && -f /opt/todo/.env ]]; then
    /opt/todo/ops.sh boot || echo "[boot] falha ao religar serviços"
  fi
  echo "[boot] VM pronta"
) &

# dockerd em primeiro plano. Só no socket local (sem API TCP exposta na rede);
# o "dind" ajusta cgroups para Docker aninhado.
exec dind dockerd
