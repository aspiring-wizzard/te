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
- everything on the left is real, and already caught today. no gaps there.

- the right column is not a tooling gap. it's a MODEL gap. no scanner here holds identity + reachability + RBAC in one place, so none of them can express a PATH — only a list

- and buying more scanners doesn't fix it: Snyk on the app side = a better flat list. still flat. SCC = a fourth console reporting the same misconfigurations again

- slow down here. this is the setup; the next slide is the payoff.

#### If asked

- **couldn't you correlate these yourself?** — *I did — that's the attack-path slide. It took me knowing the environment intimately and going looking. That doesn't scale to an estate I didn't build, and it doesn't survive me leaving.*
-->

---
layout: default
---

# Wiz adds the edges, not more findings

- **Security Graph** — resources, identities, exposure, RBAC *and* the repo, one model
- **Toxic combination** — the chain becomes a query result, not an act of cleverness
- **Agentless** — nothing installed on a host I already do not trust
- **Code to cloud** — the fix ships as a **pull request against the IaC**

Checkov hands me 32 findings, unordered.

Wiz hands me the one path — and the PR that closes it. {.punch}

<!--
So what would actually change here.

Not the findings. I have the findings. What I don't have is the edges between
them — and that's what the graph is: cloud resources, identities, network
exposure, Kubernetes RBAC and the repository, all in one model. The chain I
walked you through earlier stops being something I had to be clever enough to
spot, and becomes a query result.

That's the difference I'd want to land. Checkov gives me thirty-two findings
against this Terraform and no way to rank them — because ranking needs
reachability and identity, and Checkov can see neither. Wiz gives me the one
path that actually matters.

The agentless part matters more than it sounds. That Mongo VM is a host I
already don't trust. Snapshot scanning means I inventory it without installing
anything on it — and it's also the answer to the gap I showed you two slides
ago, where the VM had no SBOM at all.

And then code-to-cloud, which lands hardest in exactly this environment because
everything here is IaC-managed. The running container traces back to a line in
app/Dockerfile. The public bucket traces back to a resource in
terraform/bucket.tf. So the fix ships as a pull request against the
infrastructure code — which matters, because if you fix this in the console,
the next apply puts it straight back.

#### If asked

- **where does the 32 come from?** — *Checkov's actual output in CI against terraform/ — 56 passed, 32 failed. It'll drift as the code changes. The number isn't the point; "unordered" is.*
- **have you used Wiz in production?** — *No, and I won't pretend otherwise. This is the narrative built on real artefacts — I'm describing the edges Wiz would draw over this specific project, not replaying a tenant I've operated.*
- **is this just better prioritisation?** — *It holds because the graph knows reachability and identity, not because it has a better CVE feed. That distinction is the whole thing.*
-->

---
layout: two-cols-header
---

# What I would do differently

::left::

### Knowingly traded away

- **Pulumi** — lost to HCL's scanning ecosystem
- **Image signing** — cosign attestations (Binary Auth enforces an allowlist today)
- **Digest-pinned images** — not mutable tags

::right::

### The honest gaps

- **The VM has no SBOM** — only what is *declared* is checked
- Everything here reasons about **configuration**, not behaviour
- It says the path is exploitable; not that it *is being* exploited

Agentless disk scanning closes the first. A runtime sensor closes the second. {.punch}

<!--
- left column: things I traded away knowingly, not things I missed Pulumi lost to HCL's scanning ecosystem — I'd revisit that the day a pipeline standardises on policy-as-code

- right column is the honest limit of the whole exercise: everything I built reasons about CONFIGURATION it can tell you the path is exploitable it cannot tell you it IS being exploited

- and that's two different fixes: no VM SBOM        → agentless disk scanning config ≠ behaviour → a runtime sensor ("the vulnerable pod actually spawned a shell and hit 169.254.169.254" — that's the difference between an attack path and an incident)

- last line: I've shown Gatekeeper REJECT a pod. I have never made the detective control fire. that's the first thing I'd add with more lab time.

#### If asked

- **what would the simulation look like?** — *SSH in from the internet → download the backup anonymously → use the pod token to read Secrets → use the VM token to list instances → then watch the log-based alert fire and the calls land in Cloud Audit Logs.*
- **anything else still open?** — *the generated password resolves into Terraform state. That's why state is versioned, IAM-restricted and public-access-enforced. The real fix is it never passing through Terraform at all.*
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
