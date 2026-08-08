# Cloud-native security controls (exercise: "Cloud Native Security" section).
#
# Design note — the weakness/control tension:
#   The intentional weaknesses must SURVIVE for the demo. So:
#     • DETECTIVE controls flag the EXISTING weaknesses (the log-based alert below,
#       plus Cloud Audit Logs).
#     • PREVENTATIVE controls block a NEW bad action (a fresh public bucket / privileged pod),
#       demonstrated live by watching them REJECT something, not by retro-fixing the environment.

# ---------------------------------------------------------------------------
# ✅ REQUIRED — control-plane audit logging (Admin Activity is on by default;
# this adds Data Access logs, which is what makes bucket reads visible).
# ---------------------------------------------------------------------------
resource "google_project_iam_audit_config" "all_services" {
  project = var.project_id
  service = "allServices"

  audit_log_config { log_type = "ADMIN_READ" }
  audit_log_config { log_type = "DATA_READ" }
  audit_log_config { log_type = "DATA_WRITE" }
}

# ---------------------------------------------------------------------------
# ✅ DETECTIVE — log-based metric + alert on public access to the backup bucket.
# This IS the detective control here, not a fallback: the sandbox is project-scoped
# and `securitycenter.findings.list` is denied at the organisation, so Security
# Command Center cannot be used. Project-scoped logging and alerting can.
# ---------------------------------------------------------------------------
resource "google_logging_metric" "public_bucket_access" {
  name   = "${var.prefix}-public-bucket-access"
  filter = <<-EOT
    resource.type="gcs_bucket"
    resource.labels.bucket_name="${google_storage_bucket.backups.name}"
    protoPayload.authenticationInfo.principalEmail=""
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_monitoring_alert_policy" "public_bucket_access" {
  display_name = "${var.prefix} — anonymous access to backup bucket"
  combiner     = "OR"

  conditions {
    display_name = "Anonymous read on backup bucket"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.public_bucket_access.name}\" AND resource.type=\"gcs_bucket\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  documentation {
    content = "Anonymous (unauthenticated) access to the MongoDB backup bucket. Expected during the exercise demo; in production this is data exfiltration."
  }
}

# ---------------------------------------------------------------------------
# 🛡️ PREVENTATIVE (optional) — org policy denying public access prevention bypass.
# ⚠️ Requires org-level permissions; CloudLabs sandboxes are often project-scoped.
#    Default OFF. If it applies cleanly, demo it REJECTING a NEW public bucket.
#    If not, use the Gatekeeper/Policy Controller constraint in k8s/ (blocks new
#    privileged / cluster-admin pods) — arguably the better K8s-security demo anyway.
# ---------------------------------------------------------------------------
resource "google_project_organization_policy" "public_access_prevention" {
  count = var.enable_org_policy ? 1 : 0

  project    = var.project_id
  constraint = "constraints/storage.publicAccessPrevention"

  boolean_policy {
    enforced = true
  }
}
