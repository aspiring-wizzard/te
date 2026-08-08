# MongoDB on a GCE VM — deliberately outdated OS + DB, over-permissive identity,
# public IP with world-open SSH, daily backups to a public bucket.

# 🔴 INTENTIONAL WEAKNESS #2 — over-permissive service account.
# roles/editor lets this VM create VMs and read/write project resources.
# Attack-path role: privilege escalation from a compromised host into the cloud control plane.
# Caught by Checkov before apply; its use lands in Cloud Audit Logs afterwards.
resource "google_service_account" "mongo" {
  account_id   = "${var.prefix}-mongo-sa"
  display_name = "MongoDB VM (intentionally over-permissive)"
}

resource "google_project_iam_member" "mongo_editor" {
  project = var.project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.mongo.email}"
}

# A DECLARED internal address, rather than whatever DHCP hands out.
#
# The connection URI embeds this address, and it is consumed in two places that
# are updated on different schedules: the Secret Manager URI (rendered by
# Terraform, so always current) and the Kubernetes Secret (created out-of-band).
# With an ephemeral address, rebuilding the VM moves the database and leaves the
# cluster pointing at nothing — a failure that surfaces as a confusing app-level
# timeout rather than as "the thing you just rebuilt has a new address".
# Reserving it makes the address a property of the design, not of boot order.
resource "google_compute_address" "mongo_internal" {
  name         = "${var.prefix}-mongo-internal"
  subnetwork   = google_compute_subnetwork.public.id
  address_type = "INTERNAL"
  region       = var.region
  # Explicit host in the subnet, deliberately clear of the low addresses GCP
  # hands out automatically, so reserving it cannot collide with a live VM.
  address = cidrhost(google_compute_subnetwork.public.ip_cidr_range, 20)
}

resource "google_compute_instance" "mongo" {
  name         = "${var.prefix}-mongo"
  machine_type = "e2-medium"
  zone         = var.zone
  tags         = ["mongo"]

  boot_disk {
    initialize_params {
      # 🔴 INTENTIONAL WEAKNESS #3 — the original Ubuntu 20.04 release image
      # from April 2020: over six years old, unpatched, and past end of
      # standard support since April 2025. See var.mongo_image.
      image = var.mongo_image
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.public.id
    network_ip = google_compute_address.mongo_internal.address
    access_config {} # 🔴 public IP (paired with the world-open SSH rule)
  }

  service_account {
    email  = google_service_account.mongo.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = templatefile("${path.module}/scripts/mongo-startup.sh.tftpl", {
    mongo_user     = var.mongo_user
    mongo_password = local.mongo_password
    mongo_db       = var.mongo_db
    apt_suite      = var.mongo_apt_suite
    mongo_version  = var.mongo_version
    backup_bucket  = google_storage_bucket.backups.name
  })

  # Keep teardown friction-free at the end of the lab.
  allow_stopping_for_update = true
}
