#!/usr/bin/env bash
# Evidência de isolamento do banco (ACE-03) no ambiente LocalStack.
#  1. A instância do banco não tem IP público.
#  2. O Security Group do banco só aceita 27017 vindo do SG da aplicação.
#  3. De fora (esta máquina = internet), a porta 27017 não responde.
#  4. De outro host DENTRO da VPC (que não é a aplicação), também não.
#  5. Da VM da aplicação, pela rede privada, responde, e a API está conectada.
set -uo pipefail
export MSYS_NO_PATHCONV=1

falhas=0
ok()    { echo "  [OK] $*"; }
falha() { echo "  [FALHA] $*"; falhas=$((falhas + 1)); }
awsl()  { docker exec todo-localstack awslocal "$@"; }

ip_db=$(docker exec todo-vm-db printenv TODO_PRIVATE_IP)
ip_app=$(docker exec todo-vm-app printenv TODO_PRIVATE_IP)
id_db=$(docker exec todo-vm-db printenv TODO_INSTANCE_ID)

echo "1. IP público da instância do banco ($id_db)"
pub=$(awsl ec2 describe-instances --instance-ids "$id_db" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
if [[ $pub == None || -z $pub ]]; then ok "sem IP público (privado: $ip_db)"; else falha "tem IP público $pub"; fi
portas=$(docker port todo-vm-db 2>/dev/null)
if [[ -z $portas ]]; then ok "VM do banco não publica nenhuma porta"; else falha "portas publicadas: $portas"; fi

echo "2. Security Group do banco"
sg_db=$(awsl ec2 describe-security-groups --filters Name=group-name,Values=todo-db-sg --query 'SecurityGroups[0].GroupId' --output text)
sg_app=$(awsl ec2 describe-security-groups --filters Name=group-name,Values=todo-app-sg --query 'SecurityGroups[0].GroupId' --output text)
awsl ec2 describe-security-group-rules --filters Name=group-id,Values="$sg_db" \
  --query 'SecurityGroupRules[?!IsEgress].[FromPort,ToPort,IpProtocol,CidrIpv4||`-`,ReferencedGroupInfo.GroupId||`-`]' --output table
entradas=$(awsl ec2 describe-security-group-rules --filters Name=group-id,Values="$sg_db" \
  --query 'SecurityGroupRules[?!IsEgress] | length(@)' --output text)
origem=$(awsl ec2 describe-security-group-rules --filters Name=group-id,Values="$sg_db" \
  --query 'SecurityGroupRules[?!IsEgress] | [0].ReferencedGroupInfo.GroupId' --output text)
if [[ $entradas == 1 && $origem == "$sg_app" ]]; then ok "única entrada: 27017 a partir de $sg_app (todo-app-sg)"; else falha "regras de entrada inesperadas"; fi

echo "3. Tentativa de fora (esta máquina) na porta 27017"
if timeout 5 bash -c 'exec 3<>/dev/tcp/127.0.0.1/27017' 2>/dev/null; then
  falha "27017 respondeu em localhost"
else
  ok "27017 inacessível a partir desta máquina"
fi

echo "4. Tentativa de outro host da VPC (10.10.1.99, não é a aplicação)"
if docker run --rm --network todo-vpc --ip 10.10.1.99 alpine:3.20 nc -z -w 4 "$ip_db" 27017 >/dev/null 2>&1; then
  falha "27017 respondeu para um host que não é a aplicação"
else
  ok "bloqueado pelo firewall da VM do banco (equivalente ao SG)"
fi

echo "5. Da VM da aplicação ($ip_app) pela rede privada"
if docker exec todo-vm-app nc -z -w 4 "$ip_db" 27017; then ok "$ip_app -> $ip_db:27017 conecta"; else falha "aplicação não alcança o banco"; fi
saude=$(docker exec todo-vm-app /opt/todo/ops.sh health 2>/dev/null)
if [[ $saude == *'"banco":"ok"'* ]]; then ok "API conectada ao banco: $saude"; else falha "/health: ${saude:-sem resposta}"; fi
escuta=$(docker exec todo-vm-db ss -ltnH 'sport = :27017' | awk '{print $4}' | tr '\n' ' ')
if [[ $escuta == "$ip_db:27017 " ]]; then ok "MongoDB escuta apenas em $escuta"; else falha "MongoDB escuta em: $escuta"; fi

echo
if (( falhas == 0 )); then echo "Isolamento verificado"; else echo "$falhas verificação(ões) falharam"; exit 1; fi
