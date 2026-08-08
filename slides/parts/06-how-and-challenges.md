---
layout: two-cols-header
---

# The pipeline is the control plane

Every control sits at the earliest stage where the fix is still cheap. {.lede}

::left::

### 1 · Develop

gitleaks · Semgrep · Trivy fs

### 2 · Build

Trivy image · CycloneDX SBOM · Checkov · **EOL check**

::right::

### 3 · Deploy

Pull-request flow · Gatekeeper admission

### 4 · Run

ZAP · log-based alert · Cloud Audit Logs

Branch protection and environment approvals need a public or Pro repo — declared, not enforced {.aside}

<!--
Ordering is the point, not the tool list. The image scan runs BEFORE the push,
so a failing image never reaches the registry or the cluster. That is exactly
where Wiz Code slots in: same findings, in the pull request, with cloud context
attached.

Say the aside before anyone asks. Claiming a control you cannot demonstrate is
what loses a room; knowing where your platform's licence boundary sits is part
of the job.

If asked why nothing blocks: soft_fail and exit-code 0 are deliberate in a
knowingly vulnerable lab — the findings are the deliverable. Both flip to
fail-on-CRITICAL in production.
-->

---
layout: default
---

# SAST ≠ SCA ≠ DAST

- **Trivy image** finds a vulnerable *package*
- **Semgrep** finds the vulnerable *code*
- **ZAP** proves it is *reachable*

Three different questions. Only the last is evidence of exploitability. {.punch}

<!--
This is the slide that says "I know what AppSec is" without claiming it.
Conflating the three is the common mistake, and image scanning is the one people
most often mistake for application security: it finds vulnerable PACKAGES, and
says nothing at all about NodeGoat's injection flaws.

Cost rises with the stage: a secret gitleaks catches pre-merge costs minutes;
the same secret found in production costs a rotation, an incident and an audit
trail.
-->
