# VPC: MongoDB VM lives in the public subnet, GKE nodes in the private subnet.

resource "google_compute_network" "vpc" {
  name                    = "${var.prefix}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "public" {
  name          = "${var.prefix}-public"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

resource "google_compute_subnetwork" "private" {
  name                     = "${var.prefix}-private"
  ip_cidr_range            = "10.0.2.0/24"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.4.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.8.0.0/20"
  }
}

# Private GKE nodes have no external IPs — NAT lets them pull images and reach the internet.
resource "google_compute_router" "router" {
  name    = "${var.prefix}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.prefix}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# 🔴 INTENTIONAL WEAKNESS #1 — SSH open to the entire internet.
# Attack-path role: a second, parallel entry point (the primary chain starts in the
# application). Caught by Checkov before apply; nothing watches its *use* at runtime —
# a gap worth naming rather than papering over.
resource "google_compute_firewall" "ssh_from_world" {
  name          = "${var.prefix}-allow-ssh-world"
  network       = google_compute_network.vpc.id
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["mongo"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# ✅ REQUIRED CONTROL — MongoDB reachable only from the GKE cluster (nodes + pods).
resource "google_compute_firewall" "mongo_from_gke" {
  name    = "${var.prefix}-allow-mongo-gke"
  network = google_compute_network.vpc.id
  source_ranges = [
    google_compute_subnetwork.private.ip_cidr_range, # nodes
    "10.4.0.0/16",                                   # pods
  ]
  target_tags = ["mongo"]

  allow {
    protocol = "tcp"
    ports    = ["27017"]
  }
}
