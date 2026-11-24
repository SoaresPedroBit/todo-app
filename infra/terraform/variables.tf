variable "aws_endpoint" {
  description = "Endpoint do LocalStack visto de onde o Terraform roda"
  type        = string
  default     = "http://localstack:4566"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "availability_zone" {
  description = "Zona das instâncias e do volume EBS (precisam coincidir)"
  type        = string
  default     = "us-east-1a"
}

variable "docker_host" {
  description = "Docker Engine que executa as VMs"
  type        = string
  default     = "unix:///var/run/docker.sock"
}

variable "environment" {
  type    = string
  default = "feira-localstack"
}

# --- Rede -------------------------------------------------------------------
variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Sub-rede pública (VM da aplicação)"
  type        = string
  default     = "10.10.1.0/24"
}

variable "private_subnet_cidr" {
  description = "Sub-rede privada (VM do banco, sem IP público)"
  type        = string
  default     = "10.10.2.0/24"
}

variable "app_private_ip" {
  type    = string
  default = "10.10.1.10"
}

variable "db_private_ip" {
  type    = string
  default = "10.10.2.10"
}

# --- Instâncias -----------------------------------------------------------
variable "ami_id" {
  description = "AMI (no LocalStack, uma AMI simulada de Ubuntu 22.04)"
  type        = string
  default     = "ami-df5de72bdb3b"
}

variable "app_instance_type" {
  type    = string
  default = "t3.small"
}

variable "db_instance_type" {
  type    = string
  default = "t3.small"
}

variable "db_volume_size_gb" {
  description = "Tamanho do volume EBS de dados do MongoDB"
  type        = number
  default     = 10
}

# --- Publicação -----------------------------------------------------------
variable "site_address" {
  description = "Nome atendido pelo HTTPS (certificado da CA interna do Caddy)"
  type        = string
  default     = "localhost"
}

variable "publish_ip" {
  description = "IP da máquina onde as portas 80/443 da VM da aplicação são publicadas (0.0.0.0 = acessível na rede local)"
  type        = string
  default     = "0.0.0.0"
}

variable "http_port" {
  type    = number
  default = 80
}

variable "https_port" {
  type    = number
  default = 443
}

# --- Dados e segredos -----------------------------------------------------
variable "backup_bucket_name" {
  type    = string
  default = "todo-app-backups"
}

variable "backup_retention_days" {
  type    = number
  default = 30
}

variable "mongo_root_secret" {
  description = "Nome do segredo com a senha root do MongoDB (criado pelo bootstrap)"
  type        = string
  default     = "todo/mongo-root-password"
}

variable "mongo_app_secret" {
  description = "Nome do segredo com a senha do usuário todo_app (criado pelo bootstrap)"
  type        = string
  default     = "todo/mongo-app-password"
}

variable "registry" {
  description = "Registro de imagens visto pelas VMs (equivalente ao ECR)"
  type        = string
  default     = "todo-registry:5000"
}
