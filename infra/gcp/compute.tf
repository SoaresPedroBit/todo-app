data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2404-lts-amd64"
  project = "ubuntu-os-cloud"
}

# IP reservado: recriar a VM não troca o endereço da aplicação
resource "google_compute_address" "app" {
  name = "todo-app-ip"
}

locals {
  vms = {
    app = { tipo = var.app_machine_type, subnet = google_compute_subnetwork.publica.id, ip = var.app_private_ip }
    db  = { tipo = var.db_machine_type, subnet = google_compute_subnetwork.privada.id, ip = var.db_private_ip }
  }
}

resource "google_compute_instance" "vm" {
  for_each                  = local.vms
  name                      = "todo-${each.key}"
  machine_type              = var.instance_type
  allow_stopping_for_update = true

  labels = {
    environment   = var.environment
    instance_name = var.instance_name
  }

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
      size  = var.boot_disk_gb
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = each.value.subnet
    network_ip = each.value.ip

    # Só a aplicação tem IP público; a VM do banco não recebe este bloco
    dynamic "access_config" {
      for_each = each.key == "app" ? [1] : []
      content {
        nat_ip       = google_compute_address.app.address
        network_tier = "PREMIUM"
      }
    }
  }

  # Identidade da VM: as permissões vêm do IAM (iam.tf), sem chave em disco
  service_account {
    email  = google_service_account.vm[each.key].email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot = true
  }

  metadata = {
    enable-oslogin         = "FALSE"
    block-project-ssh-keys = "TRUE"
    ssh-keys               = "todo:${var.ssh_public_key}"
  }

  lifecycle {
    # Imagem nova do Ubuntu não recria a VM; o disco de dados é anexado em storage.tf
    ignore_changes = [boot_disk[0].initialize_params[0].image, attached_disk]
  }
}
