# VCS / pipeline security controls

Exercise requirement: *"You must implement security controls in your VCS platform both for the repository as well as scanning the IaC code + Container Image prior to deployment."*

Scanning lives in the two workflows; the repository-level controls below are GitHub settings. Both halves are needed — this page is what you walk the panel through.

## 1. Repository controls (GitHub settings)

| Control | What it stops |
|---|---|
| **Branch protection on `main`** — require a PR, require the `validate + scan` and `build + scan` checks to pass, dismiss stale approvals, block force-push and deletion | Unreviewed or unscanned code reaching `main`, history rewrites |
| **Secret scanning + push protection** | Credentials committed at all — blocked at `git push`, not found later |
| **Code scanning (SARIF)** | Checkov / Trivy findings surface as PR annotations instead of buried CI logs |
| **Dependabot** (`.github/dependabot.yml`) | Stale Actions and base images — supply-chain drift *in the pipeline itself* |
| **Environment `lab` with required reviewer** | An automated `apply` / deploy landing without a human |
| **Least-privilege `GITHUB_TOKEN`** (`permissions: contents: read`, escalated per job) | A compromised action rewriting the repo |
| **Keyless cloud auth (Workload Identity Federation)** | Long-lived service-account keys sitting in repo secrets |

Apply the main ones from the CLI:
```bash
gh api -X PUT repos/:owner/:repo/branches/main/protection \
  -F required_pull_request_reviews.required_approving_review_count=1 \
  -F 'required_status_checks.contexts[]=validate + scan' \
  -F 'required_status_checks.contexts[]=build + scan' \
  -F required_status_checks.strict=true \
  -F enforce_admins=true \
  -F restrictions=null \
  -F allow_force_pushes=false \
  -F allow_deletions=false

gh api -X PATCH repos/:owner/:repo \
  -f security_and_analysis[secret_scanning][status]=enabled \
  -f security_and_analysis[secret_scanning_push_protection][status]=enabled
```

## 2. Pipeline scanning (the gate)

| Stage | Tool | Runs |
|---|---|---|
| IaC misconfiguration | **Checkov** + **Trivy config** | Every PR touching `terraform/`, **before** any `apply` |
| Container image CVEs | **Trivy** (`CRITICAL,HIGH`) | **Before** push to Artifact Registry — a failing image never reaches the registry or the cluster |
| Required-file proof | `docker run … cat /app/wizexercise.txt`, then `kubectl exec` post-deploy | Build and cluster |

**Why findings do not fail the build here:** the environment is *deliberately* misconfigured and NodeGoat is *deliberately* vulnerable, so both scanners fire by design. `soft_fail` / `exit-code: 0` keeps the lab pipeline green while still publishing every finding to code scanning. In production these flip to fail-on-CRITICAL. **Say this out loud in the demo** — otherwise it reads as a weak gate rather than a deliberate one.

## 3. Workload Identity Federation (no static keys)
```bash
gcloud iam workload-identity-pools create github --location=global
gcloud iam workload-identity-pools providers create-oidc github \
  --location=global --workload-identity-pool=github \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository"
# bind a deploy SA, restricted to this repository
gcloud iam service-accounts add-iam-policy-binding "$DEPLOY_SA" \
  --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/projects/$PROJECT_NUM/locations/global/workloadIdentityPools/github/attribute.repository/$GH_OWNER/$GH_REPO"
```
Repo secrets required: `GCP_WIF_PROVIDER`, `GCP_DEPLOY_SA`, `GCP_PROJECT_ID`, `ADMIN_CIDR`, `MONGO_PASSWORD`.

## 4. The point to land on slide 9
The pipeline finds the vulnerable dependency **and** the IaC misconfiguration — but each in isolation, as a list. It cannot tell you that *this* image is the one running in a cluster-admin pod, behind an internet-facing load balancer, next to a VM whose service account can reach the cloud control plane, with database backups already public.

**That correlation — code finding → running cloud context → exploitable path — is what Wiz Code adds on top of exactly this pipeline.** A point tool gives you 50 findings; Wiz gives you the one path that matters.

## Known gaps (be honest if asked)
- Actions are pinned by tag, not commit SHA. SHA-pinning is the stronger supply-chain control; tags were kept for readability in a lab.
- No signing/attestation (Sigstore/cosign) or Binary Authorization — the natural next step, and what I would add before this pipeline went anywhere near production.
