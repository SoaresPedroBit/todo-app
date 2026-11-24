locals {
  site = var.site_address != "" ? var.site_address : "${replace(google_compute_address.app.address, ".", "-")}.sslip.io"
  # Lido da GCP: lista vazia = nenhum IP público
  ips_publicos = { for k, v in google_compute_instance.vm : k =>
    try(v.network_interface[0].access_config[0].nat_ip, "nenhum")
  }
}

output "site_address" {
  value = local.site
}

output "app_url" {
  value = "https://${local.site}"
}

output "app_public_ip" {
  value = google_compute_address.app.address
}

output "db_public_ip" {
  description = "Deve ser \"nenhum\""
  value       = local.ips_publicos["db"]
}

output "app_private_ip" {
  value = var.app_private_ip
}

output "db_private_ip" {
  value = var.db_private_ip
}

output "app_instance_id" {
  value = google_compute_instance.vm["app"].instance_id
}

output "db_instance_id" {
  value = google_compute_instance.vm["db"].instance_id
}

output "zone" {
  value = var.zone
}

output "backup_bucket" {
  value = google_storage_bucket.backups.name
}

output "registry" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.todo.repository_id}"
}

output "inventario" {
  description = "Inventário dos recursos (ACE-02)"
  value = {
    projeto = var.project_id
    zona    = var.zone
    vpc     = google_compute_network.todo.name
    vms = { for k, v in google_compute_instance.vm : k => {
      nome       = v.name
      id         = v.instance_id
      tipo       = v.machine_type
      ip_privado = v.network_interface[0].network_ip
      ip_publico = local.ips_publicos[k]
    } }
    disco_dados = "${google_compute_disk.mongo_data.name} (${google_compute_disk.mongo_data.size} GB, ${google_compute_disk.mongo_data.type})"
    nat         = var.saida_internet_banco ? "ligado" : "desligado"
    backups     = "gs://${google_storage_bucket.backups.name}/mongo/ (retenção ${var.backup_retention_days} dias)"
  }
}
