variable "project_id" {
  description = "Projeto do Google Cloud exclusivo do ToDo App"
  type        = string
}

# A cota grátis de e2-micro, disco e Cloud Storage só vale nestas três regiões
variable "region" {
  type    = string
  default = "us-east1"

  validation {
    condition     = contains(["us-east1", "us-central1", "us-west1"], var.region)
    error_message = "Use us-east1, us-central1 ou us-west1: só nelas existe a cota grátis."
  }
}

variable "zone" {
  type    = string
  default = "us-east1-b"
}

variable "ssh_public_key" {
  description = "Chave pública de administração (gerada por pipeline-gcp.sh em .local/gcp)"
  type        = string
}

# --- Rede -------------------------------------------------------------------
variable "public_subnet_cidr" {
  type    = string
  default = "10.10.1.0/24"
}

variable "private_subnet_cidr" {
  type    = string
  default = "10.10.2.0/24"
}

variable "app_private_ip" {
  type    = string
  default = "10.10.1.10"
}

variable "db_private_ip" {
  type    = string
  default = "10.10.2.10"
}

variable "saida_internet_banco" {
  description = "Cloud NAT para a VM do banco. Necessário só para instalar/atualizar pacotes; desligado, economiza e isola mais (as APIs do Google continuam acessíveis)"
  type        = bool
  default     = true
}

# --- VMs ----------------------------------------------------------------------
# Discos pd-standard: 10 + 10 + 10 = 30 GB, exatamente a cota grátis
variable "boot_disk_gb" {
  type    = number
  default = 10
}

variable "db_volume_size_gb" {
  type    = number
  default = 10
}

# --- Publicação e dados ---------------------------------------------------------
variable "site_address" {
  description = "Nome público (vazio = <ip-com-hifens>.sslip.io)"
  type        = string
  default     = ""
}

variable "backup_retention_days" {
  type    = number
  default = 30
}

# environment e instance_name viram etiquetas das VMs: mudar o valor altera as
# VMs no lugar, sem recriá-las. Os nomes das VMs (todo-app e todo-db) são fixos,
# porque trocar o nome de uma VM na GCP obriga a recriá-la (e apagaria a da feira).
variable "environment" {
  description = "Ambiente de destino (dev, homolog, prod), gravado na etiqueta environment das VMs"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "homolog", "prod"], var.environment)
    error_message = "Use dev, homolog ou prod."
  }
}

# Mesmo padrão da pipeline (.github/workflows/gcp.yml): rodar pela máquina da
# equipe ou pelo GitHub dá o mesmo plano.
variable "instance_name" {
  description = "Identificador das VMs, gravado na etiqueta instance_name"
  type        = string
  default     = "todo-pm04"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.instance_name))
    error_message = "Use minúsculas, números e hífen, começando por letra (até 63 caracteres)."
  }
}

# Cota grátis: as horas de e2-micro somadas até o total de horas do mês (~720 h).
# Duas VMs juntas cabem por ~15 dias por mês; desative ao terminar a feira.
# Outros tipos (ex.: e2-small) são cobrados.
variable "instance_type" {
  description = "Tipo de máquina das duas VMs na GCP"
  type        = string
  default     = "e2-micro"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*-[a-z0-9-]+$", var.instance_type))
    error_message = "Tipo de máquina inválido (ex.: e2-micro, e2-small)."
  }
}

