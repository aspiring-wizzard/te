---
layout: default
---

# What broke, and what it taught me

Four things went wrong. These are the three worth your time. {.lede}

- **The pipeline drifted cloud-ward** — I built the wrong kind of security
- **An EOL database I could not patch** — because the *app* pinned it
- **A control that ate the workload** — security is not free

One was the app's. Two were mine. {.punch}

<!--
— four things went wrong. three are worth your time.

— and I want to be exact about the last line, because it's easy to dress
  these up as trade-offs and they weren't:
    the drift was MINE — built the wrong kind of security
    Gatekeeper was MINE — never checked the controller was installed
    the EOL database was the APP's — nobody decided that

— these aren't confessions. they're the parts where I actually learned
  something, and all three shapes will be familiar to you.

── IF ASKED ──
what was the fourth?
  → arm64 image on amd64 nodes. it pulled perfectly and then wouldn't
    execute — "exec format error", which reads like a corrupt image rather
    than a wrong-architecture one. CI would never have caught it; the
    runners are amd64. only local builds were affected.
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
This is the correction I'm most glad I made.

My first pass at this pipeline was, I thought, thorough. Checkov and Trivy
across the Terraform. Image scanning before the registry push. Findings going
into code scanning. If you'd asked me at the time, I'd have told you I had a
security pipeline.

Then I went looking for what it did not scan. The answer was the application.
Not one job touched the source. No SAST, no dependency scanning at source, no
secret scanning. I'd built a cloud-security pipeline and put an AppSec label
on it.

The part I find uncomfortable is why. It wasn't laziness, and it wasn't that I
don't know what SAST is. It was fluency. I'm strongest on infrastructure, so
the pipeline I built by instinct secured infrastructure. I covered what I could
see.

Which is why I don't think you get application security by hiring good platform
people. It has to be designed on purpose, and somebody has to go looking for
the gap deliberately.

It's also the honest reason this conversation lands with platform teams. They
are not refusing to do AppSec. They are covering what they can see.

── IF ASKED ──
how did you catch it?
  → I went back through the exercise brief and asked which requirement each
    job satisfied. Nothing mapped to the AppSec bonus. The gap was in what I
    hadn't written, so no test was ever going to find it.
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
— and hold that thought, because there's a second half to this one:
  none of my scanners noticed any of it
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
Now the part I should own, because it's the obvious question: surely that's
trivial to catch?

It is, once you notice. But look at where my scanners were pointed. Trivy
scans the application container. Trivy fs scans the npm tree. Checkov reads
Terraform for misconfiguration — and there's no Checkov rule that says "this
string is an unsupported version". ZAP is black-box HTTP against the app. The
SBOM I generate stops at the container's edge. Every one of those tools was
pointed at something real. Not one of them was pointed at the database.

The VM has no SBOM at all. That's the actual gap, and it's a shape I think is
very common — the machine that predates the container platform, still running,
still nobody's scanning surface.

The other half is the one I'd defend hardest. End of life is a lifecycle fact,
not a vulnerability. A CVE feed can come back completely green on software
that will never receive another fix, because there's no vendor left to issue
the advisory. So catching it needs a lifecycle dataset, not a vulnerability
database. I wired mine to endoflife.date, and it flags all three: the
database, the operating system, and the Node base image.

And then the limit, which matters more than the fix. It reads pins out of
source code. It sees what I declared. It cannot see what a startup script
actually pulled onto that host, and it cannot see drift between the two.
Closing that needs an SBOM of the machine itself.

── IF ASKED ──
can I see it?
  → yes — `just demo-eol`, takes about two seconds.
why not just use Trivy on the VM?
  → that's exactly the right instinct, and it's the honest next step. Trivy
    can scan a disk image. I didn't get there. Also worth knowing: mongodb-org
    comes from MongoDB's own apt repo rather than Ubuntu's security tracker,
    so CVE matching is weaker for it than for distro packages — which is why
    the lifecycle signal is the more dependable one here.
-->

<!--
I put MongoDB 6.0 in first. The app connected to it perfectly, and then
failed every single read and write.

That error is the reason. NodeGoat ships a MongoDB driver from 2016, and that
driver speaks a wire protocol called OP_QUERY. MongoDB removed OP_QUERY in
5.1. So the newest database this application can talk to at all is 5.0 — and
5.0 went end-of-life in October 2024.

So I'm running an unsupported datastore. Not because anyone decided to, and
not because nobody got round to upgrading it. Because a dependency nobody has
touched in nearly ten years pinned it there.

That's the bit I'd want you to take from this. "Upgrade the database" sounds
like a platform ticket, and here the platform genuinely cannot act. Patching
does not fix this. The only fix is upgrading the application's driver — which
is an application change, with application testing and an application owner.

It's an AppSec problem wearing an infrastructure costume. And it's how legacy
risk actually arrives: not by decision, by accretion.

── IF ASKED ──
why Ubuntu 20.04 rather than something newer?
  → the OS choice wasn't independent either. MongoDB 5.0 only publishes
    server packages for focal. The jammy suite exists and returns HTTP 200,
    but ships just the shell and tools — a reachable repository isn't a
    supported one. The app's dependency tree reached all the way down to the
    operating system.
couldn't you have used a different app?
  → yes, and then the exercise demonstrates nothing. The constraint is the
    finding.
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
This one is two failures, and the second is the interesting one.

The first is straightforward and it was mine. I'd written the Gatekeeper
constraint, committed it, and ticked the requirement off — because the file
existed. Gatekeeper itself was never installed. So if I'd run this demo as
planned, I'd have applied a privileged pod in front of you and watched it be
admitted. The control would have proven the exact opposite of its point.

A policy manifest with no admission controller behind it is a document, not a
control. That's the same failure mode as a policy-as-code repository with no
webhook wired up, and it's a genuinely common finding.

Then I installed it, and the application went Pending. Gatekeeper ships
high-availability defaults — three controller replicas plus audit, roughly
400 millicores and two gigs. This cluster is two e2-mediums, sized down to a
two-hundred-dollar sandbox cap. That was enough to push both nodes past ninety
percent CPU requests and evict NodeGoat.

So the security control evicted the workload it existed to protect.

That's the part worth generalising. Controls are not free, and admission
controllers land on the same nodes as the thing they're protecting. "Turn on
the policy engine" is a capacity decision as much as a security one — and I
think that's a large part of why security tooling gets quietly switched off in
the real world. In production you size the cluster for the controls. In a
capped sandbox, you right-size the control.

── IF ASKED ──
how did you fix it?
  → scaled the controller to a single replica. Ample for one constraint, and
    the recipe does it automatically now so a rebuild can't repeat it.
why not just give the cluster more nodes?
  → cost cap. And I'd rather the constraint stayed visible — it's the honest
    version of a trade-off every platform team makes.
-->
