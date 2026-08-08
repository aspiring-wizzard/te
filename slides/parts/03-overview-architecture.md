---
layout: default
class: text-sm
---

# Overview

What the exercise asked for:

- **A deliberately-vulnerable two-tier app** — containerised workload on Kubernetes in a private subnet, MongoDB on a VM in a public subnet, daily backups to a publicly-readable bucket.
- **Everything as code** — the environment deployed as IaC, the application built and shipped by pipeline. No click-ops.
- **Cloud-native security** — control-plane audit logging, plus at least one preventative and one detective control from CSP-native tooling.
- **Security in the pipeline** — IaC and container image scanned *before* deployment (the Dev(Sec)Ops bonus).
- **Prove it live** — `kubectl` against the cluster, `wizexercise.txt` inside the running container, real data in the database.

<div class="mt-8 text-sm opacity-70">
The weaknesses are <b>requirements</b>, not accidents — five of them, chosen so they compose into a single attack path.
</div>

---
layout: default
---

# What I built

```mermaid {scale: 0.72}
flowchart LR
  net(["Internet"])
  lb["Cloud LB"]

  subgraph priv["GKE private · 10.0.2.0/24"]
    direction TB
    ing["Ingress<br/>gce"]
    pods["NodeGoat ×2<br/>:4000"]
  end

  subgraph pub["public · 10.0.1.0/24"]
    vm["MongoDB 5.0 EOL<br/>Ubuntu 20.04"]
  end

  gcs[("Backups<br/>public read")]

  net --> lb --> ing --> pods
  pods -->|"27017 · GKE only"| vm
  vm -->|"daily"| gcs
  net -.->|"SSH 0/0"| vm
  net -.->|"anon read"| gcs

  classDef weak stroke:#e11d48,stroke-width:2px
  class vm,gcs weak
```

<div class="grid grid-cols-3 gap-6 mt-4 text-sm">
  <div><b>Infrastructure</b><br/>OpenTofu (standard HCL) — VPC, private GKE, Mongo VM, bucket, IAM, controls</div>
  <div><b>Application</b><br/>OWASP NodeGoat, rebuilt with <code>wizexercise.txt</code>, served from Artifact Registry</div>
  <div><b>Delivery</b><br/>Two GitHub Actions pipelines, each gated by a scan before anything deploys</div>
</div>
