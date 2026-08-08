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

A deliberately-vulnerable two-tier application on GCP — built, automated, and instrumented so that five findings tell one story.

<div class="mt-10 text-lg">
  <b>{{PRESENTER}}</b> · Principal Solutions Engineer, Application Security
</div>

<div class="abs-bl m-6 text-left text-sm opacity-60">
  OpenTofu · GKE · MongoDB · GitHub Actions · GCP <code>europe-west1</code>
</div>


---

# Agenda

1. **Overview & what I built** — the GCP reference architecture
2. **Business value & risk** — what the environment delivers, and what it costs
3. **How I built it** — the pipeline as the control plane: SAST, SCA, secrets, SBOM, DAST
4. **Challenges** — what bit, and what I changed
5. **Security outcomes** — from vulnerable code to the cloud control plane: one attack path
6. **Where Wiz changes the outcome** — context and prioritisation
7. **What I'd do differently**
8. **Live walkthrough** — `kubectl`, the app, the data, the controls firing

<div class="mt-10 text-sm opacity-70">
~15 minutes on the slides, then the live environment — 25 minutes of Q&A after.
</div>
