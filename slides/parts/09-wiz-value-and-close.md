---
layout: two-cols-header
---

# Where Wiz changes the outcome

**What value would Wiz provide here?** The pipeline already finds *both* halves of this. **Nothing in it joins them up.**

::left::

### What I have today

- **Checkov + Trivy config** on `terraform/` — the world-open SSH rule, `roles/editor` on the Mongo SA, `allUsers` on the backup bucket
- **Trivy** on the image — CVEs across `node:16-bullseye` and NodeGoat's dependency tree
- **A log-based metric + alert** on anonymous reads of the bucket — post-deploy, in a third console, and it only fires *after* the data has been downloaded

<div class="mt-4 text-sm opacity-80">

Three lists, each on its own scale, **none aware the other two exist**. Snyk on the app side would give me a *better* flat list — still flat. SCC would simply be a fourth console reporting the same misconfigurations again.

</div>

::right::

### What none of them can say

- That the CVE-ridden image is the one running behind the load balancer, **unauthenticated**
- That its ServiceAccount is bound to **`cluster-admin`** — one RCE in NodeGoat reads every Secret in the cluster, `mongo-credentials` included
- That the VM on the other end of that credential holds **`roles/editor`**: one metadata call from the GCP control plane
- That `wizex-backups-*` is already `allUsers` — **that path to the data needs no exploit at all**

<style>
  .slidev-layout li { font-size: 0.8rem; line-height: 1.42; margin-bottom: 0.4rem; }
</style>

<!--
The pipeline is not the value story — it is the setup for it. Every finding on the left is real
and already caught. The right-hand column is not a tooling gap, it is a MODEL gap: no scanner
holds identity, reachability and RBAC in one place.
-->

---
layout: default
---

# What Wiz adds: the edges, not more findings

- **Security Graph** — cloud resources, identities, network exposure, Kubernetes RBAC *and* the repository in one model. The chain becomes a **query result**, not something I had to be clever enough to spot.
- **Toxic combination** — five findings nobody would page you about resolve to one critical attack path: internet → pod → `cluster-admin` → Secret → database → `roles/editor` → control plane. **Fifty tickets collapse to one.**
- **Agentless** — snapshot scanning of `wizex-mongo` and the GKE nodes: nothing installed on a host I already do not trust, and a 14-day sandbox inventoried in minutes. An agent rollout was never going to happen here.
- **Code to cloud (Wiz Code, Dazz)** — the running container traced back to `FROM node:16-bullseye` in `app/Dockerfile`; the public bucket back to `google_storage_bucket_iam_member.public_read` in `terraform/bucket.tf`. The fix ships as a **pull request against the IaC** — which matters precisely here, because a console fix is silently reverted by the next `tofu apply`.

<div class="mt-8 text-base">

**Checkov hands me fifty findings in CVSS order. Wiz hands me the one path from the internet to the data and the control plane — and the pull request that closes it.**

</div>

<style>
  .slidev-layout li { font-size: 0.82rem; line-height: 1.45; margin-bottom: 0.7rem; }
</style>

<!--
This is the slide to slow down on. Two honest caveats if asked: (1) prioritisation only holds
because the graph knows reachability and identity, not because it has a better CVE feed; (2) this
is the narrative built on the real artefacts — I am describing the edges Wiz would draw over
exactly this project, not replaying a tenant. The remediation-in-code point lands hardest here
because the environment is IaC-managed: fix it in the console and the next apply puts it back.
-->

---
layout: two-cols-header
class: text-sm
---

# What I'd do differently

::left::

### IaC: Pulumi was the genuine alternative

- A real language rather than HCL contortions, and **one program** spanning the infrastructure *and* the Kubernetes manifests
- HCL won on two grounds: the **IaC-scanning ecosystem** is far deeper for it (Checkov, tfsec and Trivy all read HCL natively; Pulumi means leaning on CrossGuard), and it is instantly legible to a reviewer
- I would revisit that the day a pipeline standardised on **policy-as-code** — the scanner argument is most of my case, and at that point it dissolves

### Supply chain: SHA-pin, then sign

- Actions are pinned by **tag** — and `trivy-action@master` is worse than a tag. Tags are mutable: pin every action by **commit SHA**, let Dependabot bump them
- Sign images with **cosign** and enforce **Binary Authorization** on the cluster, so an unsigned or unattested image cannot run even if the registry is compromised
- Emit a **CycloneDX SBOM** per build as an attestation — the next Log4Shell should be a query, not an excavation

::right::

### Secrets: solved on the way in, not in state

- **Done — no credential exists in this repository in any form.** Terraform generates the Mongo password into **Secret Manager**; the Kubernetes Secret is derived from it at deploy time. Secret scanning has nothing to find because there is nothing there
- **Removed deliberately:** an earlier **SOPS + KMS** layer. Once Terraform generated the password, SOPS was encrypting nothing — and a committed encrypted Secret *alongside* the Secret Manager copy is two sources of truth for one credential. A control that no longer protects anything is a liability, not neutral
- **Still open:** the generated password resolves into Terraform **state**, which is why state is versioned, IAM-restricted and public-access-*enforced*. The real fix is it never passing through Terraform at all

<style>
  .slidev-layout li { font-size: 0.72rem; line-height: 1.36; margin-bottom: 0.28rem; }
  .slidev-layout h3 { font-size: 0.88rem; margin: 0.5rem 0 0.3rem; }
</style>

<!--
Tone here is deliberate: these are trade-offs I made knowingly, not things I missed. If pushed on
Pulumi, be concrete — CrossGuard is a policy engine, not a scanner ecosystem, and I was not going
to spend the differentiation budget on the IaC language. The state gap is the one genuine defect
on this slide; name it before they do.
-->

---
layout: two-cols-header
class: text-sm
---

# What I'd add next

::left::

### Runtime: posture is not detection

- Everything I built reasons about **configuration state**. It says the path is exploitable; it cannot say it *is being* exploited
- A **runtime sensor** is what tells me the vulnerable pod actually spawned a shell and reached `169.254.169.254` — the difference between an attack path and an incident
- It also closes the one gap the graph cannot: workload behaviour that never appears in any config

### Prove the controls, don't assert them

- I demonstrate Gatekeeper **rejecting** a privileged pod. I have not walked the whole path end to end
- The missing run: SSH in from the internet → download the backup anonymously → use the pod token to read Secrets → use the VM token for `gcloud compute instances list` — then watch the **log-based alert** fire
- **A detective control that has never fired is a hypothesis.** That simulation is the only real evidence, and it is the first thing I would add with more lab time

::right::

### Also on the list

- **Continuous drift detection** — `plan -detailed-exitcode` on a schedule, alerting on exit 2. Git records *intent*; the cloud is the only record of *fact*. Same argument as the Wiz slide: a CNAPP reads the cloud, not my repository
- **Pin actions by commit SHA, then sign** — cosign + **Binary Authorization**, so an unsigned image cannot run even if the registry is compromised
- **GitOps for the Kubernetes half** — ArgoCD reconciling continuously, rather than push-based CI that converges only when a pipeline happens to run
- **Split the deploy identity** — one service account does `tofu apply` *and* the cluster deploy; two least-privilege ones instead
- **Private control-plane endpoint** behind IAP or a bastion, rather than an authorised admin CIDR

<style>
  .slidev-layout li { font-size: 0.72rem; line-height: 1.36; margin-bottom: 0.28rem; }
  .slidev-layout h3 { font-size: 0.88rem; margin: 0.5rem 0 0.3rem; }
</style>

<!--
The runtime point is the honest limit of the whole exercise: everything here reasons about config,
not behaviour. Say that before they ask — it is also precisely the Wiz Defend argument.
-->

---
layout: default
class: text-sm
---

# Resources

<div class="grid grid-cols-2 gap-10 mt-4">
<div>

### Application

- **OWASP NodeGoat** — the deliberately vulnerable Node.js + MongoDB app, rebuilt with `wizexercise.txt`

### Wiz

- Product documentation and the Wiz blog — **Security Graph**, **attack paths** and **toxic combinations**, **agentless** scanning, and **code-to-cloud** remediation (Dazz)

### Infrastructure as code and scanning

- **OpenTofu** — standard HCL, MPL-2.0
- **Checkov** — IaC misconfiguration scanning
- **Trivy** — container image and IaC config scanning

</div>
<div>

### Google Cloud

- **GKE private clusters** — private nodes, Cloud NAT egress, authorised control-plane networks
- **Cloud Logging + Cloud Monitoring** — log-based metrics and alert policies, the detective control
- **Workload Identity Federation** — keyless GitHub Actions authentication
- **Cloud Audit Logs**, **Artifact Registry**, **Org Policy**

### Kubernetes policy

- **OPA Gatekeeper** / GKE Policy Controller — the admission-time preventative control

</div>
</div>

<div class="mt-8 text-xs opacity-70">

Built with GenAI assistance for scaffolding and review. Every decision on these slides — and every line in the repository — is mine to defend.

</div>

<style>
  .slidev-layout li { font-size: 0.78rem; line-height: 1.4; }
  .slidev-layout h3 { font-size: 0.9rem; margin-top: 0.6rem; margin-bottom: 0.25rem; }
</style>

<!--
Keep this short — thirty seconds. Then straight into the live environment: kubectl, the app,
the data in Mongo, the anonymous bucket listing, and Gatekeeper rejecting the privileged pod.
-->
