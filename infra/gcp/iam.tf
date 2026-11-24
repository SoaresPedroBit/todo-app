# Uma identidade por VM, com privilégio mínimo
resource "google_service_account" "vm" {
  for_each     = { app = "VM da aplicacao", db = "VM do banco" }
  account_id   = "todo-${each.key}-vm"
  display_name = each.value
}

# Segredos: aqui só o "recipiente". O valor é adicionado pelo pipeline, por fora
# do Terraform, para que as senhas não fiquem no estado.
resource "google_secret_manager_secret" "mongo" {
  for_each  = toset(["mongo-root-password", "mongo-app-password"])
  secret_id = "todo-${each.key}"
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

# A aplicação lê só a própria senha; o banco lê as duas
resource "google_secret_manager_secret_iam_member" "leitura" {
  for_each = {
    app_app = { vm = "app", segredo = "mongo-app-password" }
    db_app  = { vm = "db", segredo = "mongo-app-password" }
    db_root = { vm = "db", segredo = "mongo-root-password" }
  }
  secret_id = google_secret_manager_secret.mongo[each.value.segredo].id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.vm[each.value.vm].member
}

resource "google_artifact_registry_repository_iam_member" "leitura" {
  for_each   = google_service_account.vm
  repository = google_artifact_registry_repository.todo.name
  location   = var.region
  role       = "roles/artifactregistry.reader"
  member     = each.value.member
}

# Banco: cria e lê backups. Não sobrescreve nem apaga.
resource "google_storage_bucket_iam_member" "backups" {
  for_each = toset(["roles/storage.objectCreator", "roles/storage.objectViewer"])
  bucket   = google_storage_bucket.backups.name
  role     = each.key
  member   = google_service_account.vm["db"].member
}
