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
# Cota grátis: as horas de e2-micro somadas até o total de horas do mês (~720 h).
# Duas VMs juntas cabem por ~15 dias por mês; desative ao terminar a feira.
variable "app_machine_type" {
  type    = string
  default = "e2-micro"
}

variable "db_machine_type" {
  type    = string
  default = "e2-micro"
}

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
