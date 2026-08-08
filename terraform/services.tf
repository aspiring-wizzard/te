# API enablement, managed rather than scripted.
#
# Previously done by scripts/setup-lab.sh. It belongs here: enabling an API is
# a declarative statement about the project, which is exactly what Terraform is
# for. What stays in the script is the part Terraform structurally cannot own —
# authentication, ADC, and capability discovery, which are preconditions for
# Terraform running at all rather than resources it manages.
#
# disable_on_destroy = false: a sandbox project may have arrived with some of
# these already on, and tearing down this build should not switch off APIs that
# were not ours to begin with.

locals {
  required_services = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "storage.googleapis.com",
    "artifactregistry.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "secretmanager.googleapis.com",
  ]
}

resource "google_project_service" "required" {
  for_each = toset(local.required_services)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
