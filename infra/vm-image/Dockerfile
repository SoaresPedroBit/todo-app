# Imagem das "VMs" do ambiente LocalStack.
# A EC2 do LocalStack Community é apenas simulada (não executa nada), então cada
# instância declarada no Terraform ganha uma "VM" real: um contêiner com seu
# próprio Docker Engine (Docker-in-Docker), disco e IP privado.
FROM docker:27.5-dind

# bash/coreutils/util-linux: scripts de operação | aws-cli: Secrets Manager e S3
# iproute2: diagnóstico de portas | iptables: regra equivalente ao Security Group
RUN apk add --no-cache bash coreutils util-linux iproute2 iptables curl jq aws-cli tzdata \
 && install -d -m 755 /opt/todo /mnt/mongo-data

COPY entrypoint.sh /usr/local/bin/vm-entrypoint.sh
RUN chmod 755 /usr/local/bin/vm-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/vm-entrypoint.sh"]
