# MongoDB credential — generated, not supplied.
#
# The password is created by Terraform and stored in Secret Manager rather than
# being typed into tfvars. That removes it from the filesystem, from shell
# history, and from the operator's clipboard.
#
# Honest limitation, stated rather than hidden: random_password still resolves
# into Terraform state. State is therefore treated as a secret — versioned,
# IAM-restricted, public-access-enforced GCS. The only way to keep it out of
# state is for it never to pass through Terraform: generate it on the VM at
# first boot and write it straight to Secret Manager. That is the residual gap
# on the closing slide, and this is a deliberate step towards it rather than a
# claim to have solved it.

resource "random_password" "mongo" {
  length  = 28
  special = false # avoids escaping pain in the Mongo URI and the startup script
}

locals {
  # Explicit conditional rather than coalesce(): var.mongo_password defaults to
  # null, and this leaves no doubt about the null case.
  mongo_password = var.mongo_password != null ? var.mongo_password : random_password.mongo.result
}

resource "google_secret_manager_secret" "mongo" {
  secret_id = "${var.prefix}-mongo-password"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "mongo" {
  secret      = google_secret_manager_secret.mongo.id
  secret_data = local.mongo_password
}

# Convenience for the demo: the full connection string the Kubernetes Secret needs.
resource "google_secret_manager_secret" "mongo_uri" {
  secret_id = "${var.prefix}-mongo-uri"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "mongo_uri" {
  secret = google_secret_manager_secret.mongo_uri.id
  secret_data = format(
    "mongodb://%s:%s@%s:27017/%s?authSource=admin",
    var.mongo_user,
    local.mongo_password,
    google_compute_instance.mongo.network_interface[0].network_ip,
    var.mongo_db,
  )
}
