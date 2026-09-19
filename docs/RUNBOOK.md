# Runbook — demonstrating the pipeline

How to run this in front of people. Written to be followed literally.

The demo takes **25–40 minutes** depending on how much you let the agents talk.
Everything except the final `terraform apply` is read-only or plan-verified.

---

## Before the room

Run this the day before, not five minutes before:

```bash
./scripts/preflight.sh rg-agentpoc-<suffix>
```

It checks tooling, session, subscription class, permissions, providers and the
estate itself, and exits non-zero if anything is missing. A red `aztfexport`
line is the usual one — Act 2 cannot run without it.

Then stand the estate up, or confirm it survived:

```bash
./scripts/deploy-sandbox.sh          # first time
az resource list -g rg-agentpoc-<suffix> -o table   # confirm 9 resources
```

**Have open:** a terminal, and `grading/grading-key.md` on a second screen the
audience cannot see. The key is what turns the demo from a vibe into a score.

---

## The argument you are making

Not "look, AI wrote some Terraform." The argument is:

> Reverse-engineering an undocumented Azure estate is a job with an objective
> pass condition — `terraform plan` returns zero changes — and a review step
> whose quality you can actually measure, because we planted the defects
> ourselves and we know which sound-looking choices are traps.

That framing is the whole value. Anyone can demo an agent producing output.
The interesting claim is that the output was *graded*.

---

## Act 0 — The estate nobody documented (3 min)

```bash
az resource list -g rg-agentpoc-<suffix> -o table
```

Nine resources. A VNet with two subnets, a storage account behind a private
endpoint with its DNS zone and zone group, a Key Vault, a Log Analytics
workspace, a managed identity, and a role assignment.

Say what is true: **none of it is under source control, and nothing says why
any of it is the way it is.** That is the normal condition of an inherited
estate — this one is just small enough to fit on a slide.

---

## Act 1 — Understand it (8–12 min)

Export the live state, then hand it to the architect:

```bash
# Claude does this — exports to discovery/
```

> Dispatch `expert-agents:azure-architect` on `opus`, scoped to `discovery/`
> only. **Never scope an agent at the repo root** — it can `Glob` its way into
> `grading/` and the score becomes meaningless.

While it runs, explain what it cannot do: no `Write`, no `Edit`, no `Bash`. It
is structurally incapable of changing anything. That is enforced by its tool
grant, not promised in its prompt.

### Then score it live

Put the grading key up. There are three planted flaws and one trap:

| | |
|---|---|
| Should find | public blob access enabled |
| Should find | Key Vault with no diagnostic settings |
| Should find | managed identity holding Contributor at resource-group scope |
| Must **not** flag | default Microsoft-managed encryption keys |

The trap is the part worth dwelling on. A reviewer that flags sound choices
costs more time than one that misses a MEDIUM, because every false positive
buys a meeting. The catalogue's own evals fail a run that trips a reject trap
even if it caught every real defect.

Five further characteristics — single region, LRS, no NSGs, an empty delegated
subnet, public network access alongside the private endpoint — are listed as
**arguable** and scored neither way. Raising them is not penalised. Say so, or
a sharp audience member will think you are hiding a miss.

---

## Act 2 — Reverse-engineer it (10–15 min)

> Dispatch `workflow-agents:terraform-import` on `sonnet` against the resource
> group.

This is the money shot, and it is binary:

```bash
cd terraform && terraform plan
```

**`No changes.` or it failed.** No interpretation, no "only cosmetic drift".
Say this before you run it so the audience knows you have not moved the
goalposts afterwards.

Expect friction, in rough order: the private DNS zone group, the role
assignment (GUID-named, frequently skipped), diagnostic settings, and the
private endpoint's Azure-managed NIC.

An honest "these three could not be imported, and here is why" is a **good**
outcome and worth showing. A silent gap is not.

---

## Act 3 — Can it land somewhere else? (5 min)

> Dispatch `platform-agents:landing-zone-preflight-validator` on `sonnet`
> against a *different* target resource group or subscription.

Policy collisions, regional SKU availability, quota headroom, unregistered
providers, CIDR overlap with peered space, and whether the deploying identity
can actually create role assignments.

Worth naming out loud: **this demo hit three of those for real.** Git Bash
mangling resource IDs, a non-idempotent script, and a free-trial subscription
with zero App Service quota at every tier. The validator exists because those
are the normal case, not the exception.

---

## Act 4 — Prove it (5 min)

```bash
az group create -n rg-agentpoc-restore -l uksouth
cd terraform && terraform apply
```

Everything before this was inference. This is the proof: the reverse-engineered
configuration standing up an equivalent environment in an empty resource group.

**This is the only step that deploys anything, and a human runs it.** No agent
in the chain has apply rights.

---

## Reset

```bash
./scripts/teardown.sh rg-agentpoc-<suffix>
./scripts/teardown.sh rg-agentpoc-restore
```

Teardown refuses any group not tagged `purpose=agent-pipeline-poc`, prints what
it is about to destroy, and makes you type the group name. It cannot be aimed
at something real by accident.

---

## When it goes wrong in the room

It will, eventually. The recovery is the same every time:

1. **Read the actual error aloud.** Half of them are environmental and
   self-explanatory — quota, a provider, a permission.
2. **`deploy-sandbox.sh` is idempotent.** Re-run it with the same `RG=` and
   `SUFFIX=` and it resumes from where it broke.
3. **Do not skip a failed stage and claim the next one passed.** The entire
   argument rests on the pass conditions being real.

The honest version of this demo — "here is where it broke and here is what that
tells you" — lands better with a technical audience than a rehearsed clean run.
The failures are the evidence that nothing was staged.

---

## Known degradation on the current estate

Built on an Azure free trial with the spending limit on, which has **0 App
Service quota at every tier including F1**. The web app was replaced with a
user-assigned managed identity carrying the same over-privileged role
assignment.

What that costs: the web app's regional VNet integration is out of the import
surface, and it was one of the four things exporters most often miss. Act 2
is a slightly easier test than designed.

Disclose this if anyone asks how hard the test was. Re-run with
`DEPLOY_WEBAPP=true` on pay-as-you-go to restore it.
