# Wiz Technical Exercise

Deliberately-vulnerable two-tier web application on **GCP**, built with Terraform + CI/CD, with cloud-native security controls layered on top.

> ⚠️ **This environment is intentionally insecure.** The weaknesses below are *requirements of the exercise*, not accidents — they exist to demonstrate a realistic attack path and how it is detected and prioritised. It is a short-lived sandbox (CloudLabs), torn down after the panel.
>
> 🔐 **Repo hygiene is deliberate and separate from the environment's posture:** no credentials, state, or tfvars are committed (see `.gitignore`). The *infrastructure* is vulnerable by design; the *supply chain* is not.

## Architecture
```
Internet → Load Balancer → Ingress → containerized app (GKE, private subnet)
                                          │
                                          ▼
                              MongoDB on GCE VM (public subnet)
                                          │  daily backup
                                          ▼
                              GCS bucket (public read + list)
```

## Intentional weaknesses (the attack path)
| # | Weakness | Role in the attack path |
|---|----------|------------------------|
| 1 | VM on 1+ year outdated Linux, **SSH open to 0.0.0.0/0** | Initial access |
| 2 | VM service account **over-permissive** (can create VMs) | Privilege escalation → cloud control plane |
| 3 | **MongoDB 1+ year outdated** (auth on, reachable only from GKE) | Known CVEs |
| 4 | Backup bucket **public read + list** | Data exposure |
| 5 | App container bound to **cluster-admin** | Full K8s takeover from one pod |

→ Individually these are five findings. **Together they are one exploitable path** from the internet to the data and the cloud control plane — the "toxic combination" story.

## Layout
```
terraform/     # network, Mongo VM, GKE, bucket, IAM, security controls
app/           # containerized todo app + Dockerfile (+ wizexercise.txt)
k8s/           # deployment, service, ingress, RBAC
.github/       # CI/CD: IaC pipeline + build/deploy pipeline (with scanning)
docs/          # notes, screenshots, demo script
```

## Security controls
- **Audit logging** — Cloud Audit Logs (admin activity + data access)
- **Detective** — log-based metric + Cloud Monitoring alert on anonymous reads of the backup bucket. *(Security Command Center is org-scoped; this sandbox is project-scoped and `securitycenter.findings.list` is denied — so detection was built where authority actually exists.)*
- **Preventative** — blocks *new* bad actions (kept separate so the intentional weaknesses survive for the demo)
- **Pipeline** — IaC scanning + container image scanning before deploy

## Quickstart
```bash
cd terraform && terraform init && terraform plan   # validate locally BEFORE redeeming the lab
```

## Design decisions

Every non-obvious choice — and every trade-off made knowingly rather than
missed — is recorded in [`docs/decisions.md`](docs/decisions.md). Operational
detail lives alongside it in [`docs/`](docs/): the AppSec pipeline, the
sandbox's constraints, Terraform practices, and the runbook.
