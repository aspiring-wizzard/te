---
layout: two-cols-header
---

# Business value: what the environment delivers

The application *is* the product. Its code, its dependencies and the cloud it runs in are **one risk surface, and one budget**.

::left::

### What the business gets

- **The product itself** — user accounts, profiles, financial allocations. That data *is* the business.
- **Change velocity that survives review** — every change is a reviewed PR through four pipelines. The controls sit *on the delivery path*, so they scale with it rather than against it.
- **A known supply chain** — image scanned and inventoried (CycloneDX SBOM) before push. *"What are we running?"* becomes a query, not an excavation.
- **Reproducible and recoverable** — the environment is HCL; `plan` diffs every change. Daily `mongodump`, RPO ≤ 24 h.
- **Auditable from day one** — Cloud Audit Logs: admin activity *and* data access.

::right::

### Why the controls sit in the pull request

| Caught | What it costs |
|---|---|
| In the pull request | a commit and a review comment |
| At build or admission | a rebuild — never reaches a customer |
| In production | rotation, incident response, audit trail, customer comms, notification decision |

<div class="mt-4">

A gate that **blocks delivery gets routed around** — an exception, a bypass flag, a second pipeline. A gate that **answers inside the pull request** gets adopted.

**Adoption is a design constraint, not a rollout problem.**

</div>

<style>
  .slidev-layout li { font-size: 0.82rem; line-height: 1.42; margin-bottom: 0.35rem; }
  .slidev-layout table { font-size: 0.78rem; }
</style>

<!--
The asymmetry IS the argument — no invented figures needed. The same finding is cheap in a pull
request and expensive in an incident. On supply chain: the difference between an afternoon and a
fortnight when the next Log4Shell lands.
-->

---
layout: two-cols-header
---

# Business risk: what it carries

The failure mode here is **disclosure, not downtime** — user data leaving, which no deploy reverses.

::left::

### The exposure

- **The copy nobody is watching** — the daily backup lands in a bucket granting `allUsers` read **and** list. No exploit, no credential, no login: enumerate and download.
- **EU regulation makes it a board question** — under **GDPR** that bucket is a personal-data breach with a statutory notification clock (Art. 33), not a backlog item. **DORA** and **NIS2** add ICT-risk, supply-chain and incident-reporting duties — with management bodies accountable.
- **Privilege concentrated in two identities** — one pod service account, one VM service account. Compromise either and the blast radius is the whole cluster, or the whole project.

::right::

### The cost of an unranked list

- Every control produces **its own list on its own scale** — SAST, dependency CVEs, image CVEs, IaC misconfigurations, cloud posture. **None of them knows the others exist.**
- The team triages hundreds of undifferentiated findings in CVSS order while the one genuinely exploitable combination waits its turn.
- The cost is **analyst-weeks spent on findings that cannot be reached** — and a list nobody can finish is a list nobody trusts.

<div class="mt-6 text-sm opacity-70">

**Controls that *are* in place:** MongoDB requires authentication and is firewalled to the GKE node and pod ranges only · GKE nodes are private · no credentials, state or tfvars in the repository.

</div>

<style>
  .slidev-layout li { font-size: 0.82rem; line-height: 1.42; margin-bottom: 0.45rem; }
</style>

<!--
Blast radius is a COMMERCIAL measure: how much of the business one bad afternoon can reach.
An SBOM stops being paperwork the moment someone has to answer "which of our systems contained
that library". The environment is weak by design, but weak in the ways real estates are.
-->

---
layout: default
---

# Security outcomes: five findings, one attack path

Five planted weaknesses — plus the application they exist around. **The chain starts in the code, not in the cloud posture.**

```mermaid
flowchart LR
  NET([Internet]) -->|"Cloud LB"| APP["NodeGoat pod<br/>vulnerable code"]
  APP -->|"5 · cluster-admin"| K8S["Whole cluster<br/>every Secret"]
  K8S -->|"mongo-creds"| VM["Mongo VM<br/>3 · 5.0 EOL<br/>user data"]
  VM -->|"2 · roles/editor"| CP["GCP<br/>control plane"]

  NET -.->|"1 · SSH 0/0"| VM
  VM -->|"backup"| BKT["Bucket<br/>4 · allUsers<br/>anonymous download"]

  classDef entry fill:#fee2e2,stroke:#dc2626,stroke-width:2.5px,color:#7f1d1d
  classDef weak fill:#fee2e2,stroke:#dc2626,stroke-width:1px,color:#7f1d1d
  classDef crown fill:#fef3c7,stroke:#d97706,stroke-width:1px,color:#78350f
  class APP entry
  class VM weak
  class K8S,CP,BKT crown
```

<style>
  /* Let the SVG scale itself to the slide rather than hand-tuning a `scale:`
     magic number — a wide flowchart otherwise renders at its natural width and
     is silently clipped at the slide edge. */
  .slidev-layout .mermaid { display: flex; justify-content: center; }
  .slidev-layout .mermaid svg { width: 100%; max-width: 100%; height: auto; }
</style>

<div class="mt-6 text-sm">

**Individually:** five routine tickets — a role binding, a version pin, an IAM role, a bucket ACL, a firewall rule — plus *"the app has findings"*, which every app has. **Five different owners.** None alarming on its own.

**Chained:** one exploitable path from a line of application code to the cluster, the data *and* the cloud control plane — with a second, credential-free route to the same data via the bucket.

</div>

<!--
Land this slowly, and start at the LEFT of the graph — the entry point is application code, not a
firewall rule. If asked which finding to fix first: the ordering only exists once you can see the
path, which is exactly the setup for the Wiz slide.
-->

---
layout: default
---

# The five findings, and who owns each

<div class="text-xs">

| # | Link in the chain | Role | Caught by |
|---|---|---|---|
| — | **Application code + dependencies** — injection, XSS and SSRF-class flaws, plus known-vulnerable npm packages | **Entry point** — the way in is the app, not the perimeter | Semgrep (SAST) · Trivy fs (SCA) |
| — | **Internet-facing** behind the Cloud load balancer | **Reachability** — what makes the flaw exploitable rather than theoretical | ZAP (DAST), on the running app |
| 5 | App pod service account bound to **`cluster-admin`** | **Cluster takeover** — every Secret in every namespace, `mongo-credentials` included | Gatekeeper — but only for the *next* workload |
| 3 | **MongoDB 5.0 (EOL Oct 2024)**, unpatched, on the VM that credential opens | **Known CVEs** on the data tier, no vendor fixes coming | VM patching — and the version is **pinned by the app's driver**, so patching alone cannot fix it |
| 2 | That VM's service account holds **`roles/editor`** | **Privilege escalation** — host → GCP control plane | Checkov pre-`apply` · Cloud Audit Logs post-deploy |
| 4 | Backup bucket grants `allUsers` read **and** list | **Data exposure** — no exploit, no credential, no login | Checkov pre-`apply` · log-based metric + alert on anonymous reads |
| 1 | SSH `0.0.0.0/0` to a public-IP VM | **Second, parallel entry point** — still real, no longer the headline | Checkov pre-`apply` — nothing watches its *use* at runtime |

</div>

<div class="text-xs opacity-70 mt-4">

**On #3:** authentication **is** enforced and Mongo **is** firewalled to the GKE node and pod ranges only — both required controls. The exposure is the unpatched version, not the access path. That firewall is also *why* the chain runs through the application: from the internet, the pod is the only route to that credential.

</div>

<style>
  .slidev-layout table { font-size: 0.62rem; line-height: 1.3; }
  .slidev-layout th, .slidev-layout td { padding: 0.18rem 0.4rem; vertical-align: top; }
</style>

<!--
Every scanner in the market produces this table. The table is not the risk — the ORDERING is.
Point at the fourth column: AppSec tooling owns the front of the chain, IaC scanning and cloud
logging the back, and not one of them sees the whole path.
-->


<!--
Land this slowly, and start at the left of the graph — the entry point is application code, not a
firewall rule. Every scanner in the market produces this table; the table is not the risk, the
ordering is. Point at the fourth column: AppSec tooling owns the front of the chain, IaC scanning
and cloud logging the back, and not one of them can see the whole path. If asked which finding to
fix first, the honest answer is that the ordering only exists once you can see the path — which is
exactly the setup for the Wiz slide.
-->
