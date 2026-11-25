# =============================================================================
# Acesso do GitHub Actions ao projeto, SEM chave: o GitHub prova quem é por OIDC
# e recebe um token temporário (Workload Identity Federation).
#
# Configuração separada de propósito: quem aplica é o dono do projeto, na própria
# máquina. O pipeline não consegue alterar as próprias permissões.
# =============================================================================
terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.12"
    }
  }
  backend "gcs" {
    prefix = "todo-ci"
  }
}

variable "project_id" {
  type = string
}

variable "github_repository" {
  description = "dono/repositorio autorizado"
  type        = string
  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", var.github_repository))
    error_message = "Use o formato dono/repositorio."
  }
}

variable "region" {
  type    = string
  default = "us-east1"
}

provider "google" {
  project = var.project_id
}

resource "google_project_service" "sts" {
  for_each           = toset(["sts.googleapis.com", "iamcredentials.googleapis.com"])
  service            = each.key
  disable_on_destroy = false
}

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"
}

# Só este repositório, só no branch main e só em execução manual
resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }
  attribute_condition = "assertion.repository == '${var.github_repository}' && assertion.ref == 'refs/heads/main' && assertion.event_name == 'workflow_dispatch'"
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "ci" {
  account_id   = "todo-ci"
  display_name = "GitHub Actions (ToDo App)"
}

resource "google_service_account_iam_member" "github" {
  service_account_id = google_service_account.ci.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

# Publicar imagens, entrar nas VMs pelo IAP, e ler a infraestrutura e o estado.
# Não cria nem apaga recursos: "provisionar" e "desativar" ficam com o dono.
resource "google_project_iam_member" "ci" {
  for_each = toset([
    "roles/browser",
    "roles/compute.viewer",
    "roles/iam.securityReviewer",
    "roles/artifactregistry.writer",
    "roles/iap.tunnelResourceAccessor",
    "roles/secretmanager.viewer",
    "roles/secretmanager.secretAccessor",
    "roles/storage.bucketViewer", # só metadados dos buckets, para o plan
  ])
  project = var.project_id
  role    = each.key
  member  = google_service_account.ci.member
}

# Estado do Terraform: leitura e trava (o plan e o refresh gravam no objeto)
resource "google_storage_bucket_iam_member" "estado" {
  bucket = "${var.project_id}-todo-tfstate"
  role   = "roles/storage.objectAdmin"
  member = google_service_account.ci.member
}

output "workload_identity_provider" {
  value = google_iam_workload_identity_pool_provider.github.name
}

output "service_account" {
  value = google_service_account.ci.email
}
