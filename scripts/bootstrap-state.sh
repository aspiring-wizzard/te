#!/usr/bin/env bash
# Creates the ONE thing Terraform cannot create for itself: the bucket that
# holds its state. A bucket cannot be stored in the state it holds.
#
# Everything else that was once here is now Terraform-managed:
#   • APIs        -> terraform/services.tf   (google_project_service)
#   • Mongo creds -> terraform/secrets.tf    (random_password + Secret Manager)
#
# Run once per sandbox. Idempotent.
#
#   ./scripts/bootstrap-state.sh           # uses GCP_PROJECT/GCP_REGION from direnv
#   ./scripts/bootstrap-state.sh <PROJECT_ID> [REGION]
set -euo pipefail

PROJECT="${1:-${GCP_PROJECT:?set GCP_PROJECT (direnv) or pass it: bootstrap-state.sh <PROJECT_ID>}}"
REGION="${2:-${GCP_REGION:-europe-west1}}"
STATE_BUCKET="tfstate-${PROJECT}"

gcloud config set project "${PROJECT}" >/dev/null
gcloud services enable storage.googleapis.com >/dev/null 2>&1 || true

# Versioned so a clobbered state can be recovered; uniform IAM; public access
# ENFORCED. Note the deliberate contrast with the exercise's intentionally public
# backup bucket — state is the one thing that must never leak, because it holds
# resolved secret values in plaintext.
if gcloud storage buckets describe "gs://${STATE_BUCKET}" >/dev/null 2>&1; then
  echo "state bucket already exists: gs://${STATE_BUCKET}"
else
  gcloud storage buckets create "gs://${STATE_BUCKET}" \
    --location="${REGION}" \
    --uniform-bucket-level-access \
    --public-access-prevention
  gcloud storage buckets update "gs://${STATE_BUCKET}" --versioning
  echo "created state bucket: gs://${STATE_BUCKET}"
fi

cat <<EOF

────────────────────────────────────────────────────────────────────
State bucket ready.

Next:
  cd terraform
  tofu init -backend-config=backend.hcl
  tofu apply            # creates APIs, secrets and the environment

────────────────────────────────────────────────────────────────────
EOF
