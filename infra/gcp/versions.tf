terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.12"
    }
  }

  # Estado em bucket privado e versionado, criado por "pipeline-gcp.sh bootstrap".
  # O nome chega por -backend-config. As senhas não passam pelo Terraform.
  backend "gcs" {
    prefix = "todo-app"
  }
}

# Credencial: token temporário do gcloud (GOOGLE_OAUTH_ACCESS_TOKEN), passado
# pelo pipeline. Nenhuma chave em arquivo.
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  default_labels = {
    projeto  = "todo-app"
    gerencia = "terraform"
  }
}
