# import-duty

Reverse-engineering live Azure infrastructure into Terraform, using the
[agent-catalog](https://github.com/angrayOne/agent-catalog) agents — and proving
the pipeline works before pointing it at anything real.

The name is what you pay for clickops.

---

## Executive summary

**What we did.** We took an Azure estate built by hand in the portal — nine
resources, no infrastructure-as-code, no documentation — and brought it under
Terraform control using specialist agents from the agent catalogue. We then
proved the result could rebuild the estate from nothing in an empty resource
group, modernised it onto Azure Verified Modules, and produced an as-built
architecture document and a Well-Architected review.

**Why the agent catalogue mattered.** The catalogue does not provide one general
assistant; it provides specialists with fixed roles, restricted tools, and their
own built-in verification. That structure is what made the output trustworthy:

- **Reviewers cannot change what they review.** The architecture reviewer holds
  no write tools, so every finding is a finding, never a silent fix.
- **Builders verify their own work before finishing.** The import agent is not
  done until Terraform reports zero difference from the live estate.
- **Judgement and execution run on different models.** The strongest model
  handles assessment; a faster one handles construction whose output is checked
  mechanically.
- **Agents can be scored, not just trusted.** Following the catalogue's own
  evaluation discipline, we planted known flaws and deliberate traps in the
  estate before any agent saw it, and graded every result against that key.

**Efficiency.** Work we estimate at around **eighteen working days** — close to
four weeks — for an experienced Azure engineer working manually was executed by
agents in roughly **45 minutes**, with every stage independently verified. Agents also found
issues that were not planted — including the review's highest-severity finding.

**What we found.** Every scored stage passed. The most useful result was not a
pass mark but an insight: **Terraform that perfectly matches what exists is not
the same as Terraform that can recreate it.** Our first import matched the live
estate exactly and still carried two defects that would only have surfaced
when deployed somewhere new. The approach we recommend for real engagements
avoids both by design.

**Scope.** A disposable sandbox with known ground truth, chosen so every stage
could be graded objectively. What we would do differently is under
[How we'd improve next time](#how-wed-improve-next-time).

---

## Approach

**Build the ground truth first.** The sandbox was created with three
deliberate security flaws and one deliberate trap — a sound design choice that
*looks* flaggable. The grading key was written before any agent ran. An agent
that flagged the trap would fail, however many real flaws it caught.

**One specialist per stage.** Each act is owned by a single catalogue agent
chosen for that job, dispatched on the model tier the job warrants.

**Scope every agent to its inputs.** Each agent was pointed at one directory and
nothing else. The grading key lives elsewhere, so no agent could read the
answers.

**Verify every claim independently.** No agent result was accepted on its own
word. Every plan was re-run, factual findings were checked against the raw
export, and agent edits to state and configuration were inspected.

**Humans hold the deploy button.** No agent in the chain can deploy. Reviews are
read-only, builds are plan-verified, and the one live deployment was run by a
person.

**Fix criteria before results.** Where an act tested a hypothesis of our own,
the pass criteria were committed to the repository before the run, so the result
could not be graded generously after the fact.

---

## The acts

| Act | Purpose | Catalogue agent | Model | Output | Result |
|---|---|---|---|---|---|
| 0 | Build the test estate | *scripted, not an agent* | — | [deploy script](scripts/deploy-sandbox.sh) · [grading key](grading/grading-key.md) | 9 resources, 3 planted flaws, 1 trap |
| 1 | Understand and assess it | `expert-agents:azure-architect` | Opus | [WAF review](docs/waf-review.md) · [architecture](docs/architecture.md) · [agent's review](discovery/architect-review.md) | **Pass** · [score](grading/act1-score.md) |
| 2 | Reverse-engineer into Terraform | `workflow-agents:terraform-import` | Sonnet | [`terraform/`](terraform/) · [import report](terraform/import-report.md) | **Pass** · [score](grading/act2-score.md) |
| 3 | Pre-flight a deployment target | `platform-agents:landing-zone-preflight-validator` | Sonnet | — | Not run |
| 4 | Prove it rebuilds from nothing | *human-run deploy* | — | [`terraform/`](terraform/) applied to an empty resource group | **Pass** · [score](grading/act4-score.md) |
| 5 | Modernise onto Azure Verified Modules | `workflow-agents:avm-refactor` | Sonnet | [`terraform-avm/`](terraform-avm/) · [refactor report](terraform-avm/avm-refactor-report.md) | Complete, unscored |
| 5a | Design first, then import | `expert-agents:devops-infrastructure-expert` | Sonnet | [`terraform-hybrid/`](terraform-hybrid/) · [import report](terraform-hybrid/hybrid-import-report.md) | **Pass** · [criteria](grading/act5a-criteria.md) · [score](grading/act5a-score.md) |

---

## What we did in each act

### Act 0 — Build the test estate

**Output:** [scripts/deploy-sandbox.sh](scripts/deploy-sandbox.sh) · [grading key](grading/grading-key.md)

A script built a small but realistic application platform: a virtual network
with application and private-endpoint subnets, a storage account behind a
private endpoint with private DNS, a Key Vault, a Log Analytics workspace, and a
managed identity with a role assignment. It was built through the Azure CLI
rather than Terraform, deliberately — the point was to import something that had
never been under code.

Three flaws were planted: anonymous blob access enabled, a Key Vault with no
audit logging, and an identity holding far broader rights than it needed. One
trap was set: default platform-managed encryption, which is sound and should not
be flagged.

### Act 1 — Understand and assess it

**Output:** [WAF review](docs/waf-review.md) · [architecture](docs/architecture.md) · [agent's review](discovery/architect-review.md) · [score](grading/act1-score.md)

**Agent:** `azure-architect` on Opus, reading a structured export of the live
estate.

It produced a severity-ranked security and Well-Architected review: fourteen
findings, each with a concrete remediation, with date-sensitive platform
behaviour checked against current Microsoft documentation.

**Result:** all three planted flaws found, the trap correctly declined with
stated reasoning, and no invented findings — every claim checked against the
raw export was correct. Its most important findings were not planted: storage
still open to the internet despite its private endpoint (the review's only
critical), and a path by which the identity could read all storage data with a
shared account key, bypassing the keyless design it was evidently built for.

### Act 2 — Reverse-engineer into Terraform

**Output:** [`terraform/`](terraform/) · [import report](terraform/import-report.md) · [score](grading/act2-score.md)

**Agent:** `terraform-import` on Sonnet.

It generated Terraform for every resource and imported the live estate into
Terraform state, working until the configuration matched reality exactly.

**Result:** `No changes. Your infrastructure matches the configuration.`
Re-verified independently against live Azure. All sixteen Terraform resources
under management, including the relationships generators commonly miss — the
private DNS zone group, the role assignment, and diagnostic settings.

### Act 3 — Pre-flight a deployment target

**Agent:** `landing-zone-preflight-validator` — not run in this exercise.

Its role is to confirm, before any deployment, that a target subscription can
receive it: policy restrictions, quota, registered providers, address-space
overlap, and deployment permissions. Act 4 deployed into the same subscription
as the source, where those conditions were already known.

### Act 4 — Prove it rebuilds from nothing

**Output:** [score and evidence](grading/act4-score.md)

**Human-run deployment**, from a plan verified beforehand.

The configuration was parameterised so a second copy could coexist with the
first, then deployed into an empty resource group.

**Result:** sixteen resources created, nothing touched in the original estate,
and the rebuilt environment wired correctly — including the managed identity's
permissions binding to the *new* identity rather than the original one. A
post-deployment check surfaced one configuration value owned by Azure rather
than by us; it was corrected, and both estates now match their configuration
exactly.

### Act 5 — Modernise onto Azure Verified Modules

**Output:** [`terraform-avm/`](terraform-avm/) · [refactor report](terraform-avm/avm-refactor-report.md)

**Agent:** `avm-refactor` on Sonnet.

It moved the resources that suit Microsoft's verified modules onto them, keeping
behaviour identical to the original and justifying every difference.

**Result:** five of sixteen resources modernised. Where a module's defaults are
more secure than the imported estate — network restrictions, purge protection,
public ingestion — the agent held the original behaviour and flagged each one,
so those gaps are now named settings that can be changed deliberately. Four
further modules were declined for a sound technical reason.

Unscored: equivalence was reasoned rather than proven against live state — and
review since has found one place it does not hold. The live Key Vault uses RBAC
authorisation; the refactored configuration sets the module's legacy
access-policy flag, which disables RBAC. Applied, it would change the vault's
access model rather than preserve it.

### Act 5a — Design first, then import

**Output:** [`terraform-hybrid/`](terraform-hybrid/) · [import report](terraform-hybrid/hybrid-import-report.md) · [criteria](grading/act5a-criteria.md) · [score](grading/act5a-score.md)

**Agent:** `devops-infrastructure-expert` on Sonnet.

The reverse of Act 2. Rather than generating code from the estate and then
correcting it, the agent wrote the intended configuration first — modules,
variables, references — and bound the live estate into it using Terraform's
native import capability. Tested without writing state or changing anything in Azure.

**Result:** `15 to import, 0 to add, 0 to change, 0 to destroy`. Both defect
classes found after Act 2 were avoided by design, with no correction needed, and
a third Azure-owned value was identified unprompted. This is the approach we
recommend for real engagements.

---

## Benefits

### Effort against manual delivery

Estimated effort for an experienced Azure engineer working without AI tooling,
against measured agent execution time.

| Work | Manual estimate | Agent execution |
|---|---|---|
| **Act 0** — design and script a test estate with planted flaws; write the grading key | 2 days | orchestrated, not separately timed |
| **Act 1** — build discovery tooling; security and Well-Architected review, 14 findings with remediation | 3 days | 5 min |
| **Act 2** — import the estate to a zero-difference Terraform state | 2 days | 16 min |
| **Act 4** — parameterise, rebuild in an empty resource group, resolve drift | 1 day | orchestrated; human-run deploy |
| **Act 5** — refactor onto Azure Verified Modules with equivalence reasoning | 3 days | 7 min |
| **Act 5a** — design the configuration, bind the estate with import blocks | 3 days | 18 min |
| **Documentation** — architecture, WAF review, generated inventory and diagrams, runbook | 4 days | drafted, then reviewed |
| **Total** | **~18 days (about four weeks)** | **~45 min of agent execution** |

Agent times are execution only; direction and review sat alongside them.

### Quality

- **Nothing invented.** Findings were checked against the source data; none was
  wrong.
- **Beyond the brief.** The review's highest-severity finding was not planted,
  and the design-first import found an Azure-owned value that had not been
  identified.
- **Proven, not asserted.** Every scored stage ends in a mechanical check — a zero
  difference, a clean deployment — rather than a judgement that it looks right.

### Control

- **Separation of duties enforced by tooling**, not by instruction: reviewers
  cannot edit, builders cannot deploy.
- **Parallel delivery.** The rebuild and the modernisation ran at the same time
  in isolated workspaces without interfering.
- **Repeatable.** Every stage consumes the previous stage's output from the
  repository, so the whole pipeline can be re-run against a new estate.

---

## Challenges

**Matching reality is not the same as reproducing it.** Act 2's Terraform
matched the live estate perfectly and still carried two defects: a permission
pinned to the original identity rather than to whichever identity the code
creates, and values Azure generates itself recorded as if someone had chosen
them. Neither shows up until the code is deployed somewhere new. This is why Act
5 exists, and why we recommend the design-first approach of Act 5a.

**Telling configuration from platform behaviour.** An exporter reads what Azure
reports and cannot know which values a person chose and which Azure stamped on
its own. Separating the two needs judgement, and it is the difference between
code that deploys once and code that deploys anywhere.

**Modernising without changing behaviour.** Microsoft's verified modules default
to stronger security than the estate had. Adopting them honestly means holding
the original behaviour first and changing it as a deliberate, separate decision —
otherwise a refactor silently becomes a security change nobody reviewed.

**Module coverage.** Only some resources can move onto verified modules without
rebuilding them. Knowing which, and why, matters before promising a client a
fully modular estate.

**Trusting agent output.** Agents are fast and often right, but a pipeline is
only as credible as its checks. Every claim in this exercise was independently
verified, and the grading key was fixed before the agents ran. That discipline
is what turns agent output into evidence.

---

## Lessons learned

### What worked — keep doing it

**Plant the answers before the agents run.** Planted flaws, a deliberate trap,
and criteria committed before the run turned agent output from plausible into
gradable. Without them there is no way to tell a thorough review from a
confident one. *Evidence:* [grading key](grading/grading-key.md) ·
[Act 5a criteria](grading/act5a-criteria.md)

**Verify every claim independently.** Checking caught real problems in three
places: an agent's edit to Terraform state, which proved legitimate only once
checked against live Azure; a discovery script recording failed queries as
"none found"; and overclaims in this write-up's own first draft. *Evidence:*
[Act 2 score](grading/act2-score.md) ·
[discovery notes](docs/running.md) ·
[write-up corrections](https://github.com/jdk-official/import-duty/commit/8f08030)

**Rebuild from nothing.** Deploying into an empty resource group was the only
test of whether the code could reproduce the estate, and it found a defect no
other act could. *Evidence:* [Act 4 score](grading/act4-score.md)

### What surprised us

**Matching is not reproducing.** A Terraform configuration with zero difference
from the live estate still carried two defects that surfaced only when deployed
elsewhere. *Evidence:* [Act 4 score](grading/act4-score.md)

**Modernising did not secure anything.** Azure Verified Module defaults were
stronger than the estate's settings, and preserving behaviour meant switching
them off. A refactor and a security improvement are separate decisions.
*Evidence:* [refactor report](terraform-avm/avm-refactor-report.md)

**The agents found what we did not plant.** The review's only critical finding —
storage open to the internet despite its private endpoint — was not one of the
planted flaws. *Evidence:* [Act 1 score](grading/act1-score.md)

**Unverified equivalence was wrong in one place.** The modernisation reasoned
that behaviour was preserved; the module source shows the Key Vault's access
model would change. Reasoning is not proof. *Evidence:*
[`terraform-avm/identity_security.tf`](terraform-avm/identity_security.tf)

---

## How we'd improve next time

| Improvement | Why | Affects |
|---|---|---|
| Start with design-then-import; use `aztfexport` for discovery only | Act 5a avoided by design both defects Act 2 produced | Acts 2, 5a |
| Prove modernisation against live state, not by reasoning | Act 5's reasoned equivalence missed a change to the Key Vault access model | Act 5 |
| Run pre-flight before the rebuild | Act 3 was not run | Act 3 |
| Time one act done by hand | The efficiency comparison rests on estimates | Benefits |
| Build the test estate with compute | The sandbox could not host an App Service, so VNet integration never reached the import — Act 2 was an easier test than designed | Act 0 |
| Keep tenant identifiers out from the first commit | Parameterise them in Terraform and scan before every commit, rather than cleaning history afterwards | All |
| Run the documentation agent | `iac-docs-writer` would give cited, drift-checkable infrastructure docs; it was not run | Documentation |

### Feedback to the agent catalogue

Found in use; each is a candidate issue or pull request for the catalogue.

- **`azure-architect` grounding does not resolve.** It declares Microsoft Learn
  tool names that do not match those the installed grounding plugin exposes, so
  it falls back to fetching documentation pages directly. It said so honestly,
  but grounding is weaker than designed. *Evidence:*
  [Act 1 score](grading/act1-score.md)
- **`azure-architect` cannot write its own report.** It holds no write tools by
  design, so a dispatcher must ask for the report in the reply, not in a file.
  Worth stating in the agent's output contract.
- **`avm-refactor` equivalence is unproven by default.** Without state it
  reasons rather than plans, and here the reasoning missed a behaviour change.
  Its contract could require a live plan diff where state is available.
- **Skill behavioural evals only cover one plugin.** `tools/skill_eval.py` is
  scoped to `backlog-delivery`, so scenarios for skills elsewhere are not
  validated.

---

## Deliverables

| | |
|---|---|
| [Architecture](docs/architecture.md) | As-built design, reverse-engineered, with intended-versus-realised analysis |
| [Well-Architected review](docs/waf-review.md) | Findings by pillar and severity, with an ordered remediation plan |
| [Generated inventory](docs/generated-inventory.md) | Topology, dependencies and immutable decisions, regenerated from the live export |
| [`terraform/`](terraform/) | The imported estate — the proven baseline |
| [`terraform-avm/`](terraform-avm/) | Modernised onto Azure Verified Modules |
| [`terraform-hybrid/`](terraform-hybrid/) | Designed first, then imported — the recommended approach |
| [`grading/`](grading/) | Ground truth, pre-registered criteria, and every score |

**Running it yourself:** [docs/running.md](docs/running.md) ·
**Demonstrating it:** [docs/RUNBOOK.md](docs/RUNBOOK.md)
