---
layout: default
---

# What broke, and what it taught me

Four things went wrong. These are the three worth your time. {.lede}

- **The pipeline drifted cloud-ward** — I built the wrong kind of security
- **An EOL database I could not patch** — because the *app* pinned it
- **A control that ate the workload** — security is not free

None of these were blockers. All of them were decisions. {.punch}

<!--
Framing matters here: these are not confessions, they are the parts of the build
where something was actually learned. A panel of engineers has debugged all
three shapes of problem and will recognise them.

The fourth, if anyone asks: an arm64 image on amd64 nodes. It pulled perfectly
and then would not execute — "exec format error" reads like a corrupt image
rather than a wrong-architecture one. CI never would have caught it; CI runners
are amd64. Only local builds were affected.
-->

---
layout: default
---

# The pipeline drifted cloud-ward

My first pipeline scanned infrastructure and images thoroughly.

It never once looked at the application source. {.punch}

- A **cloud-security** pipeline wearing an AppSec label
- Found by going looking for what it did *not* scan
- Added gitleaks, Semgrep, source-level SCA, SBOM, ZAP

You secure the layer you are most fluent in. {.punch}

<!--
This is the correction I am most glad I made, and the one most worth telling an
AppSec panel — because the failure is not laziness, it is fluency. I am strongest
on infrastructure, so the pipeline I built by instinct secured infrastructure.

The uncomfortable generalisation: AppSec coverage has to be DESIGNED. It does not
fall out of a container scan, and it does not fall out of hiring good
infrastructure people. That is a programme-design point, not a tooling point.

It is also the honest reason a CNAPP conversation lands with platform teams: they
are not refusing to do AppSec, they are covering what they can see.
-->

---
layout: default
---

# An EOL database I could not patch

MongoDB 6.0 → the app connected, then failed every read and write. {.lede}

```
MongoError: Unsupported OP_QUERY command: find   (code 352)
```

- NodeGoat ships a **2016-era driver**; OP_QUERY was removed in 5.1
- So the datastore is pinned at **5.0 — EOL since Oct 2024**
- Nobody chose to run EOL software. **A dependency chose it.**

Patching cannot fix this. Only an application change can. {.punch}

<!--
[continues on the next slide — the second beat is that nothing caught it]
-->

---
layout: default
---

# And nothing in my pipeline caught it

Every scanner here reads the app image or the IaC config. The database is `apt-get install`-ed onto a VM that none of them inspects. {.lede}

- **End of life is not a CVE** — clean today, unfixable tomorrow
- So I added a **lifecycle check**: pins vs. vendor support dates
- It catches all three — Mongo 5.0, Ubuntu 20.04, Node 16

It sees what is **declared**. Not what is **installed**. {.punch}

<!--
This is the honest half of the previous slide, and it is worth volunteering
because it is the obvious question: surely that is trivial to catch?

It is — once you notice. The reason it went unnoticed is structural, not lazy.
Trivy scans the application container. Trivy fs scans the npm tree. Checkov
reads Terraform for MISCONFIGURATION, and no rule says "this string is an
unsupported version". ZAP is black-box HTTP. The CycloneDX SBOM stops at the
container's edge — so the VM has no SBOM at all. Every tool was pointed at
something real; none of them was pointed at the datastore.

The second point is the one I would defend hardest: EOL is a LIFECYCLE fact, not
a vulnerability. A vulnerability feed can be entirely green on software that
will never receive another fix. Catching it needs a lifecycle dataset —
endoflife.date here — not a CVE database. Worth adding: mongodb-org comes from
MongoDB's own apt repo rather than Ubuntu's security tracker, so CVE matching is
weaker for it than for distro packages. The lifecycle signal is the more
dependable one.

Then the limit, and it is the hand-off to agentless: the check reads pins out of
source. It cannot see a package a startup script pulled in transitively, or
drift between the pin and the running host. Closing that means an SBOM of the VM
itself — disk scanning, no agent on a host I already do not trust.

Demo it live if there is time: `just demo-eol`.
-->

<!--
This is the best AppSec story in the build, because it inverts the usual framing.
"Upgrade your database" is a platform ticket. Here the platform CANNOT act: the
version is pinned by an application dependency nobody has touched since 2016.

That is how legacy risk actually arrives — not by decision, by accretion. And it
is why "just patch it" is not something a platform team can unilaterally execute.

An AppSec problem wearing an infrastructure costume. If they push: the fix is
upgrading the driver, which is an application change, with application testing
and an application owner.

Coupling detail if asked: MongoDB 5.0 publishes server packages for focal only —
the jammy suite exists and returns HTTP 200 but ships just the shell and tools.
A reachable repository is not a supported one. The OS choice was never
independent of the app's dependency tree.
-->

---
layout: default
---

# A control that ate the workload

The Gatekeeper manifest existed. Gatekeeper did not. {.lede}

- The privileged pod would have been **admitted** — proving the opposite
- Installing it at stock HA size pushed both nodes past **90% CPU**
- The application went `Pending`

The security control evicted the workload it was there to protect. {.punch}

<!--
Two failures, and the second is the interesting one.

First: a policy manifest with no admission controller behind it is a document,
not a control. I had treated the requirement as met because the FILE existed.
That is the same failure mode as a policy-as-code repo with no webhook wired up,
and it is a real and common finding.

Second: Gatekeeper ships HA defaults — three controller replicas plus audit,
about 400m CPU and 2Gi. On a cluster sized down to a $200 sandbox cap that was
enough to evict NodeGoat.

The generalisation is the useful part: controls are not free, and admission
controllers land on the same nodes as the workload. "Turn on the policy engine"
is a capacity decision as well as a security one — which is a large part of why
security tooling gets disabled in the real world. In production you size the
cluster for the controls; in a capped sandbox you right-size the control.
-->
