---
layout: two-cols-header
---

# The pipeline finds both halves. Nothing joins them.

::left::

### What I have today

- Checkov + Trivy on `terraform/`
- Trivy on the image
- A log-based alert on the bucket

Three lists. Three scales. {.punch}

::right::

### What none of them can say

- That the CVE-ridden image is the one **running**, unauthenticated
- That its ServiceAccount reads **every Secret**
- That the VM behind that credential holds `roles/editor`
- That the bucket needs **no exploit at all**

<!--
Every finding on the left is real and already caught. The right-hand column is
not a tooling gap — it is a MODEL gap. No scanner here holds identity,
reachability and RBAC in one place, so none of them can express a path.

Snyk on the application side would give me a better flat list. Still flat. SCC
would be a fourth console reporting the same misconfigurations again.

Do not rush this slide. It is the setup; the next one is the payoff.
-->

---
layout: default
---

# Wiz adds the edges, not more findings

- **Security Graph** — resources, identities, exposure, RBAC *and* the repo, one model
- **Toxic combination** — the chain becomes a query result, not a act of cleverness
- **Agentless** — nothing installed on a host I already do not trust
- **Code to cloud** — the fix ships as a **pull request against the IaC**

Checkov hands me fifty findings in CVSS order.

Wiz hands me the one path — and the PR that closes it. {.punch}

<!--
The code-to-cloud point lands hardest in exactly this environment, because it is
IaC-managed: the running container traces back to FROM node:16-bullseye in
app/Dockerfile; the public bucket to google_storage_bucket_iam_member.public_read
in terraform/bucket.tf. Fix it in the console and the next tofu apply puts it
back. The fix has to land in the repository or it is not a fix.

Two honest caveats if pushed: prioritisation holds because the graph knows
reachability and identity, not because it has a better CVE feed. And this is the
narrative built on real artefacts — I am describing the edges Wiz would draw
over this project, not replaying a tenant I have used.
-->

---
layout: two-cols-header
---

# What I would do differently

::left::

### Knowingly traded away

- **Pulumi** — lost to HCL's scanning ecosystem
- **SHA-pin then sign** — cosign + Binary Authorization
- **Digest-pinned images** — not mutable tags

::right::

### The honest gap

- Everything here reasons about **configuration**
- It says the path is exploitable
- It cannot say it *is being* exploited

A detective control that has never fired is a hypothesis. {.punch}

<!--
Tone: these are trade-offs made knowingly, not things I missed.

The runtime point is the honest limit of the entire exercise, and it is also
precisely the Wiz Defend argument — configuration state versus workload
behaviour. A runtime sensor is what tells me the vulnerable pod actually spawned
a shell and reached 169.254.169.254. That is the difference between an attack
path and an incident.

The thing I would add first with more lab time: walk the whole path end to end —
SSH in, download the backup anonymously, use the pod token to read Secrets, use
the VM token to list instances — and watch the log-based alert fire. I have
demonstrated Gatekeeper rejecting a pod. I have not proved the detective control
by making it fire.

On state, if it comes up: the generated password still resolves into Terraform
state, which is why state is versioned, IAM-restricted and public-access-
enforced. The real fix is it never passing through Terraform at all.
-->

---
layout: default
class: text-center
---

# Let's look at the live environment

`kubectl` · the file in the running container · the data · the controls firing {.lede .mx-auto}

<!--
Order for the walkthrough:

  just demo-proof          pods, service, ingress, wizexercise.txt, cluster-admin
  just url                 open the app, log in as admin
  just demo-blast          the pod's own token reads every Secret in the cluster
  just demo-public-bucket  anonymous download, no credentials at all
  just demo-prevent        the privileged pod is REJECTED, live

The blast-radius one is the moment: five Secrets across three namespaces,
including the Mongo URI with its password — read by the application pod's own
token, reaching outside its own namespace.

Then the bucket, which needs no exploit and no credential: that is your user
table, downloaded from the public internet.
-->
