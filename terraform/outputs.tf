output "mongo_public_ip" {
  description = "MongoDB VM public IP (SSH is open to the world by design)."
  value       = google_compute_instance.mongo.network_interface[0].access_config[0].nat_ip
}

output "mongo_internal_ip" {
  description = "MongoDB VM internal IP — used in the app's MONGODB_URI."
  value       = google_compute_instance.mongo.network_interface[0].network_ip
}

output "mongo_service_account" {
  description = "Over-permissive service account attached to the Mongo VM."
  value       = google_service_account.mongo.email
}

output "backup_bucket" {
  description = "Public backup bucket (read + list by allUsers)."
  value       = google_storage_bucket.backups.name
}

output "backup_bucket_public_url" {
  description = "Anonymous listing URL — paste into a browser during the demo."
  value       = "https://storage.googleapis.com/storage/v1/b/${google_storage_bucket.backups.name}/o"
}

output "gke_cluster" {
  description = "GKE cluster name."
  value       = google_container_cluster.gke.name
}

output "kubectl_credentials_command" {
  description = "Run this to point kubectl at the cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.gke.name} --zone ${var.zone} --project ${var.project_id}"
}

output "mongo_uri_secret" {
  description = "Secret Manager secret holding the Mongo connection string. Create the Kubernetes Secret from it without the value ever touching your shell."
  value       = google_secret_manager_secret.mongo_uri.secret_id
}

output "create_k8s_secret_command" {
  description = "Creates the mongo-credentials Secret straight from Secret Manager."
  value       = <<-EOT
    kubectl create secret generic mongo-credentials \
      --from-literal=uri="$(gcloud secrets versions access latest --secret=${google_secret_manager_secret.mongo_uri.secret_id})"
  EOT
}
