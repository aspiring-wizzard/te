# Decisions

Running log of build decisions and their rationale — feeds slide 6 ("how you built it") and slide 10 ("what you'd do differently").

## D1 — IaC: Terraform (not Pulumi)
**Decision:** build the environment in **Terraform**.

**Considered:** **Pulumi** — a real programming language (loops/conditionals without HCL contortions), one program for both infrastructure and Kubernetes, and `pulumi preview` diffs demo nicely. Genuinely viable: the exercise mandates "modern DevOps tools/best practices" and never names a tool, and Pulumi's GCP provider covers everything needed here.

**Why Terraform won:**
1. **IaC scanning is a graded requirement.** Checkov/tfsec/Trivy have deep, mature HCL support; Pulumi coverage is thinner (policy-as-code would mean leaning on CrossGuard). Keeping the scanner step frictionless matters because it feeds the **Wiz Code** narrative.
2. **Panel legibility.** All four panelists are Wiz Principal Customer Engineers; Wiz's own scanning, docs and customer conversations are Terraform-centric. HCL is instantly scannable to them.
3. **Risk budget.** The exercise is scored on the **attack-path / toxic-combination narrative**, not tooling novelty. Don't spend differentiation on the IaC language.

**Slide 10 remark (say this):** *"Terraform-style HCL was a deliberate choice for the scanning ecosystem and reviewer legibility; Pulumi was the considered alternative for expressiveness and a single program across infra and K8s — a fair trade I'd revisit if the pipeline standardised on policy-as-code."*

## D2 — IaC runtime: OpenTofu (HCL unchanged)
**Decision:** author standard HCL, execute with **OpenTofu** (`tofu`) rather than the Terraform CLI.

**Why:** the deliverable `.tf` files are byte-identical (same `hashicorp/google` provider, same `required_providers`), so **IaC scanning is unaffected** — Checkov/tfsec/Trivy read the files, not the binary. OpenTofu is **MPL-2.0** (Linux Foundation) and sidesteps the BSL licence question, which is a genuine enterprise consideration.

**Cost:** none functionally. CI uses `opentofu/setup-opentofu` instead of `hashicorp/setup-terraform`.

**Have ready if asked "why not Terraform?":** *"Same HCL, same providers, open licence, no functional difference — and every scanner in the pipeline behaves identically."*

## D4 — Secrets: none in the repository; state treated as secret
**Decision:** no secret enters the repository at all. Terraform generates the Mongo password (`random_password`) into **Secret Manager**; the Kubernetes Secret is created at deploy time by reading it back. State lives in a versioned, IAM-restricted, public-access-**enforced** GCS bucket.

**This supersedes an earlier SOPS + GCP KMS design, and the reason is worth telling.** SOPS was introduced when the password was a required Terraform *input* — encrypting it meant it could be committed. Once Terraform generated it instead, the remaining inputs were `project_id`, `region`, `zone`, `admin_cidr`, `enable_org_policy` — **none of them secret**. SOPS was encrypting nothing.

Keeping it would have been worse than useless: a SOPS-encrypted Kubernetes Secret in git *plus* the Secret Manager copy is **two sources of truth for one credential**. Rotate one, the other silently goes stale. That is precisely the drift a CNAPP exists to surface, so shipping it in an exercise about correlation would have been hard to defend.

**The stronger claim, and it is now true:** *no credential exists in this repository in any form, encrypted or otherwise.* Secret scanning has nothing to find because there is nothing there.

**The residual gap, unchanged:** the generated password still resolves into Terraform **state**, which is why state is treated as a secret. See D10 for the fix.

**Lesson worth saying out loud:** a control that no longer protects anything is not neutral — it is a liability, because it implies a guarantee it no longer provides. Removing SOPS was a security improvement, not a simplification.

## D10 — Secret delivery: imperative pull now, external-secrets next
**Decision:** create the Kubernetes Secret at deploy time from Secret Manager —
```bash
kubectl create secret generic mongo-credentials \
  --from-literal=uri="$(gcloud secrets versions access latest --secret=wizex-mongo-uri)"
```

**Why not a committed manifest:** it would duplicate the credential (D4).

**Trade-off accepted:** the Secret itself is not in code, so that one object is imperative rather than declarative.

**The enhancement — `external-secrets` (posture, and the honest next step):** install the operator, bind the pod's service account to Secret Manager via **Workload Identity**, and declare an `ExternalSecret` CR. Then the *binding* is in code, Secret Manager stays the single source of truth, nothing is duplicated, and rotation propagates on its own. The exercise's requirement — Mongo access via an environment variable configured in Kubernetes — is satisfied either way, since the operator produces an ordinary Secret.

**Why not now:** roughly an hour, against a fixed panel date and a 14-day sandbox. It is a posture improvement rather than a missing control, so it belongs on the closing slide as a named next step.

## D5 — What belongs in IaC, and what cannot
**Decision:** move API enablement and the Mongo password into Terraform; keep authentication, ADC and capability discovery in `scripts/setup-lab.sh`; keep the state bucket in `bootstrap-state.sh`.

**The boundary, which is the actual point:** Terraform can own anything that is a *declarative statement about the project*. It cannot own its own *preconditions* — you cannot Terraform the credentials Terraform authenticates with, and a capability probe (`test-iam-permissions`) is discovery, not desired state. The state bucket is the one honest exception: it cannot be stored in the state it holds.

**If asked "why is any of this a shell script?":** *"Authentication and capability discovery are preconditions for Terraform, not resources it can own. Everything downstream of that boundary is managed."* Better than claiming everything is automated, because it is true.

## D6 — Mongo password: generated, not supplied
**Decision:** `random_password` generates it; Secret Manager stores the password and the full URI; an output prints the `kubectl create secret` that reads straight from Secret Manager.

**Why:** the credential now never exists in `tfvars`, in a shell, in shell history, or on the clipboard.

**The limitation, stated not hidden:** it still resolves into Terraform **state**. Mitigation is treating state as a secret (versioned, IAM-restricted, public-access-enforced GCS). The real fix — generate on the VM at boot, write straight to Secret Manager, never let it pass through Terraform — remains on the closing slide.

## D7 — GKE control-plane access, and what it means for CI
**Decision:** `master_authorized_networks` renders from `admin_cidr` plus an optional `extra_admin_cidrs` list.

**The consequence worth volunteering:** GitHub-hosted runners have dynamic egress IPs and cannot be pinned this way, so **CI owns build, scan and push; the cluster deploy runs from an authorised network.** The correct fix is the GKE Connect gateway (authenticate through the Google API rather than the control-plane IP) — more moving parts than a 14-day sandbox warrants.

**Also worth saying:** control-plane access is a *genuine* control, deliberately not one of the intentional weaknesses. The contrast with the world-open SSH rule is the point.

## D8 — DAST: ZAP baseline, not active scan
**Decision:** `dast.yml` runs the ZAP **baseline** (passive spider + passive rules).

**Why:** an active scan attacks the target. Against a deliberately vulnerable app that is also the demo environment, that risks destroying the thing being demonstrated. Baseline proves the control is wired and keeps the environment intact. In a real programme, active scanning belongs in a disposable staging environment.

## D9 — Sizing to the sandbox cost cap
**Decision:** GKE node pool of 2 × `e2-medium` on 30 GB `pd-standard`, trimmed from `e2-standard-2`.

**Why:** the CloudLabs sandbox caps spend at **$200**. The original sizing put the 14-day estimate around $120, leaving no headroom for rebuilds — and a first `apply` rarely survives contact. This lands near $95.

**If asked about capacity or HA:** *"A cost constraint I chose to respect, not an architectural opinion."* Production would be a regional cluster across three zones with autoscaling.

## D11 — The outdated VM image: pinned, not a family alias
**Decision:** boot the Mongo VM from `ubuntu-os-cloud/ubuntu-2004-focal-v20200423` — the **original April 2020 Ubuntu 20.04 release build**. Over six years old, unpatched, and past end of standard support since April 2025.

**Why a pinned build rather than a family alias:**
1. **A family alias is freshly patched.** It satisfies "1+ year outdated *version*" on paper while giving a vulnerability scanner almost nothing to find. The pinned April 2020 build is unpatched — the exposure is real, not nominal.
2. **A family alias silently changes what `apply` builds.** Pinning is reproducible, which is the whole point of infrastructure as code. Using a moving alias in a security demo would undercut the argument being made.

**The part worth telling — pinning is why this is still buildable at all.** An early `apply` failed with `Could not find image or family ubuntu-2004-lts`: Google retired the **family alias** after EOL. The obvious conclusion — "20.04 is gone, use 22.04" — was wrong, and I acted on it before checking. The individual images are all still present and `READY`, merely marked `DEPRECATED`, so an **exact name keeps resolving long after the alias dies**. Pinning did not just make the build reproducible; it outlived the alias.

**The correction mattered,** because 22.04 quietly broke the application — see D13. The two are coupled, which is the real lesson: the OS choice was never independent.

**Note:** the apt suite (`focal`) is a separate variable and must track the image — MongoDB's repository path is codename-specific, so the two drift apart silently if only one is changed. That coupling is now load-bearing (D13).

## D13 — MongoDB 5.0 is a compatibility floor, not a preference
**Decision:** pin MongoDB to the **5.0** series (`var.mongo_version`), and `apt-mark hold` it so an unattended upgrade cannot move it.

**Forced by the application, discovered at runtime.** On MongoDB 6.0 the app connected successfully and then failed *every* read and write:

```
MongoError: Unsupported OP_QUERY command: find    (code 352)
```

NodeGoat ships a 2016-era driver that speaks the legacy **OP_QUERY** wire protocol. MongoDB **removed OP_QUERY in 5.1**. So 5.0 is the newest server the application can talk to at all — not a choice, a ceiling.

**Why this is a better story than the version I originally picked:**
- MongoDB 5.0 went **end-of-life in October 2024**, so the datastore is genuinely unsupported and unpatched. The "outdated component" finding is real rather than contrived.
- **The outdated version is forced by the application.** Nobody chose to run EOL software; an old dependency pinned it. That is exactly how legacy risk actually arrives — and it is why "just patch it" is not an answer a platform team can unilaterally execute.
- Fixing it properly means **upgrading the app's driver**. This is an AppSec problem wearing an infrastructure costume — which is the argument I want to be making in this role.

**The coupling that bit:** MongoDB 5.0 publishes **server** packages for `focal` only. The `jammy/5.0` suite *exists* and returns HTTP 200 — but ships only the shell and tools, so `apt-get install mongodb-org` fails there. A reachable repository is not a supported one. Checking that the `Release` file exists was not enough; I had to read the package index. Hence 20.04 (D11) and 5.0 are a matched pair, and `mongo_image` / `mongo_apt_suite` / `mongo_version` must move together.

**Also non-obvious:** `mongodb-mongosh` is *not* pulled in by the `mongodb-org` metapackage on 5.0 — that series still ships the legacy `mongo` shell. The provisioning script uses `mongosh` throughout, so it now asks for it by name rather than inheriting it by luck.

## D14 — Mutable image tags: `Always` now, digest pinning in production
**Decision:** set `imagePullPolicy: Always` on the Deployment and seed Job.

**Forced by:** rebuilding and re-pushing `:v1` changed nothing. `kubectl apply` reported `deployment unchanged` — correctly, since the pod spec was byte-identical — so no new ReplicaSet was created, and the nodes kept serving the **stale layers they had cached under that tag**. The default pull policy for any tag other than `:latest` is `IfNotPresent`.

**Why it is worth raising unprompted:** this is a supply-chain property, not an operational annoyance. If `:v1` can mean different bytes at different times, then *"what is running?"* is not answerable from the manifest — and two pods from different ReplicaSets can run **different builds under the same tag**, which is exactly what happened here before the cleanup.

**Production posture:** pin by **digest** (`@sha256:…`) and enforce it with **Binary Authorization**, so only an attested image runs and the manifest is a truthful record of what is deployed. `Always` is the pragmatic fix inside a demo's rebuild loop; the digest is the real answer.

## D15 — Kubelet probes and Google Cloud health checks disagree
**Decision:** add a `BackendConfig` pointing the load-balancer health check at `/login`, and align the kubelet readiness probe to the same path.

**Forced by:** pods sat `Ready=False` with a healthy container and zero restarts. The blocking condition was the GKE container-native LB readiness gate:

```
cloud.google.com/load-balancer-neg-ready = LoadBalancerNegNotReady
ContainersReady=True   restarts=0
```

**The trap:** a kubelet `httpGet` probe treats any **2xx or 3xx** as success. A Google Cloud health check requires a strict **200** and does not follow redirects. NodeGoat's `/` returns `302 → /login`. So the same URL passed the kubelet and failed the load balancer *permanently* — the app looked healthy by every `kubectl` signal while the ingress refused to serve it.

**Generalisable point:** "healthy" is not one predicate. Two layers were asking different questions of the same endpoint and only one of them was visible in `kubectl get pods`.

## D16 — The database address is declared, not inherited
**Decision:** reserve an internal address (`google_compute_address`) for the Mongo VM instead of accepting whatever DHCP assigns.

**Why:** the connection URI embeds that address and is consumed in two places updated on different schedules — the Secret Manager URI (rendered by Terraform, always current) and the Kubernetes Secret (created out-of-band). With an ephemeral address, **rebuilding the VM moves the database and leaves the cluster pointing at nothing**, surfacing as a confusing app-level timeout rather than as "the thing you just rebuilt has a new address."

Paired with `just k8s-secret`, which re-derives the Kubernetes Secret **from Secret Manager** rather than from a hand-typed string, so the credential cannot drift from the database it points at. The one manual step in the chain was the one that broke on every rebuild.

## D17 — The preventative control was inert, then it evicted the workload
**Decision:** install Gatekeeper via `just gatekeeper`, scaled to a single controller replica.

**Two failures worth owning, because both were silent.**

**It was never installed.** `90-preventative-gatekeeper.yaml` and its DENYME counterpart had existed since early in the build, and I had treated the requirement as met because the *manifest* existed. It wasn't: there was no admission controller behind it, so applying the privileged pod would have **succeeded** — demonstrating the exact opposite of the control's point, in front of the panel. A policy manifest with no enforcement engine is a document, not a control. This is worth stating plainly rather than hiding, because it is the same failure mode as a policy-as-code repo with no admission webhook wired up, and that is a real and common finding.

**Then installing it broke the app.** Gatekeeper's stock deployment is HA — 3 controller replicas plus audit, ~400m CPU and 2Gi memory. On a cluster deliberately sized down to a $200 sandbox cap (2 × `e2-medium`, D9), that pushed both nodes past **90% CPU requests** and left NodeGoat `Pending`: *the security control evicted the workload it existed to protect.*

**The generalisable point:** controls are not free, and admission controllers land on the same nodes as the workload. "Turn on the policy engine" is a capacity decision as well as a security one — which is a large part of why security tooling gets disabled in the real world. In production you size the cluster for the controls; in a cost-capped sandbox you right-size the control. One replica is ample for a single constraint.

**Also non-obvious:** the manifest holds a `ConstraintTemplate` *and* the constraint that depends on it, but the constraint's CRD is **generated by Gatekeeper from the template** — so the first apply always half-fails with `no matches for kind K8sDenyPrivileged`. Apply, wait for the CRD, apply again. `just gatekeeper` does this.

## D18 — Native cloud controls: Security Posture and Binary Authorization

**Decision:** add two GCP-native controls alongside the Gatekeeper one — **GKE Security Posture** (detective) and **Binary Authorization** (preventative) — both declared in Terraform (`gke.tf`, `security-binauthz.tf`).

**Why, and what it fixes about the earlier story.** The Cloud Native Security requirement leans hard on *CSP-native* tooling, and the honest gap was that our strongest controls were either third-party (Checkov/Trivy in CI) or Kubernetes-layer (Gatekeeper). Security Command Center — the obvious native answer — is denied: `securitycenter.findings.list` and `orgpolicy.policy.set` both fail in this project-scoped CloudLabs sandbox (confirmed via `testIamPermissions`). So SCC and Org Policy are genuinely out of reach. But two native controls *were* in reach, and `testIamPermissions` confirmed the permissions before any work:

- **GKE Security Posture** was already enabled at `BASIC` (a GKE default). Made it explicit in IaC and turned on `VULNERABILITY_BASIC`, so it now audits both workload **misconfiguration** (privileged, runAsRoot, over-broad RBAC) and image **CVEs**, project-scoped, agentless. This is the native detective equivalent of SCC for the workload layer — findings in the GKE Security Posture dashboard and Cloud Logging.
- **Binary Authorization** — admission control enforced by the **GKE control plane itself**, not a pod we installed. A default-deny policy with the application image allowlisted, `global_policy_evaluation_mode = ENABLE` so Google-managed system images stay exempt. It removes the one soft spot in the preventative story: whether Gatekeeper is a *cloud* control or a *Kubernetes* one. Binary Authorization is unambiguously the former.

**The two preventative controls are deliberately kept distinct in the demo.** The Gatekeeper prop uses the **allowlisted app image** so Binary Authorization admits it and Gatekeeper is unambiguously the control that rejects it (on `privileged: true`). The Binary Authorization prop is a boring, non-privileged `nginx` pod whose only sin is an un-allowlisted image — Gatekeeper is happy with it, the control plane refuses it. Two controls, two different questions: *is this workload configured safely?* versus *are we allowed to run this image at all?*

**One thing that bit, worth knowing:** the allowlist `name_pattern` matching is not obvious. A pattern like `.../nodegoat*` matches the image, but the safest form is the exact image path (no trailing wildcard), which matches all tags and digests of that image. The failure mode is quiet — a too-narrow pattern blocks your *own* new pods at admission while existing pods keep running, so the app looks healthy and only a rollout reveals it. (Here the surge that exposed it turned out to be CPU, not the pattern — but the trap is real.)

**Cost note:** neither control adds a pod. Security Posture and Binary Authorization are control-plane features, so unlike Gatekeeper (D17) they add no CPU pressure to the cost-capped nodes.

## D19 — The detective control watches the misconfiguration, not the read

**Decision:** the log-based alert fires on a bucket being **granted public access**
(`storage.setIamPermissions` adding `allUsers`/`allAuthenticatedUsers`), not on
an anonymous read of it.

**Forced by a blind spot I found by testing, not by reading docs.** The original
control filtered Data Access logs for `principalEmail=""` — an anonymous read of
the backup bucket. It looked right and it can never fire: **Cloud Audit Logs do
not record `allUsers` access.** Verified empirically — an anonymous object GET
returns `200` and produces **zero** data-access log entries, while my own
authenticated calls to the same bucket log fine. Anonymous reads surface only in
the legacy, hourly-batched bucket *usage* logs, which are neither real-time nor
worth demoing. A filter for an event the platform never emits is a control that
exists on paper and not in fact — the same shape as the inert Gatekeeper
manifest (D17), caught the same way: by checking whether it actually fires.

**The fix is also the better control.** `storage.setIamPermissions` is an **Admin
Activity** event — always on, cannot be disabled — so alerting on the public-grant
fires the moment *any* bucket in the project is made public, in real time, before
a byte leaves. Detecting the door being unlocked beats hoping to catch someone
walking through it, and it fires **once at the misconfiguration** rather than on
every read.

**The blind spot is itself a talking point, not just a workaround.** "Cloud Audit
Logs don't see anonymous access" is a sharp, non-obvious fact about GCS — the kind
of gap a CNAPP with its own data plane exists to cover. Naming it is stronger than
quietly routing around it.

**Verified:** the corrected filter matches both the historical grant (when
Terraform made the bucket public) and a fresh test grant; the metric ticks and the
alert condition trips within ~a minute. Repeatable demo trigger:
`gsutil iam ch allAuthenticatedUsers:objectViewer gs://<bucket>`, then `-d` to
remove it — the intentional `allUsers` weakness is left untouched.

## D12 — Control-plane allowlist: a /32 plus the ISP range
**Decision:** `admin_cidr` stays the precise current `/32`; `extra_admin_cidrs` adds the ISP's `/16` as an explicit fallback. *(Actual addresses are redacted here — this is a residential connection, and the repository is public.)*

**Why:** this ISP rotates the egress address **several times a day** — `x.x.134.169` → `x.x.147.247` → `x.x.188.88`, all within a single day. A `/32` alone was locking `kubectl` out within hours, and would plausibly do so *during* the panel. Being unable to reach your own cluster mid-demo is a materially worse outcome than a wider allowlist on a throwaway sandbox.

**The trade-off, stated rather than hidden:** a `/16` of consumer ISP space is far weaker than a `/32`. It is still enormously better than `0.0.0.0/0`, the cluster still requires authentication, and this is a 14-day sandbox holding nothing real. In production the answer is not a wider CIDR — it is the **GKE Connect gateway** or a bastion behind IAP, so control-plane access never depends on a client IP at all.

**Say it before they ask.** A reviewer who spots a `/16` and is not told why will assume carelessness.

## D3 — Application: OWASP NodeGoat (not the sample todo app)
**Decision:** use **[OWASP NodeGoat](https://github.com/OWASP/NodeGoat)** (Node.js + MongoDB, port 4000) as the containerised app, rebuilt with `wizexercise.txt` added.

**Considered:** the sample todo app linked in the exercise PDF (what most candidates use), and writing a bespoke app.

**Why NodeGoat:**
1. **It makes the image scan produce real findings.** A clean todo app gives the CI scanner nothing to catch; NodeGoat ships deliberately vulnerable code and dependencies, so Trivy/`npm audit` surface genuine SCA results — **which is what powers the Wiz Code narrative** ("this is where Wiz Code catches it in the PR").
2. **It completes the story.** Vulnerable *code* + vulnerable *cloud* + vulnerable *cluster* = **code → cloud → runtime**, demonstrated rather than described. That is Wiz's own thesis.
3. **Recognition** — an OWASP project the panel will know on sight.
4. **Zero build risk** — Mongo-backed, dockerised, `MONGODB_URI` env var satisfies the "config via env var in Kubernetes" requirement.

**Stretch goal (if time permits):** a small bespoke app with a "blast radius" page that uses its own cluster-admin token to list K8s secrets and hit the GCE metadata server. Same effect is achievable live via `kubectl` in the demo, so this is optional polish, not critical path.
