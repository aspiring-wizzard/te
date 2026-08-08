---
layout: two-cols-header
---

# The pipeline is the control plane

Controls sit as early as they usefully can — that is where the fix is cheapest. {.lede}

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
— don't read the tool list. the ORDERING is the point.

— image scan runs BEFORE the registry push
  ⇒ a failing image never reaches the registry, never mind the cluster
— that's precisely where Wiz Code slots in: same findings, in the PR,
  with cloud context attached

— EOL check in stage 2 is new — I added it after finding a gap.
  story's coming.

— say the grey footnote before anyone asks:
  enforced branch protection + environment approvals need a public or Pro repo
  the workflows declare them; only the enforcement is licence-gated
  → claiming a control I can't show is what loses the room

── IF ASKED ──
why does nothing block?
  → soft_fail and exit-code 0, deliberately. this environment is knowingly
    vulnerable, so fail-on-finding would mean a permanently red pipeline —
    and a permanently red pipeline trains people to stop reading it. both
    flip to fail-on-CRITICAL in production.
what about the cloud jobs?
  → gated on credentials being present. without them they skip rather than
    fail red. same reasoning.
-->

---
layout: default
---

# SAST ≠ SCA ≠ DAST

- **Trivy image** finds a vulnerable *package*
- **Semgrep** finds the vulnerable *code*
- **ZAP** tests what is *actually deployed*

Three different questions. Only the last one looks at the running app. {.punch}

<!--
— three different questions, and conflating them is the common mistake

— image scanning is the one people most often mistake for AppSec
  it finds vulnerable PACKAGES. it says nothing about NodeGoat's
  injection flaws — those are in code the image scanner never parses.

— cost rises with the stage:
  a secret gitleaks catches pre-merge costs minutes
  the same secret in production costs a rotation, an incident, an audit trail

── IF ASKED ──
does ZAP prove exploitability?
  → no, and I'd be careful there. this is the BASELINE — passive spider,
    passive rules, no active attack. it tells me the flaw class is present
    on a live target. it doesn't prove someone can weaponise it.
why not active scanning?
  → an active scan attacks the target. here the target IS the demo
    environment, so I'd risk destroying the thing I'm showing you. in a real
    programme active scanning belongs in disposable staging.
-->
