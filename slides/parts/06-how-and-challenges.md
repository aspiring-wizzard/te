---
layout: default
---

# How I built it: the pipeline is the control plane

Four pipelines, one rule — **every control sits at the earliest stage where the fix is still cheap**.

<div class="grid grid-cols-4 gap-5 mt-8">
  <div class="sdlc">
    <b>1 · Develop</b> <code>appsec.yml</code>
    <ul>
      <li><b>gitleaks</b> — secrets, in the working tree <i>and</i> the history</li>
      <li><b>Semgrep</b> — SAST; OWASP Top Ten + JavaScript rulesets</li>
      <li><b>Trivy fs</b> — SCA; vulnerable dependencies, at source, in the PR</li>
    </ul>
  </div>
  <div class="sdlc">
    <b>2 · Build</b> <code>app.yml · iac.yml</code>
    <ul>
      <li><b>Trivy image</b> — the gate, <i>before</i> the registry push</li>
      <li><b>CycloneDX SBOM</b> — an inventory of what actually shipped</li>
      <li><b>Checkov + Trivy config</b> — IaC, before any <code>apply</code></li>
    </ul>
  </div>
  <div class="sdlc">
    <b>3 · Deploy</b> <code>GitHub · k8s/</code>
    <ul>
      <li><b>Pull-request flow</b> — every change lands through a reviewed PR</li>
      <li><b>Human-gated apply</b> — <code>iac.yml</code> declares <code>environment: lab</code></li>
      <li><b>Gatekeeper</b> — admission control rejects a new privileged pod</li>
    </ul>
  </div>
  <div class="sdlc">
    <b>4 · Run</b> <code>dast.yml · security.tf</code>
    <ul>
      <li><b>OWASP ZAP baseline</b> — DAST against the deployed application</li>
      <li><b>Log-based metric + alert</b> — anonymous reads of the backup bucket</li>
      <li><b>Cloud Audit Logs</b> — admin activity <i>and</i> data access</li>
    </ul>
  </div>
</div>

<div class="mt-8 text-xs opacity-70">

**Stated rather than claimed:** enforced branch protection, required status checks and environment approvals are **not available on a free private repository** — they need a public or Pro repo. The workflows declare them; only the *enforcement* is licence-gated. Same for SARIF upload to code scanning, which is gated in the workflow on the repo being public.

</div>

<style>
  .slidev-layout .sdlc { border-top: 2px solid rgba(100, 116, 139, 0.45); padding-top: 0.4rem; }
  .slidev-layout .sdlc > code { font-size: 0.62rem; opacity: 0.7; }
  .slidev-layout .sdlc ul { list-style: none; padding: 0; margin: 0.4rem 0 0; font-size: 0.72rem; line-height: 1.4; }
  .slidev-layout .sdlc ul li { margin-bottom: 0.45rem; }
</style>

<!--
Lead with the pipeline, not the tooling — this is where application security actually lives.
Ordering is the point: the image scan runs BEFORE the push, so a failing image never reaches the
registry or the cluster. That is exactly where Wiz Code slots in.

On the footnote: say it before they ask. Knowing where your platform's licence boundary sits is
part of the job; claiming a control you do not have is the thing that loses the room.
-->

---
layout: two-cols-header
class: text-sm
---

# The choices underneath

::left::

### SAST ≠ SCA ≠ DAST

Three different questions. Conflating them is the common mistake:

- **Trivy image** finds a vulnerable *package* — and says nothing about NodeGoat's injection flaws.
- **Semgrep** finds the vulnerable *code* — and says nothing about whether anyone can reach it.
- **OWASP ZAP** proves it is *reachable on the running app* — and knows nothing about the dependency tree.

**Cost rises with the stage.** A secret gitleaks catches pre-merge costs minutes; the same secret found in production costs a rotation, an incident and an audit trail.

::right::

### Build choices

- **OpenTofu, standard HCL** — same `hashicorp/google` provider, `.tf` files unchanged; scanners read the *files*, not the binary. MPL-2.0 sidesteps the BSL licence question.
- **OWASP NodeGoat** — deliberately vulnerable, so every scan returns **genuine findings**. A pipeline reporting "all clear" demonstrates nothing.
- **`node:16-bullseye`, deliberately EOL** — real OS and dependency CVEs to find.
- **`COPY wizexercise.txt`** — its own layer; proven in the image at build, then in the running pod.

### Secrets and state

- **No secret in the repository** — Terraform generates the Mongo password into **Secret Manager**; the Kubernetes Secret is derived from it at deploy time.
- **No static key in CI** — the workflows authenticate by **Workload Identity Federation**. *(Wired, but the cloud pipelines are not enabled in this sandbox.)*
- **Remote GCS state backend** — versioned, IAM-restricted, public-access-enforced; state never rests on an ephemeral runner.

<style>
  .slidev-layout ul  { font-size: 0.72rem; line-height: 1.38; }
  .slidev-layout li  { margin-bottom: 0.3rem; }
  .slidev-layout p   { font-size: 0.72rem; line-height: 1.38; margin-bottom: 0.4rem; }
  .slidev-layout h3  { font-size: 0.92rem; margin: 0.5rem 0 0.35rem; }
</style>

<!--
The line to land: image scanning finds vulnerable PACKAGES, Semgrep finds vulnerable CODE,
ZAP proves it is REACHABLE. Three questions, and only the last is evidence of exploitability.

ZAP is workflow_dispatch against the load-balancer IP, because DAST needs a live target that
only exists once the app pipeline has deployed. If asked why nothing blocks: soft_fail and
exit-code 0 are deliberate in a knowingly vulnerable lab, and flip to fail-on-CRITICAL in
production. Say it before they ask.
-->

---
layout: default
---

# Challenges: designing the pipeline

- **The pipeline drifted cloud-ward — the correction I am most glad I made.** The first iteration scanned infrastructure and images thoroughly and never once analysed the application source: a strong *cloud*-security pipeline wearing an AppSec label.
  <br>→ Added **gitleaks**, **Semgrep** SAST, source-level **SCA**, a **CycloneDX SBOM** and **ZAP** DAST. You secure the layer you are most fluent in, so AppSec coverage has to be **designed deliberately** — it does not fall out of a container scan.

- **Every scanner fires — by design.** In a deliberately vulnerable environment, fail-on-finding is a permanently red pipeline.
  <br>→ Checkov `soft_fail`, Trivy `exit-code: 0`: the pipeline **publishes** findings rather than blocking on them. In production both flip to fail-on-CRITICAL — worth saying out loud, or it reads as a weak gate rather than a deliberate one.

- **The weaknesses have to survive the demo.** A preventative control that retro-fixes the planted misconfigurations destroys the detective story.
  <br>→ I split the two: **detective** controls flag what already exists — a log-based metric and alert on anonymous reads of the bucket; **preventative** controls block a *new* bad action — Gatekeeper rejecting a new privileged pod, live.

<style>
  .slidev-layout ul { font-size: 0.8rem; line-height: 1.45; }
  .slidev-layout ul li { margin-bottom: 0.9rem; }
</style>

<!--
Honest framing: none of these were blockers — all were design decisions with a trade-off.

Lead with the drift one and do not soften it. The first pipeline was a cloud-security pipeline
with an AppSec label on it, and I only caught it by going looking for what it did NOT scan.
For an AppSec panel that is the point: coverage is designed, never inherited.
-->

---
layout: default
---

# Challenges: the environment I actually had

- **The sandbox is project-scoped — probed, not assumed.** The `securitycenter` API is *enabled*, but the account holds no organisation permissions: `scc findings list` and `org-policies list` both return `PERMISSION_DENIED`.
  <br>→ I built the detective control where I **do** have authority — a log-based metric and Cloud Monitoring alert on anonymous access to the bucket, over Cloud Audit Logs — and the preventative control as **Gatekeeper**; `enable_org_policy` defaults to **false**. A premium tier you cannot enable is not a control.

- **Private GKE nodes have no public IPs** — no egress means no image pulls; a fully private endpoint means no `kubectl`.
  <br>→ **Cloud NAT** for egress, and a public control-plane endpoint restricted by `master_authorized_networks` to a single admin CIDR. That restriction is deliberate — SSH is the ingress left open to the world by design, not this.

- **Lab access is a 14-day clock that starts on redemption.**
  <br>→ Everything built and validated locally first — `tofu validate` clean, image built, `wizexercise.txt` proven, all four workflows written — so lab time is spent demonstrating, not debugging.

<style>
  .slidev-layout ul { font-size: 0.8rem; line-height: 1.45; }
  .slidev-layout ul li { margin-bottom: 0.9rem; }
</style>

<!--
If pushed on the absent SCC and org-policy access, the Gatekeeper constraint is arguably the better
Kubernetes-security demo anyway — you watch the API server reject the pod in real time. The probe
output is the evidence: the API is on, the permission is not.
-->
