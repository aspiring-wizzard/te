---
layout: two-cols-header
---

# Why this costs money before anyone is breached

::left::

### What the business gets

- The product itself — user accounts and financial data
- Change velocity that survives review
- A **known supply chain** — SBOM per build
- Reproducible; RPO ≤ 24 h
- Auditable from day one

::right::

### Where a flaw is caught

| Caught | Costs |
|---|---|
| In the pull request | a review comment |
| At build or admission | a rebuild |
| In production | rotation · IR · customer comms |

A gate that **blocks** gets routed around. A gate that **answers** gets adopted. {.punch}

<!--
The asymmetry IS the argument — no invented figures needed, and none are used
anywhere in this deck.

On the supply chain line: "what are we running, and what is inside it" becomes a
query rather than an excavation. That is the difference between an afternoon and
a fortnight when the next Log4Shell lands.

On the last line: adoption is a design constraint, not a rollout problem. A gate
developers route around — an exception, a bypass flag, a second pipeline — is a
gate that has already failed, however good its findings are.
-->

---
layout: two-cols-header
---

# Disclosure, not downtime

This is not an outage you roll back. {.lede}

::left::

### The exposure

- Backup bucket: `allUsers` **read + list**
- No exploit. No credential. No login.
- GDPR Art. 33 clock — not a backlog item
- Privilege concentrated in **two identities**

::right::

### The cost of an unranked list

- Five tools. Five lists. Five scales.
- **None knows the others exist**
- Analyst-weeks on findings nobody can reach

Mongo requires auth and is firewalled to the GKE ranges · nodes are private · no credentials in the repo {.aside}

<!--
"Disclosure, not downtime" is the line to land. Everything else on the slide
supports it: user data leaving is not recoverable by rolling back a deploy.

The bucket is the sharpest version — same data as the database, a different
control set, and a quieter owner. Enumerate and download; no exploit needed.

Regulation, if it comes up: under GDPR that bucket is a personal-data breach
with a statutory notification clock attached, not a ticket. DORA and NIS2 add
ICT-risk, supply-chain and incident-reporting duties, with management bodies
accountable for the measures. An SBOM stops being paperwork the moment someone
has to answer "which of our systems contained that library".

Blast radius is a commercial measure: how much of the business one bad afternoon
can reach.

The aside matters — say it. Otherwise this reads as a uniformly careless
environment rather than a deliberately weak one.
-->

---
layout: default
---

# Five findings. One attack path.

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

Five routine tickets. Five different owners. One chain. {.punch}

<!--
Start at the LEFT of the graph and say it explicitly: the entry point is
application code, not a firewall rule. The chain starts in the app.

Individually these are a role binding, a version pin, an IAM role, a bucket ACL
and a firewall rule — plus "the app has findings", which every app has. Owned by
application, platform, database, cloud and data teams respectively. Nothing here
would page anyone.

Chained: one path from a line of application code to the cluster, the data AND
the cloud control plane — with a second, credential-free route to the same data
through the bucket.

If asked which to fix first: the ordering only exists once you can see the path.
That is the setup for the Wiz slide — do not pre-empt it here.
-->

---
layout: default
---

# Who catches each one

| # | Finding | Caught by |
|---|---|---|
| — | Application code + dependencies | Semgrep · Trivy fs |
| — | Internet-facing, unauthenticated | ZAP, on the running app |
| 5 | Pod SA bound to `cluster-admin` | Gatekeeper — only for the *next* pod |
| 3 | MongoDB 5.0, EOL, unpatched | lifecycle check — **which I had to add** |
| 2 | VM SA holds `roles/editor` | Checkov · Cloud Audit Logs |
| 4 | Bucket grants `allUsers` | Checkov · log-based alert |
| 1 | SSH `0.0.0.0/0` | Checkov — but no host logs shipped, so nothing watches its *use* |

Every tool owns one column. **None of them owns the chain.** {.punch}

<!--
This is the only reference-density slide in the deck, and it earns its place:
point at the third column rather than reading the table.

AppSec tooling owns the front of the chain. IaC scanning and cloud logging own
the back. Not one of them can see the whole path — which is precisely the gap
the Wiz slide fills.

Row 3 is the one to dwell on. Originally NOTHING here caught it, and the reason
is structural: every scanner in these pipelines looks at either the app image or
the IaC configuration, and the database is apt-installed onto a VM that none of
them inspects. I added a lifecycle check to close it — that story is two slides
away, and the residual gap is on the closing slide.
-->
