# CloudLabs sandbox — constraints and cost

Facts from the Wiz Labs Candidate Sandbox welcome page, and what they mean for this build.

| Constraint | Value | Impact |
|---|---|---|
| **Duration** | **14 days from lab start** | The walkthrough sits comfortably inside the window. Extension requestable if needed. |
| **Cost cap** | **$200 per candidate** | The real constraint. See below. |
| **Supported regions** | us-east4, us-central1, us-west1, **europe-west1**, australia-southeast1 | ✅ `europe-west1` is supported — the existing default stands, no change needed. |
| **Pre-configured resources** | Do not modify or delete | We only create new resources. Safe. |
| **Teardown** | All lab resources deleted at completion | Everything is IaC, so the build is reproducible from the repo. This is exactly the argument for IaC — worth saying in the demo. |

## Cost management
Rough estimate, running continuously for 14 days:

| Resource | ~14-day cost |
|---|---|
| GKE cluster management fee | ~$33 |
| Node pool (2 × `e2-medium`, trimmed from `e2-standard-2`) | ~$22 |
| Mongo VM (`e2-medium`) | ~$11 |
| Cloud NAT | ~$15 |
| HTTP(S) Load Balancer | ~$8 |
| Storage / Secret Manager / logging | ~$5 |
| **Total** | **~$95** |

Headroom for rebuilds, which is the point — a first `apply` rarely survives contact.

**Levers if it gets tight:**
1. **`tofu destroy` between the build phase and panel prep**, then re-apply the day before. The whole environment is code; rebuild is one command. *(Do a timed rebuild once first, so you know how long it takes and that it works.)*
2. Scale the node pool to zero when idle — the cluster management fee still accrues, so destroy is the stronger lever.
3. The load balancer only exists once the Ingress is applied; delete the Ingress when not demoing.

**Watch spend:** Billing → Reports in the console, filtered to this project.

## Sizing note for the panel
The node pool is deliberately small — sized for a sandbox cost cap, not for production. If asked about capacity or HA, that is the honest answer: **a cost constraint I chose to respect, not an architectural opinion.** A production deployment would run a regional cluster across three zones with larger nodes and autoscaling.

## ⚠️ The dynamic public IP — a real demo-day risk

`admin_cidr` gates GKE control-plane access, and **this ISP rotates the address several times a day** — not daily, as first assumed:

| Observation | Egress IP *(network prefix redacted — this is a home connection)* |
|---|---|
| day 1 | `x.x.90.101` |
| day 4 | `x.x.134.169` |
| day 5 (morning) | `x.x.147.247` |
| day 5 (afternoon) | `x.x.188.88` |

It had already gone stale within a day of `setup-lab.sh` writing it. **Assume it will be wrong on the morning of the panel.**

**The ritual, first thing on the morning of the walkthrough:**
```bash
just myip          # compares, exits non-zero on mismatch and prints the fix
# if it mismatches:
sed -i '' 's|admin_cidr = .*|admin_cidr = "<new>/32"|' terraform/terraform.tfvars
just plan && just apply      # ~1-2 min: only master_authorized_networks changes
```

**Only `https://api.ipify.org` is reachable** from this network — icanhazip, checkip.amazonaws.com, ipinfo.io, ident.me and ifconfig.me are all blocked by the local egress policy, as is DNS to external resolvers. The recipes try ipify first for that reason.

**This is now configured** (D12): the precise `/32` remains the primary, with the ISP's `/16` as an explicit fallback, because rotation was locking `kubectl` out within hours. Say the trade-off out loud rather than leaving a reviewer to notice a `/16` and wonder.

### Also required for kubectl: the GKE auth plugin
`kubectl` needs `gke-gcloud-auth-plugin` on PATH. Homebrew installs the Cloud SDK under `share/` and symlinks only `gcloud` into `bin/`, so the plugin is present but invisible — `gcloud components list` shows it *Installed* while `kubectl` fails with *"executable gke-gcloud-auth-plugin not found"*. `.envrc` now adds the SDK `bin` to PATH, and `setup-lab.sh` checks for it during preflight.
