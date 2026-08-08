# Runbook — one-time setup vs. every deploy

## Once per sandbox (~5 min)

| # | Command | What it does | Why it can't be Terraform |
|---|---|---|---|
| 1 | `gcloud auth login`<br>`gcloud auth application-default login` | Human + **ADC** credentials | Terraform authenticates *with* these — it cannot create them. **ADC is separate from the gcloud login and is the most common silent failure.** |
| 2 | `direnv allow` then `./scripts/setup-lab.sh` | Verifies creds/billing, **probes capabilities**, detects your IP, writes `terraform.tfvars` + `backend.hcl`, captures findings to `docs/lab-environment.md` | Capability discovery is *discovery*, not desired state |
| 3 | `./scripts/bootstrap-state.sh` | Creates the GCS state bucket | A bucket cannot live in the state it holds |
| 4 | `cd terraform && tofu init -backend-config=backend.hcl` | Wires the backend | — |

*(Step 2 calls step 3 for you; run it standalone only to see its output.)*


## Every deploy

```bash
just plan          # review
just apply         # infrastructure  (~15 min first run: GKE is the slow part)
just creds         # point kubectl at the cluster

# the Mongo credential, straight from Secret Manager — never touches your shell
kubectl create secret generic mongo-credentials \
  --from-literal=uri="$(gcloud secrets versions access latest --secret=wizex-mongo-uri)"

just build && just push && just deploy
just seed
just url           # load balancer IP (a few minutes to provision)
```

## Before the demo
```bash
just myip          # has your public IP moved? if so update admin_cidr and re-apply
just demo-proof    # health + wizexercise.txt in the running container + the RBAC binding
just url           # open it in a browser
```

## Teardown
```bash
just destroy
```
Nothing has `prevent_destroy`; teardown is clean. The state bucket is created outside Terraform, so `destroy` leaves it — delete it by hand if you want the project spotless.

## What is one-time vs. repeatable, and why it matters
Only **four** commands are one-time, and three of them exist because of a real constraint rather than convenience:

- **Credentials** are Terraform's *precondition*, not its output.
- **Capability discovery** answers "what am I allowed to do here?" — a question, not a resource.
- **The state bucket** is the single genuine chicken-and-egg.

Everything else — APIs, secrets, network, cluster, VM, bucket, IAM, monitoring — is `tofu apply`. That boundary is the honest answer to *"why is any of this a shell script?"*
