# Cloud Native Security — demo script

Everything for the "Cloud Native Security" section of the exercise: what to show,
the link to show it at, the command, and the one sentence that says *why it
matters*. Project is `clgcporg10-152`, cluster `wizex-gke`, zone `europe-west1-b`.

## The map — requirement → control → where it lives

| Exercise requirement | Control | CSP-native? | Show it at |
|---|---|---|---|
| Control-plane **audit logging** (must) | Cloud Audit Logs — Admin Activity + Data Access | ✅ native | Logs Explorer |
| Native tooling to **detect misconfigurations** (role-gated) | **GKE Security Posture** (`BASIC` + `VULNERABILITY_BASIC`) | ✅ native | Security Posture dashboard |
| ≥1 **detective** cloud control (should) | Log-based metric + Monitoring alert on anonymous bucket reads | ✅ native | Logs / Monitoring |
| ≥1 **preventative** cloud control (must) | **Binary Authorization** — control-plane admission | ✅ native | Binary Authorization page |
| (defense in depth) | Gatekeeper — Kubernetes admission | ◻ K8s-layer | live `kubectl` |
| **CI/CD** security (optional) | 4 pipelines: SAST/SCA/secrets/SBOM, IaC scan, image scan, DAST, EOL | ✅ | GitHub Actions |

**The honest framing to open with:** *"Security Command Center is the native tool
you'd reach for, and it's denied at the org in this project-scoped sandbox — I
confirmed that with `testIamPermissions`. So I used the native controls that
were in scope, and they cover the same ground at the layers that matter here."*

---

## Console links (open these tabs before you start)

- **GKE Security Posture** — https://console.cloud.google.com/kubernetes/security/dashboard?project=clgcporg10-152
- **Binary Authorization** — https://console.cloud.google.com/security/binary-authorization?project=clgcporg10-152
- **Logs Explorer** (audit logs) — https://console.cloud.google.com/logs/query?project=clgcporg10-152
- **Log-based metrics** — https://console.cloud.google.com/logs/metrics?project=clgcporg10-152
- **Monitoring → Alerting** — https://console.cloud.google.com/monitoring/alerting/policies?project=clgcporg10-152
- **IAM → Audit Logs config** — https://console.cloud.google.com/iam-admin/audit?project=clgcporg10-152
- **GKE cluster** — https://console.cloud.google.com/kubernetes/clusters/details/europe-west1-b/wizex-gke?project=clgcporg10-152
- **Backup bucket** (the public one) — https://console.cloud.google.com/storage/browser/wizex-backups-clgcporg10-152?project=clgcporg10-152
- **GitHub Actions** — https://github.com/aspiring-wizzard/te/actions

---

## The demo, in order

### 1 · Control-plane audit logging  *(must)*

**Show:** IAM → Audit Logs config (Data Access enabled on *All services*), then
Logs Explorer with the anonymous bucket read already captured.

**Command** — surface the anonymous read in the audit log:
```bash
gcloud logging read \
  'resource.type="gcs_bucket" AND protoPayload.authenticationInfo.principalEmail=""' \
  --project=clgcporg10-152 --limit=3 --freshness=1d --format=json
```

**Talking point:** *"Admin Activity logging is on by default — that's the control
plane. What I added is Data Access logging, because that's what makes a read of
the backup bucket visible at all. Without it, the exfiltration leaves no trace.
This is the substrate the detective control is built on."*

### 2 · Native misconfiguration detection — GKE Security Posture  *(role-gated 'native tooling')*

**Show:** the Security Posture dashboard — workload misconfiguration concerns
(privileged, run-as-root, over-broad RBAC) and, with vuln scanning on, CVEs in
the running images.

**Command:**
```bash
just demo-posture          # prints the dashboard link + confirms the mode
```

**Talking point:** *"This is the native detective control. Security Command
Center is the org-level product and it's denied here — but GKE Security Posture
is the project-scoped, GKE-native equivalent for the workload layer. It's
agentless, it audits the same misconfigurations Checkov flagged in CI, and it
finds them again at runtime against what's actually deployed. That's the
code-to-cloud continuity in one screen: the same finding, caught twice."*

> Check the dashboard the morning of the panel — findings can take time to
> populate after a cluster change, and you want to point at real ones.

### 3 · Detective cloud control — the anonymous-access alert  *(should)*

**Show:** the log-based metric `wizex-public-bucket-access` and the alert policy
"anonymous access to backup bucket".

**Command** — fire it, then show the metric tick:
```bash
# trigger: anonymous download, no credentials (this is finding #4)
curl -s "https://storage.googleapis.com/storage/v1/b/wizex-backups-clgcporg10-152/o" | head
# then watch the metric increment in Logs → Metrics, or the alert condition go active
```

**Talking point:** *"The detective control is specific: it fires on
`principalEmail=""` — an unauthenticated read of the backup bucket. During this
demo that's expected. In production it's data exfiltration, and it's the
difference between finding out in minutes and finding out from a headline. Note
what it can and can't do: it tells me the access happened; it can't prevent it.
That's why it's paired with a preventative control."*

### 4 · Preventative cloud control — Binary Authorization  *(must — the native one)*

**Show:** the Binary Authorization policy (default *deny*, the app image
allowlisted), then reject a pod live.

**Command:**
```bash
just demo-binauthz         # applies a normal nginx pod with an un-allowlisted image
# → Error from server (VIOLATES_POLICY): Image nginx:stable denied by Binary
#   Authorization default admission rule. Denied by always_deny admission rule
```

**Talking point:** *"This is the preventative control, and it's native — enforced
by the GKE control plane itself, not by anything I installed into the cluster.
The policy is default-deny with our own application image allowlisted, so only
images we vouch for run. That nginx pod is otherwise completely ordinary — it's
rejected purely because we didn't authorise the image. In a supply-chain
context this is the control that stops a compromised or unreviewed image from
ever starting. It's also where Wiz Code's attestation story plugs in: allowlist
today, signed attestations tomorrow."*

### 5 · Preventative, defense-in-depth — Gatekeeper  *(the Kubernetes-layer one)*

**Command:**
```bash
just demo-prevent          # applies a PRIVILEGED pod (allowlisted image, so BinAuthz admits it)
# → Error from server (Forbidden): [deny-privileged-containers] privileged
#   container is not allowed: bad
```

**Talking point:** *"Two preventative controls, deliberately answering two
different questions. Binary Authorization asks 'are we allowed to run this image
at all?' — that's the cloud provider. Gatekeeper asks 'is this workload
configured safely?' — that's Kubernetes admission. I kept the demos clean on
purpose: this privileged pod uses the allowlisted image, so Binary Authorization
lets it through and Gatekeeper is unambiguously the one rejecting it, on the
privileged flag."*

### 6 · Security in CI/CD  *(optional — you have it)*

**Show:** the GitHub Actions runs — `appsec` (gitleaks / Semgrep / Trivy fs /
SBOM / EOL lifecycle), `iac` (Checkov + Trivy config), `app` (image scan).

**Talking point:** *"The controls so far detect and prevent at runtime. The
pipeline moves the same questions left — the misconfiguration Security Posture
flags on the cluster is the one Checkov flags in the pull request, before it
ships. Same finding, cheapest possible place to fix it."*

---

## The close for this section

*"So: audit logging underneath, a detective control and a native posture scanner
watching what's deployed, and two preventative controls stopping the next bad
action — one at the image, one at the workload. What none of them do on their
own is tell me which of these findings actually chains into a breach. That's the
graph, and that's the next slide."*

(→ hands straight into the Wiz value slide.)

---

## Answers ready, if asked

- **"Why not Security Command Center?"** — Denied. `securitycenter.findings.list`
  fails; this is a project-scoped CloudLabs sandbox with no org permissions. I
  confirmed it rather than assumed it. GKE Security Posture is the in-scope
  native substitute for the workload layer.
- **"Why not an Org Policy for the preventative control?"** — `orgpolicy.policy.set`
  is also denied — org-scoped, same reason. Binary Authorization is project-scoped
  and *was* permitted (`binaryauthorization.policy.update` — I checked), so that's
  the native preventative I could actually implement.
- **"Is Gatekeeper really a *cloud* control?"** — It's Kubernetes-layer, which is
  exactly why I added Binary Authorization: a genuinely CSP-native preventative,
  enforced by the control plane. Gatekeeper is defense-in-depth on top.
- **"Did you enable Security Posture or was it a default?"** — It was on at `BASIC`
  by default; I made it explicit in Terraform and enabled vulnerability scanning,
  so it's intentional and reproducible rather than inherited.
- **"Binary Authorization with an allowlist — isn't signing the real control?"** —
  Yes. Allowlist-by-image is the enforced baseline; the stronger posture is cosign
  attestations verified by the policy, which is a named next step. The enforcement
  mechanism — control-plane admission, default-deny — is already the right one.
