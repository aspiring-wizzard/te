# Artifact Registry for the application image.
#
# Managed here rather than created by hand: the pipeline pushes to it, the
# deployment pulls from it, and Binary Authorization (if enabled) allowlists it
# by path — three things that would all break silently if it were a manual step
# someone forgot to repeat.
#
# Vulnerability scanning is NOT configured here because it does not need to be:
# with containerscanning.googleapis.com enabled on the project, Artifact
# Analysis scans every image pushed to Artifact Registry automatically. That is
# a second, cloud-native opinion on the same image the pipeline already scanned
# with Trivy — same artefact, different vantage point.

resource "google_artifact_registry_repository" "app" {
  location      = var.region
  repository_id = "app"
  format        = "DOCKER"
  description   = "NodeGoat application images for the Wiz technical exercise"

  depends_on = [google_project_service.required]
}
