# Backup bucket for the daily MongoDB dump.

# 🔴 INTENTIONAL WEAKNESS #4 — bucket is publicly readable AND listable.
# Attack-path role: data exposure. Anyone on the internet can enumerate and download DB backups.
# roles/storage.objectViewer grants both objects.get and objects.list = public read + public listing.
# Caught by Checkov before apply; anonymous reads then fire the log-based alert
# in security.tf. (A CSPM would also flag PUBLIC_BUCKET_ACL — not available in
# this project-scoped sandbox.)
resource "google_storage_bucket" "backups" {
  name          = "${var.prefix}-backups-${var.project_id}"
  location      = var.region
  force_destroy = true # lab environment — keep teardown clean

  uniform_bucket_level_access = true
  public_access_prevention    = "inherited" # deliberately NOT "enforced"
}

resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.backups.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}
