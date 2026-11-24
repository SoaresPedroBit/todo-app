# ===========================================================================
# Rede na "AWS" (LocalStack)
# ===========================================================================
resource "aws_vpc" "todo" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "todo-vpc" }
}

resource "aws_subnet" "publica" {
  vpc_id                  = aws_vpc.todo.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false # IP público só via Elastic IP, explicitamente
  tags                    = { Name = "todo-publica" }
}

resource "aws_subnet" "privada" {
  vpc_id            = aws_vpc.todo.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone
  tags              = { Name = "todo-privada" }
}

resource "aws_internet_gateway" "todo" {
  vpc_id = aws_vpc.todo.id
  tags   = { Name = "todo-igw" }
}

resource "aws_route_table" "publica" {
  vpc_id = aws_vpc.todo.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.todo.id
  }
  tags = { Name = "todo-rt-publica" }
}

resource "aws_route_table_association" "publica" {
  subnet_id      = aws_subnet.publica.id
  route_table_id = aws_route_table.publica.id
}

# Saída para a internet sem entrada: a VM do banco baixa pacotes e imagens,
# mas ninguém de fora inicia conexão com ela.
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "todo-nat-ip" }
}

resource "aws_nat_gateway" "todo" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.publica.id
  tags          = { Name = "todo-nat" }
  depends_on    = [aws_internet_gateway.todo]
}

resource "aws_route_table" "privada" {
  vpc_id = aws_vpc.todo.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.todo.id
  }
  tags = { Name = "todo-rt-privada" }
}

resource "aws_route_table_association" "privada" {
  subnet_id      = aws_subnet.privada.id
  route_table_id = aws_route_table.privada.id
}

# ===========================================================================
# Security Groups
# Nenhuma regra de SSH: a administração é feita pelo SSM Session Manager
# (no ambiente local, "docker exec" na VM cumpre esse papel).
# ===========================================================================
resource "aws_security_group" "app" {
  name        = "todo-app-sg"
  description = "VM da aplicacao: somente HTTP/HTTPS publicos"
  vpc_id      = aws_vpc.todo.id
  tags        = { Name = "todo-app-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "app_http" {
  security_group_id = aws_security_group.app.id
  description       = "HTTP (redireciona para HTTPS)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "app_https" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "app_saida" {
  security_group_id = aws_security_group.app.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "db" {
  name        = "todo-db-sg"
  description = "VM do banco: MongoDB apenas a partir da VM da aplicacao"
  vpc_id      = aws_vpc.todo.id
  tags        = { Name = "todo-db-sg" }
}

# A ÚNICA entrada do banco: porta 27017 vinda do Security Group da aplicação
resource "aws_vpc_security_group_ingress_rule" "db_mongo_from_app" {
  security_group_id            = aws_security_group.db.id
  ip_protocol                  = "tcp"
  from_port                    = 27017
  to_port                      = 27017
  referenced_security_group_id = aws_security_group.app.id

  # Compatibilidade com o LocalStack:
  # - ele devolve o ID no formato "conta/sg-..." (a AWS real devolve só
  #   "sg-..."), o que geraria uma alteração falsa a cada plano;
  # - ele descarta a "description" ao criar regras que referenciam outro SG,
  #   por isso esta regra não tem descrição (a finalidade está no comentário acima).
  lifecycle {
    ignore_changes = [referenced_security_group_id]
  }
}

resource "aws_vpc_security_group_egress_rule" "db_saida" {
  security_group_id = aws_security_group.db.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ===========================================================================
# Rede local que materializa a VPC para as VMs (mesma faixa e mesmos IPs)
# ===========================================================================
resource "docker_network" "vpc" {
  name   = "todo-vpc"
  driver = "bridge"
  ipam_config {
    subnet  = var.vpc_cidr
    gateway = cidrhost(var.vpc_cidr, 1)
  }
  labels {
    label = "todo.vpc_id"
    value = aws_vpc.todo.id
  }
}

# Rede dos serviços (LocalStack e registro), criada pelo bootstrap
data "docker_network" "servicos" {
  name = "todo-servicos"
}
