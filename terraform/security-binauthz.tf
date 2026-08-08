# Binary Authorization — the project singleton policy the GKE cluster enforces.
#
# This is a NATIVE CLOUD preventative control: admission is decided by the GKE
# control plane, not by anything we installed into the cluster. It is the
# vendor-native counterpart to the Gatekeeper constraint in k8s/, and it is
# deliberately here to answer the "preventative *cloud* control" requirement
# without the "is Gatekeeper really a CSP control?" argument.
#
# THE SHAPE, and why it is safe to run against the live environment:
#   • default rule DENIES every image, and we allow exactly the app image.
#   • global_policy_evaluation_mode = ENABLE keeps Google-managed GKE system
#     images (kube-system, gke-managed-*, etc.) exempt automatically — so the
#     platform keeps running; only USER workloads in the default namespace are
#     evaluated, where we control the images.
#   • enforcement is BLOCK *and* AUDIT_LOG: a disallowed image is rejected at
#     admission AND the rejection lands in Cloud Audit Logs. Prevent and record,
#     in one control — which is exactly the pairing the exercise asks to see.
#
# The existing weaknesses survive (the requirement): this blocks a NEW bad
# action — a pod whose image is not on the allowlist — rather than retro-fixing
# anything already deployed. Demo it by watching the control plane reject an
# unauthorised image live (k8s/99-unauthorized-image-DENYME.yaml).

resource "google_binary_authorization_policy" "policy" {
  project = var.project_id

  # Google-managed GKE system images stay allowed, so the cluster keeps working.
  global_policy_evaluation_mode = "ENABLE"

  # The one image we vouch for: the application, from our Artifact Registry repo.
  # Trailing '*' matches any tag or digest of that image.
  admission_whitelist_patterns {
    name_pattern = "${var.region}-docker.pkg.dev/${var.project_id}/app/nodegoat*"
  }

  # Everything not explicitly allowed above is denied — and the denial is
  # enforced (the pod does not start) and logged.
  default_admission_rule {
    evaluation_mode  = "ALWAYS_DENY"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"
  }

  depends_on = [google_project_service.required]
}
