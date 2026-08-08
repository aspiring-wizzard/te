---
theme: default
title: "Wiz Technical Exercise"
highlighter: shiki
lineNumbers: false
drawings:
  persist: false
transition: slide-left
mdc: true
class: text-center
---

# Wiz Technical Exercise

Five findings. One attack path. {.lede .mx-auto}

**__PRESENTER__** · Principal Solutions Engineer, Application Security {.mt-12.opacity-70}

OpenTofu · GKE · MongoDB · GitHub Actions · GCP `europe-west1` {.mt-2.text-sm.opacity-50}

<!--
- thanks for the time. ~15 min on slides, then we go to the live environment
- that's the substance, this is scaffolding

- what I built: deliberately vulnerable two-tier app on GCP, all as code
- five planted weaknesses. the interesting part isn't the five, it's that they chain
-->

---

# What I'll cover

- **What I built** — and what is deliberately wrong with it
- **The business case** — why this costs money before anyone is breached
- **One attack path** — five findings, five owners, one chain
- **How it is built** — the pipeline as the control plane
- **What broke** — the three failures worth telling you about
- **Where Wiz changes the outcome**

~15 minutes here, then the live environment. {.aside}

<!--
- quick map so you know where we're going

- front half: what it is, and why it costs money before anyone is breached
- middle: one attack path, and how the thing is built
- then what broke — three failures. I'll be specific about which were mine
- close: where Wiz changes the outcome. then live.

- interrupt whenever. I'd rather go deep on one thing than finish all of it.
-->
