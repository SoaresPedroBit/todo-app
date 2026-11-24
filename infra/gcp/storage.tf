# Disco de dados do MongoDB, separado do disco de sistema
resource "google_compute_disk" "mongo_data" {
  name = "todo-mongo-data"
  type = "pd-standard"
  size = var.db_volume_size_gb
}

resource "google_compute_attached_disk" "mongo_data" {
  disk        = google_compute_disk.mongo_data.id
  instance    = google_compute_instance.vm["db"].id
  device_name = "mongo-data"
}

resource "google_storage_bucket" "backups" {
  name                        = "${var.project_id}-todo-backups"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true # o pipeline de desativação exporta os dados antes

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age            = var.backup_retention_days
      matches_prefix = ["mongo/"]
    }
  }
}

# Imagens da aplicação, em versões identificáveis. Mantém as 5 mais recentes de
# cada uma, para caber na cota grátis de 0,5 GB.
resource "google_artifact_registry_repository" "todo" {
  repository_id = "todo"
  location      = var.region
  format        = "DOCKER"

  cleanup_policies {
    id     = "manter-recentes"
    action = "KEEP"
    most_recent_versions {
      keep_count = 5
    }
  }
  cleanup_policies {
    id     = "apagar-antigas"
    action = "DELETE"
    condition {
      older_than = "604800s"
    }
  }
}
