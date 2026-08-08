---
layout: default
---

# I'm on the other side of this too

I maintain the pipeline I would be asking developers to adopt. {.lede}

- **Version bumps, every day** — one issue per stale pin, auto-assessed, low-risk ones merged automatically
- **CI/CD, SBOMs, drift detection** — built, running, and mine to keep running
- **First-party code in there too** — Go services, Python tooling, their own dependency trees
- It is **tedious**. Genuinely, daily, grindingly tedious.

No SAST. No dependency gate. No secret scanning. {.punch}

<!--
I want to step outside the exercise for a minute, because I think this matters
more than anything else I've shown you.

I run a self-hosted estate at home. All of it is code, all of it deploys
through CI. Part of that is version automation: every day it checks every
pinned dependency, opens an issue for each one that's gone stale, drafts an
upgrade assessment, and auto-merges the ones it can classify as low risk.

I built that, and I maintain it. And I'll be honest about what that's like —
it is tedious. Genuinely, daily, grindingly tedious.

Which is the point. When I sit with a platform team and say "this control
belongs in the pull request", I know exactly what I'm adding to somebody's
Tuesday. Every gate I'd propose is a gate I've had to live with myself.

Now the uncomfortable half. There is first-party code in there — Go services
doing Matrix plumbing, Python tooling running the version and triage
automation, each with a dependency tree of its own. So this isn't a case of
there being nothing to scan.

There's no SAST in it. No dependency gate. No secret scanning worth the name.

Not because I couldn't build it. Because application security is a different
discipline, and it does not fall out of infrastructure work. Which is the same
lesson as the pipeline that drifted cloud-ward — except I caught that one in a
fortnight, and this one has been true for years.

That's the gap. And it's why I believe this argument rather than just being
able to make it.

#### If asked

- **so why haven't you added SAST?** — *honestly, the same reason your customers haven't. It's a separate thing to stand up, own and tune, and there is always something with a deadline in front of it. That is the adoption problem, and it's exactly why the gate has to answer inside the pull request rather than being another console somebody has to remember to open.*
- **what's in the estate?** — *self-hosted git and CI, monitoring and alerting, backups with restore drills, home automation. The version automation is the piece most relevant here.*
-->
