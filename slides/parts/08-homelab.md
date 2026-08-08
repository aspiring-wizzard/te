---
layout: default
---

# I'm on the other side of this too

I maintain the pipeline I would be asking developers to adopt. {.lede}

- **Version bumps, every day** — one issue per stale pin, auto-assessed, most auto-merged
- **CI/CD, SBOMs, drift detection** — built, running, and mine to keep running
- It is **tedious**. Genuinely, daily, grindingly tedious.

And there is still **no AppSec pipeline in it**. {.punch}

<!--
This is the slide that says I am not describing developer pain from the outside.

The point is not that I have a homelab. It is that I own the maintenance burden
of exactly the automation I would be asking a customer's teams to adopt — so
when I say "this belongs in the pull request", I know precisely what I am adding
to somebody's Tuesday. Every gate I propose is a gate I have had to live with.

Then the honest half. All that automation, and there is no SAST, no dependency
gate, no secret scanning worth the name. Not because I could not build it —
because it is a separate discipline that does not fall out of infrastructure
work. Same lesson as the pipeline that drifted cloud-ward two slides ago, except
that one I caught in a fortnight and this one has been true for years.

That is the gap Wiz Code closes, and it is why I believe the argument rather
than just being able to make it. If a panel wants the version-bump detail: a
daily job buckets every stale pin, drafts an upgrade assessment per source, and
auto-merges only the ones a spec has classified as low risk. It works. It still
tells me nothing about whether the code I am shipping is exploitable.
-->
