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

**Show:** IAM → Audit Logs config — Admin read / Data read / Data write all
**Enabled**, 0 exempted principals. (The yellow banner about
`resourcemanager.organizations.getIamPolicy` is expected and harmless — it only
means the console can't read the *org*'s inherited config in this project-scoped
sandbox. Your project config is fully visible and on. This page is the *config*,
not the logs — the logs are in Logs Explorer.)

**Command** — prove control-plane operations are being recorded (this returns
real entries: cluster changes, IAM grants, the bucket being made public):
```bash
gcloud logging read \
  'logName="projects/clgcporg10-152/logs/cloudaudit.googleapis.com%2Factivity"' \
  --project=clgcporg10-152 --limit=5 --freshness=1d \
  --format='value(timestamp,protoPayload.methodName,protoPayload.authenticationInfo.principalEmail)'
```

**Talking point:** *"Admin Activity logging is always on — that's every
control-plane operation, and it can't be disabled. I added Data Access logging
on top, for reads and writes. One thing worth being honest about, because it's a
genuine cloud blind spot: Data Access logs do not capture anonymous access — an
allUsers read of the public bucket leaves no audit trail at all. That shapes the
detective control, which is the next thing I'll show you."*

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

### 3 · Detective cloud control — alert when a bucket is made public  *(should)*

**Show:** the log-based metric `wizex-bucket-made-public` and the alert policy
"a Cloud Storage bucket was made public", then the triggering event in the log.

**Log link (the event that opened the door):**
https://console.cloud.google.com/logs/query;query=logName%3D%22projects%2Fclgcporg10-152%2Flogs%2Fcloudaudit.googleapis.com%252Factivity%22%0Aresource.type%3D%22gcs_bucket%22%0AprotoPayload.methodName%3D%22storage.setIamPermissions%22%0AprotoPayload.serviceData.policyDelta.bindingDeltas.member%3D%22allUsers%22;duration=P30D?project=clgcporg10-152

**Command** — fire it live, then remove the test grant (the real `allUsers`
weakness stays):
```bash
BK=wizex-backups-clgcporg10-152
gsutil iam ch  allAuthenticatedUsers:objectViewer gs://$BK   # → metric ticks, alert fires within ~1 min
gsutil iam ch -d allAuthenticatedUsers:objectViewer gs://$BK # → clean up (allUsers weakness untouched)
```

**Talking point — and lead with the nuance, it's the strong part:** *"The
obvious thing to alert on is the anonymous download itself. You can't, natively —
and that surprised me until I tested it: Cloud Audit Logs do not record allUsers
access at all. An anonymous GET returns 200 and leaves zero audit trail. So I
detect the cause instead of the symptom: the IAM change that grants public
access. That's an Admin Activity event — always on, can't be disabled — so it
fires the moment any bucket in the project is made public, in real time, before
a byte is exfiltrated. Catching the door being unlocked beats hoping to see
someone walk through it. It's also honestly a better control: it fires once, at
the misconfiguration, not on every read."*

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
- **"Your cluster has three High-priority recommendations — what are those?"** —
  Reliability recommendations, not security findings, and I can account for all
  three. One is a node-service-account best-practice nudge. The other two are my
  own Gatekeeper webhook: it's fail-closed and intercepts broadly, and I'm running
  a single replica — which I chose deliberately to stop Gatekeeper's stock
  HA footprint evicting the app on a $200 two-node cluster. A single-replica,
  fail-closed admission webhook that intercepts system requests genuinely *is* a
  reliability risk — if that pod is down, it can block cluster operations. In
  production the fix is to exclude system namespaces from the webhook and run
  multiple replicas; here I accepted the single replica as a known trade-off. GKE's
  own recommender catching that is the native tooling working — and it's the same
  point as the control that ate the workload: **controls are not free.** I'd rather
  show you the trade-off and explain it than hide it behind a green dashboard.
  (This is a *reliability* view — the security misconfiguration findings, run-as-root
  and so on, are in the Security Posture → Concerns tab, a different screen.)
