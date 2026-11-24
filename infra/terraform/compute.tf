# ===========================================================================
# Instâncias EC2 (LocalStack)
# ===========================================================================
# Observação sobre o LocalStack: ele aplica o Security Group na interface da
# instância, mas não o devolve em vpc_security_group_ids na leitura. Sem o
# ignore_changes, todo plano mostraria uma alteração falsa. (Interfaces de rede
# separadas evitariam isso, mas o LocalStack não as libera ao terminar a
# instância e o destroy falha.) A associação real é conferida em
# scripts/verificar-isolamento.sh.
resource "aws_instance" "app" {
  ami                    = var.ami_id
  instance_type          = var.app_instance_type
  subnet_id              = aws_subnet.publica.id
  private_ip             = var.app_private_ip
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name

  metadata_options {
    http_tokens = "required" # IMDSv2
  }

  tags = { Name = "todo-app", Funcao = "aplicacao" }

  lifecycle {
    ignore_changes = [vpc_security_group_ids]
  }
}

resource "aws_eip" "app" {
  domain = "vpc"
  tags   = { Name = "todo-app-ip" }
}

# Associação separada: recriar a instância não troca o IP público
resource "aws_eip_association" "app" {
  allocation_id = aws_eip.app.id
  instance_id   = aws_instance.app.id
}

# Sem IP público, na sub-rede privada
resource "aws_instance" "db" {
  ami                    = var.ami_id
  instance_type          = var.db_instance_type
  subnet_id              = aws_subnet.privada.id
  private_ip             = var.db_private_ip
  vpc_security_group_ids = [aws_security_group.db.id]
  iam_instance_profile   = aws_iam_instance_profile.db.name

  metadata_options {
    http_tokens = "required"
  }

  tags = { Name = "todo-db", Funcao = "banco" }

  lifecycle {
    ignore_changes = [vpc_security_group_ids]
  }
}

# ===========================================================================
# "VMs" locais: uma para cada instância acima, com o mesmo IP privado.
# ===========================================================================
resource "docker_image" "vm" {
  name = "todo-vm:local"
  build {
    context = "${path.module}/../vm-image"
  }
  triggers = {
    hash = sha1(join("", [for f in fileset("${path.module}/../vm-image", "*") : filesha1("${path.module}/../vm-image/${f}")]))
  }
  keep_locally = true
}

# Disco de sistema de cada VM (imagens e contêineres do Docker interno)
resource "docker_volume" "disco_app" {
  name = "todo-vm-app-disco"
}

resource "docker_volume" "disco_db" {
  name = "todo-vm-db-disco"
}

locals {
  # Variáveis comuns: equivalem aos metadados da instância + credenciais do
  # perfil IAM (no LocalStack as credenciais são fictícias).
  vm_env_comum = [
    "AWS_ENDPOINT_URL=http://localstack:4566",
    "AWS_REGION=${var.aws_region}",
    "AWS_DEFAULT_REGION=${var.aws_region}",
    "AWS_ACCESS_KEY_ID=test",
    "AWS_SECRET_ACCESS_KEY=test",
    "TODO_REGISTRY=${var.registry}",
    "TZ=America/Sao_Paulo",
  ]
}

resource "docker_container" "vm_db" {
  name       = "todo-vm-db"
  hostname   = "todo-db"
  image      = docker_image.vm.image_id
  privileged = true # necessário para o Docker da VM (Docker-in-Docker)
  restart    = "unless-stopped"

  # Sem portas publicadas: inacessível de fora da "VPC"
  networks_advanced {
    name         = docker_network.vpc.name
    ipv4_address = aws_instance.db.private_ip
  }
  networks_advanced {
    name = data.docker_network.servicos.name
  }

  env = concat(local.vm_env_comum, [
    "TODO_ROLE=db",
    "TODO_INSTANCE_ID=${aws_instance.db.id}",
    "TODO_PRIVATE_IP=${aws_instance.db.private_ip}",
    # Regra do Security Group (todo-db-sg): 27017 somente da VM da aplicação
    "TODO_MONGO_ALLOWED_FROM=${aws_instance.app.private_ip}",
    "TODO_SECRET_ROOT=${data.aws_secretsmanager_secret.mongo_root.name}",
    "TODO_SECRET_APP=${data.aws_secretsmanager_secret.mongo_app.name}",
    "TODO_BACKUP_BUCKET=${aws_s3_bucket.backups.bucket}",
  ])

  volumes {
    volume_name    = docker_volume.mongo_data.name
    container_path = "/mnt/mongo-data"
  }
  volumes {
    volume_name    = docker_volume.disco_db.name
    container_path = "/var/lib/docker"
  }

  labels {
    label = "todo.instance_id"
    value = aws_instance.db.id
  }

  depends_on = [aws_volume_attachment.mongo_data]
}

resource "docker_container" "vm_app" {
  name       = "todo-vm-app"
  hostname   = "todo-app"
  image      = docker_image.vm.image_id
  privileged = true
  restart    = "unless-stopped"

  networks_advanced {
    name         = docker_network.vpc.name
    ipv4_address = aws_instance.app.private_ip
  }
  networks_advanced {
    name = data.docker_network.servicos.name
  }

  # Equivale ao Elastic IP + regras 80/443 do todo-app-sg
  ports {
    internal = 80
    external = var.http_port
    ip       = var.publish_ip
  }
  ports {
    internal = 443
    external = var.https_port
    ip       = var.publish_ip
  }

  env = concat(local.vm_env_comum, [
    "TODO_ROLE=app",
    "TODO_INSTANCE_ID=${aws_instance.app.id}",
    "TODO_PRIVATE_IP=${aws_instance.app.private_ip}",
    "TODO_PUBLIC_IP=${aws_eip.app.public_ip}",
    "TODO_DB_HOST=${aws_instance.db.private_ip}",
    "TODO_SITE_ADDRESS=${var.site_address}",
    "TODO_SECRET_APP=${data.aws_secretsmanager_secret.mongo_app.name}",
  ])

  volumes {
    volume_name    = docker_volume.disco_app.name
    container_path = "/var/lib/docker"
  }

  labels {
    label = "todo.instance_id"
    value = aws_instance.app.id
  }
}
