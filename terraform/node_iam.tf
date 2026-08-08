# IAM for the GKE node pool's service account.
#
# The node pool runs as the project's DEFAULT compute service account, which in
# this project holds NO roles at all — so the nodes could not pull the
# application image and every pod sat in ImagePullBackOff with a 403.
#
# That is current GCP behaviour, not a misconfiguration: since 2024 new projects
# no longer automatically grant roles/editor to the default compute service
# account. Historically that grant existed and made this "just work" — while
# also handing every VM in the project broad write access, which is exactly the
# over-privileged-default finding a CSPM flags.
#
# So this grants the documented MINIMUM instead of restoring a broad role:
# pull images, ship logs and metrics. Nothing else.
#
# What I would do properly, with more time (see docs/decisions.md): give the node
# pool a DEDICATED service account rather than sharing the project default with
# every other VM. That needs the node pool recreating, so it is named as a
# trade-off rather than done here.

locals {
  gke_node_sa = "serviceAccount:${data.google_project.this.number}-compute@developer.gserviceaccount.com"

  gke_node_roles = [
    "roles/artifactregistry.reader",             # pull the application image
    "roles/logging.logWriter",                   # ship container logs
    "roles/monitoring.metricWriter",             # ship metrics
    "roles/monitoring.viewer",                   # read back its own metrics
    "roles/stackdriver.resourceMetadata.writer", # resource metadata for monitoring
  ]
}

data "google_project" "this" {
  project_id = var.project_id
}

resource "google_project_iam_member" "gke_nodes" {
  for_each = toset(local.gke_node_roles)

  project = var.project_id
  role    = each.value
  member  = local.gke_node_sa
}
