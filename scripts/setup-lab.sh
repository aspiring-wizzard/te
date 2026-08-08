#!/usr/bin/env bash
# Preflight for the CloudLabs sandbox. Idempotent — safe to re-run at any point.
#
# Scope is deliberately narrow: this handles what Terraform structurally CANNOT —
# authentication, Application Default Credentials, and capability discovery, all
# of which are preconditions for Terraform running rather than resources it owns.
# API enablement and the Mongo password are Terraform-managed.
# The state bucket is the one honest exception: it cannot live in the state it stores.
#
#   ./scripts/setup-lab.sh                 # uses GCP_PROJECT/GCP_REGION from direnv
#   ./scripts/setup-lab.sh <PROJECT_ID> [REGION]   # or pass explicitly
#
# Does, in order:
#   1. verifies gcloud auth AND Application Default Credentials (Terraform uses ADC,
#      not your gcloud login — the most common silent failure)
#   2. verifies project + billing
#   3. notes API enablement (Terraform-managed)
#   4. PROBES CAPABILITIES via test-iam-permissions — org policy, SCC, and the
#      create permissions — which decides the detective/preventative path
#   5. detects your public IP for admin_cidr
#   6. writes terraform/terraform.tfvars if absent (gitignored)
#   7. runs bootstrap-state.sh (state bucket — the one genuine chicken-and-egg)
#   8. records everything in docs/lab-environment.md
#
# Prints no secret values.
set -euo pipefail

PROJECT="${1:-${GCP_PROJECT:?set GCP_PROJECT (direnv) or pass it: setup-lab.sh <PROJECT_ID>}}"
REGION="${2:-${GCP_REGION:-europe-west1}}"
ZONE="${GCP_ZONE:-${REGION}-b}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CAPTURE="${ROOT}/docs/lab-environment.md"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
step "1. Credentials"
ACCOUNT="$(gcloud config get-value account 2>/dev/null || true)"
[ -n "${ACCOUNT}" ] && ok "gcloud account: ${ACCOUNT}" || { bad "not logged in — run: gcloud auth login"; exit 1; }

ADC="${CLOUDSDK_CONFIG:-$HOME/.config/gcloud}/application_default_credentials.json"
if [ -f "${ADC}" ]; then
  ok "Application Default Credentials present"
  gcloud auth application-default set-quota-project "${PROJECT}" >/dev/null 2>&1 \
    && ok "ADC quota project set to ${PROJECT}" \
    || warn "could not set ADC quota project (usually harmless)"
else
  bad "no ADC — Terraform will fail. Run: gcloud auth application-default login"
  exit 1
fi

# ---------------------------------------------------------------------------
step "2. Project and billing"
gcloud config set project "${PROJECT}" >/dev/null 2>&1
PROJECT_NUM="$(gcloud projects describe "${PROJECT}" --format='value(projectNumber)' 2>/dev/null || true)"
[ -n "${PROJECT_NUM}" ] && ok "project ${PROJECT} (number ${PROJECT_NUM})" || { bad "cannot describe project ${PROJECT}"; exit 1; }

BILLING="$(gcloud beta billing projects describe "${PROJECT}" --format='value(billingEnabled)' 2>/dev/null || echo "unknown")"
[ "${BILLING}" = "True" ] && ok "billing enabled" || warn "billing status: ${BILLING}"

# ---------------------------------------------------------------------------
step "3. APIs"
ok "managed by Terraform (terraform/services.tf) — google_project_service"
warn "container.googleapis.com can take a few minutes to become usable after first enable"

# ---------------------------------------------------------------------------
step "4. Capability probe (decides the detective/preventative path)"
ORG_ID="$(gcloud organizations list --format='value(ID)' 2>/dev/null | head -1 || true)"
if [ -n "${ORG_ID}" ]; then
  ok "organisation visible: ${ORG_ID}"
else
  warn "no organisation visible — project-scoped only"
fi

have_perm() { # resource_type resource_id permission
  local out
  case "$1" in
    project) out="$(gcloud projects test-iam-permissions "$2" --permissions="$3" --format='value(permissions)' 2>/dev/null || true)" ;;
    org)     out="$(gcloud organizations test-iam-permissions "$2" --permissions="$3" --format='value(permissions)' 2>/dev/null || true)" ;;
  esac
  [ -n "${out}" ]
}

ORGPOLICY_WRITE=no
if have_perm project "${PROJECT}" orgpolicy.policy.set; then
  ORGPOLICY_WRITE=yes; ok "CAN set org policy at project scope → enable_org_policy = true is viable"
else
  warn "cannot set org policy → keep enable_org_policy = false, use Gatekeeper as the preventative control"
fi

SCC_READ=no
if [ -n "${ORG_ID}" ] && have_perm org "${ORG_ID}" securitycenter.findings.list; then
  SCC_READ=yes; ok "CAN list SCC findings → SCC is the detective control"
else
  warn "no SCC findings access → use the log-based metric + alert as the detective control"
fi

for p in compute.instances.create container.clusters.create storage.buckets.create; do
  have_perm project "${PROJECT}" "$p" && ok "have ${p}" || bad "MISSING ${p} — the build will fail"
done

# ---------------------------------------------------------------------------
step "4b. kubectl prerequisites"
if command -v kubectl >/dev/null 2>&1; then ok "kubectl present"; else bad "kubectl missing — brew install kubectl"; fi
if command -v gke-gcloud-auth-plugin >/dev/null 2>&1; then
  ok "gke-gcloud-auth-plugin on PATH"
else
  FOUND=""
  for d in /opt/homebrew/share/google-cloud-sdk/bin /usr/local/share/google-cloud-sdk/bin "$HOME/google-cloud-sdk/bin"; do
    [ -x "$d/gke-gcloud-auth-plugin" ] && FOUND="$d" && break
  done
  if [ -n "${FOUND}" ]; then
    warn "plugin installed at ${FOUND} but NOT on PATH — direnv adds it; otherwise: export PATH=\"${FOUND}:\$PATH\""
  else
    bad "gke-gcloud-auth-plugin missing — run: gcloud components install gke-gcloud-auth-plugin"
  fi
fi

# ---------------------------------------------------------------------------
step "5. Public IP (admin_cidr)"
MYIP="$(curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null || curl -fsS --max-time 8 https://ifconfig.me 2>/dev/null || true)"
if [ -n "${MYIP}" ]; then
  ok "public IP ${MYIP} → admin_cidr = ${MYIP}/32"
else
  warn "could not detect public IP — set admin_cidr by hand"
fi

# ---------------------------------------------------------------------------
step "6. terraform.tfvars"
TFVARS="${ROOT}/terraform/terraform.tfvars"
if [ -f "${TFVARS}" ]; then
  ok "terraform.tfvars already exists (left untouched)"
else
  cat > "${TFVARS}" <<EOF
project_id = "${PROJECT}"
region     = "${REGION}"
zone       = "${ZONE}"
admin_cidr = "${MYIP:-CHANGE_ME}/32"

# mongo_password is deliberately absent: Terraform generates it with
# random_password and stores it in Secret Manager, so it never exists here.

enable_org_policy = $( [ "${ORGPOLICY_WRITE}" = yes ] && echo true || echo false )
EOF
  chmod 600 "${TFVARS}"
  ok "wrote terraform/terraform.tfvars (gitignored; no secret in it)"
fi

# ---------------------------------------------------------------------------
step "7. State bucket (the one genuine bootstrap exception)"
"${ROOT}/scripts/bootstrap-state.sh" "${PROJECT}" "${REGION}" >/dev/null 2>&1 \
  && ok "state bucket ready" \
  || warn "bootstrap-state.sh reported problems — run it directly to see why"

BACKEND="${ROOT}/terraform/backend.hcl"
if [ ! -f "${BACKEND}" ]; then
  printf 'bucket = "tfstate-%s"\nprefix = "wizex"\n' "${PROJECT}" > "${BACKEND}"
  ok "wrote terraform/backend.hcl"
else
  ok "backend.hcl already exists"
fi

# ---------------------------------------------------------------------------
step "8. Capture"
cat > "${CAPTURE}" <<EOF
# Lab environment (generated)

Written by \`scripts/setup-lab.sh\`. Re-run it to refresh; do not hand-edit.

| Fact | Value |
|---|---|
| Project | \`${PROJECT}\` (number ${PROJECT_NUM}) |
| Organisation | ${ORG_ID:-none visible} |
| Region / zone | \`${REGION}\` / \`${ZONE}\` |
| Billing enabled | ${BILLING} |
| Public IP (admin_cidr) | ${MYIP:-undetected} |

## Capability probe

| Capability | Result | Consequence |
|---|---|---|
| Set org policy (project scope) | **${ORGPOLICY_WRITE}** | $( [ "${ORGPOLICY_WRITE}" = yes ] && echo 'Org Policy is the preventative control (`enable_org_policy = true`)' || echo 'Gatekeeper admission control is the preventative control' ) |
| List SCC findings | **${SCC_READ}** | $( [ "${SCC_READ}" = yes ] && echo 'SCC is the detective control' || echo 'Log-based metric + Monitoring alert is the detective control' ) |

Both paths are implemented, so this probe selects a path rather than creating work.
**Caveat:** SCC Security Health Analytics takes hours to populate after resources are
created — an empty console shortly after \`apply\` is expected, not a failure.

## Next
\`\`\`bash
cd terraform
tofu init -backend-config=backend.hcl
tofu plan
tofu apply
\`\`\`
EOF
ok "captured to docs/lab-environment.md"

step "Summary"
printf '  org policy write : %s\n  SCC findings     : %s\n  detective        : %s\n  preventative     : %s\n\n' \
  "${ORGPOLICY_WRITE}" "${SCC_READ}" \
  "$( [ "${SCC_READ}" = yes ] && echo 'SCC' || echo 'log-based alert' )" \
  "$( [ "${ORGPOLICY_WRITE}" = yes ] && echo 'Org Policy' || echo 'Gatekeeper' )"
echo "  next: cd terraform && tofu init -backend-config=backend.hcl && tofu plan"
