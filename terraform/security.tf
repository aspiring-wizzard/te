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
# ✅ DETECTIVE — log-based metric + alert on a bucket being MADE PUBLIC.
#
# This IS the detective control, and the signal it watches is deliberate.
#
# The obvious thing to alert on is the anonymous READ — someone downloading the
# backup. You cannot, natively: Cloud Audit Logs do NOT record allUsers /
# allAuthenticatedUsers access. Verified empirically — an anonymous object GET
# returns 200 and produces zero data-access log entries. Anonymous reads only
# appear in the legacy hourly-batched bucket usage logs, which are neither
# real-time nor demoable. That blind spot is itself a sharp cloud-security point.
#
# So detect the CAUSE, not the symptom: the IAM change that grants allUsers.
# `storage.setIamPermissions` is an Admin Activity event, which is always on and
# cannot be disabled — so this fires the moment ANY bucket in the project is made
# public, in real time, before a single byte is exfiltrated. Catching the door
# being unlocked beats hoping to see someone walk through it.
#
# (Security Command Center is the org-native tool for this; it is denied in this
# project-scoped sandbox — securitycenter.findings.list returns PERMISSION_DENIED
# — so this project-scoped log-based control is the in-scope equivalent.)
# ---------------------------------------------------------------------------
resource "google_logging_metric" "bucket_made_public" {
  name   = "${var.prefix}-bucket-made-public"
  filter = <<-EOT
    logName="projects/${var.project_id}/logs/cloudaudit.googleapis.com%2Factivity"
    resource.type="gcs_bucket"
    protoPayload.methodName="storage.setIamPermissions"
    protoPayload.serviceData.policyDelta.bindingDeltas.action="ADD"
    (protoPayload.serviceData.policyDelta.bindingDeltas.member="allUsers" OR protoPayload.serviceData.policyDelta.bindingDeltas.member="allAuthenticatedUsers")
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_monitoring_alert_policy" "bucket_made_public" {
  display_name = "${var.prefix} — a Cloud Storage bucket was made public"
  combiner     = "OR"

  conditions {
    display_name = "allUsers/allAuthenticatedUsers granted on a bucket"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.bucket_made_public.name}\" AND resource.type=\"gcs_bucket\""
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
    content = "A Cloud Storage bucket was granted anonymous (allUsers/allAuthenticatedUsers) access. This is the misconfiguration that makes the backup exfiltration possible — expected once during the exercise (the backup bucket), a data-exposure incident in production. Native anonymous READS are not logged by Cloud Audit Logs, so this alerts on the IAM change that opens the door."
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
