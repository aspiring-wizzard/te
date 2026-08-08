# OpenTofu/Terraform practices used here

## 1. Plan → review → apply, done properly

Your instinct is right, but the usual form of it has a hole:

```bash
tofu plan          # review the output
tofu apply         # ← RE-PLANS. May apply something different from what you read.
```

`apply` without a saved plan computes a **fresh** plan. Between your review and your apply, state can move — a colleague applied, a console change drifted, a data source re-resolved. You approved one thing and shipped another.

**The correct form, and what `just` now does:**
```bash
just plan          # tofu plan -out=tfplan
just review        # tofu show tfplan          (or `just review-short`)
just apply         # tofu apply tfplan  ← exactly the reviewed plan, then deletes it
```

- **The plan file is the artefact of approval.** In CI it should be uploaded by the plan job and consumed by the apply job — the same object a human approved.
- **Consumed plans are deleted.** A stale plan applied later is the same bug in slow motion.
- **Plan files are gitignored** — they contain resolved values, including the generated Mongo password.
- **`-lock-timeout=5m`** so a concurrent run waits rather than failing outright.
- **`just drift`** uses `-detailed-exitcode`: `0` clean, `2` changes pending, `1` error. That is the exit code a scheduled drift check should gate on.

## 2. Workspaces — and why *not* for dev/prod

**The short answer: don't use workspaces to separate environments.** It is one of the most common Terraform mistakes.

`tofu workspace` gives you **multiple state files against one configuration and one backend**. That is the whole feature. It does not give you:

- **Different credentials or projects.** The provider block is shared, so `dev` and `prod` authenticate the same way into the same place unless you contort it.
- **Blast-radius separation.** One credential set can reach every workspace. The isolation is bookkeeping, not security.
- **Protection from the classic outage.** `tofu workspace select` is invisible state in your shell. Everyone who has run this long enough has applied to the wrong workspace.
- **Divergence without pain.** Environments always diverge, and with workspaces that shows up as `terraform.workspace == "prod" ? … : …` conditionals spreading through the config until nobody can read it.

**Use workspaces for what they are good at:** short-lived, *genuinely identical* copies of the same stack — per-PR preview environments, per-developer scratch, ephemeral test rigs.

**For dev/prod, separate the root module and the state:**
```
terraform/
  modules/
    network/  gke/  mongo/          # the reusable pieces
  envs/
    dev/   main.tf  backend.hcl  terraform.tfvars
    prod/  main.tf  backend.hcl  terraform.tfvars
```
Each env is its own root, its own state, its own backend and credentials. Code is shared through `modules/`, not through a workspace switch. Blast radius is a directory boundary, and `cd` is a lot harder to get wrong than `workspace select`.

*(A single root with `-backend-config=envs/prod.hcl -var-file=envs/prod.tfvars` is a lighter middle ground — but it relies on the operator passing both flags every time, so the directory split is safer.)*

**Blue/green:** workspaces *can* serve here, because the two stacks genuinely are identical and short-lived. But it is usually better expressed **inside** the configuration — two node pools, or two instance groups behind one load balancer with weighting — so the cutover is a reviewable plan diff rather than a state-file swap.

## 3. Structure

**This repository uses a flat root module, deliberately.** With ~25 resources that is the correct choice; modules would add indirection and no reuse. Premature modularisation is as real a problem as premature abstraction anywhere else.

Conventions worth keeping:

| Practice | Why |
|---|---|
| One file per logical group (`network.tf`, `gke.tf`, `mongo.tf`, `security.tf`) | Grep-ability. The file name is the search index. |
| `versions.tf`, `variables.tf`, `outputs.tf` always present | Reviewers know where to look without reading everything |
| **Commit `.terraform.lock.hcl`** | CI resolves identical provider versions to your laptop |
| Pin providers (`~> 6.0`) | An unpinned major upgrade is a surprise you get at `apply` time |
| Remote state + locking (GCS gives both) | Two people, one state, no corruption |
| `prevent_destroy` on anything whose loss is unrecoverable | Cheap insurance against a mis-typed `destroy` |
| **`moved` blocks** when renaming resources | Refactor without `state mv` surgery |
| `-target` is an escape hatch, never a workflow | It silently skips dependency ordering |
| Validation blocks on inputs (`admin_cidr`) | Fail at plan, not after GCP has built something unreachable |

**When to reach for modules:** genuine reuse (three environments needing the same VPC), or a boundary somebody else consumes. Not "this file is getting long" — that is what more files are for.

## 4. Where this build knowingly falls short
- ~~CI plans and applies without passing the plan artefact~~ — **closed.** The plan job now uploads `tfplan`, the apply job downloads it and applies that file. Note the apply step needs neither `-auto-approve` nor any `TF_VAR_*`: a saved plan already carries every resolved value, which is exactly why nothing can differ between review and apply. The artefact has 5-day retention because a binary plan contains resolved values, including the generated password.
- **No `moved` blocks**, because nothing has been renamed yet.
- **One environment.** The dev/prod split above is the pattern I would use, not something this exercise needs.
