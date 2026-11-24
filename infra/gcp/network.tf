locals {
  # Origem fixa do Identity-Aware Proxy. Passar por ele exige login Google com
  # permissão no projeto; a porta 22 nunca fica aberta para a internet.
  iap_cidr = "35.235.240.0/20"
}

resource "google_compute_network" "todo" {
  name                    = "todo-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "publica" {
  name          = "todo-publica"
  network       = google_compute_network.todo.id
  ip_cidr_range = var.public_subnet_cidr
}

# Acesso privado às APIs do Google: segredos, imagens e backups sem internet
resource "google_compute_subnetwork" "privada" {
  name                     = "todo-privada"
  network                  = google_compute_network.todo.id
  ip_cidr_range            = var.private_subnet_cidr
  private_ip_google_access = true
}

# Saída sem entrada, só para a sub-rede do banco (pode ser desligada)
resource "google_compute_router" "todo" {
  count   = var.saida_internet_banco ? 1 : 0
  name    = "todo-router"
  network = google_compute_network.todo.id
}

resource "google_compute_router_nat" "todo" {
  count                              = var.saida_internet_banco ? 1 : 0
  name                               = "todo-nat"
  router                             = google_compute_router.todo[0].name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name                    = google_compute_subnetwork.privada.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

# --- Firewall: sem regra, a VPC recusa toda entrada ---------------------------
resource "google_compute_firewall" "web" {
  name                    = "todo-web"
  network                 = google_compute_network.todo.id
  description             = "HTTP e HTTPS publicos, so na VM da aplicacao"
  source_ranges           = ["0.0.0.0/0"]
  target_service_accounts = [google_service_account.vm["app"].email]
  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

resource "google_compute_firewall" "mongo" {
  name                    = "todo-mongo"
  network                 = google_compute_network.todo.id
  description             = "MongoDB somente a partir da VM da aplicacao"
  source_service_accounts = [google_service_account.vm["app"].email]
  target_service_accounts = [google_service_account.vm["db"].email]
  allow {
    protocol = "tcp"
    ports    = ["27017"]
  }
}

resource "google_compute_firewall" "ssh_iap" {
  name                    = "todo-ssh-iap"
  network                 = google_compute_network.todo.id
  description             = "SSH somente pelo Identity-Aware Proxy"
  source_ranges           = [local.iap_cidr]
  target_service_accounts = [for s in google_service_account.vm : s.email]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
