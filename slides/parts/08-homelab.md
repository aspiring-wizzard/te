---
layout: default
---

# I'm on the other side of this too

I maintain the pipeline I would be asking developers to adopt. {.lede}

- **Version bumps, every day** — one issue per stale pin, auto-assessed, most auto-merged
- **CI/CD, SBOMs, drift detection** — built, running, and mine to keep running
- **First-party code in there too** — Go services, Python tooling, their own dependency trees
- It is **tedious**. Genuinely, daily, grindingly tedious.

No SAST. No dependency gate. No secret scanning. {.punch}

<!--
This is the slide that says I am not describing developer pain from the outside.

The point is not that I have a homelab. It is that I own the maintenance burden
of exactly the automation I would be asking a customer's teams to adopt — so
when I say "this belongs in the pull request", I know precisely what I am adding
to somebody's Tuesday. Every gate I propose is a gate I have had to live with.

Then the honest half — and say the third bullet deliberately, because it closes
the obvious escape route. The easy dismissal is "it is an infrastructure repo,
there is no application to scan". That is not true: there are self-written
services in there — Go plumbing around Matrix, Python tooling for the version
and triage automation — with real dependency trees of their own. So the gap is
not "nothing to scan". It is "something to scan, and I do not scan it".

Not because I could not build it. Because AppSec is a separate discipline that
does not fall out of infrastructure work — the same lesson as the pipeline that
drifted cloud-ward, except that one I caught in a fortnight and this one has
been true for years.

That is the gap Wiz Code closes, and it is why I believe the argument rather
than just being able to make it. If a panel wants the version-bump detail: a
daily job buckets every stale pin, drafts an upgrade assessment per source, and
auto-merges only the ones a spec has classified as low risk. It works. It still
tells me nothing about whether the code I am shipping is exploitable.
-->
