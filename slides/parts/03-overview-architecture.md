---
layout: default
---

# What the exercise asked for

- A **deliberately vulnerable** two-tier app on Kubernetes
- **Everything as code** — no click-ops
- **Cloud-native controls** — one preventative, one detective
- **Security in the pipeline** — scan before deploy
- **Prove it live** — `kubectl`, the file in the container, real data

The weaknesses are **requirements**, not accidents. {.punch}

<!--
- all of this is required. the last line is the one I chose.

- I could have scattered five weaknesses around and ticked the box. didn't. picked five that CHAIN.
- on its own each is an afternoon's ticket: role binding · version pin · bucket ACL
- in the right order: internet → app → cluster → data → cloud control plane
- that's what the next ten minutes are about

#### If asked

- **why NodeGoat, not the sample todo app?** — *a clean app gives the scanners nothing to find. a pipeline reporting "all clear" proves nothing. I wanted real findings.*
-->

---
layout: default
---

# What I built

```mermaid
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

OpenTofu · OWASP NodeGoat from Artifact Registry · four GitHub Actions pipelines {.aside}

<!--
- solid arrows = how a user reaches it internet → load balancer → ingress → the pods → Mongo on 27017
- dotted = the two ways in nobody intended SSH from anywhere · anonymous read on the backups

- red outline = deliberately weak, only two things here

- and be clear about what ISN'T weak: Mongo firewalled to the GKE ranges only · auth IS required · nodes are private · no credentials in the repo
- otherwise this reads as uniformly careless. it's weak in five specific places, on purpose.

#### If asked

- **why a VM for the database, not a managed service?** — *the exercise asked for it, and it's the realistic shape — the VM that predates the container platform. it also turns out to be the part nothing scans, which comes up later.*
-->
