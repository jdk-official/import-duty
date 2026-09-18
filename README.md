# import-duty

Reverse-engineering live Azure infrastructure into Terraform, using the
[agent-catalog](https://github.com/angrayOne/agent-catalog) agents — and proving
the pipeline works before pointing it at anything real.

The name is what you pay for clickops.

---

## Results

Run end to end against a disposable sandbox on 2026-09-18. Every stage was
scored against ground truth written before the run, and every agent claim was
re-verified by the orchestrator rather than accepted.

| Act | Agent | Result |
|---|---|---|
| 1. Build the estate | *(scripted)* | 9 resources, 3 planted flaws, 1 reject trap |
| 2. Understand | `expert-agents:azure-architect` | **PASS** — 3/3 flaws found, trap not tripped, 0 hallucinated findings |
| 3. Reverse-engineer | `workflow-agents:terraform-import` | **PASS** — zero-change plan, independently re-verified |
| 4. Pre-flight | `platform-agents:landing-zone-preflight-validator` | not run |
| 5. Prove it | *(human applies)* | **PASS** — equivalent estate stood up in an empty RG; one defect found and fixed |
| 6. Modernise | `workflow-agents:avm-refactor` | done, **unscored** — static equivalence only, no live plan diff |

Scores and evidence are in [`grading/`](grading/).

### The finding that matters

**A zero-change plan against the source estate is fidelity, not reproducibility.**

Act 3 passed cleanly, and the configuration still carried two defects that would
only bite somewhere else:

1. `principal_id` on the role assignment was emitted as a **literal GUID** pinned
   to the identity in the source resource group. Applied unchanged, a fresh
   deployment creates a new identity and then grants Contributor on the new
   resource group to the **old** one. Caught by reading; fixed with a resource
   reference; proved correct by Act 5.
2. The private DNS A record carried a `creator` tag holding the private
   endpoint's resource GUID, plus a pinned IP address. Both are **Azure-managed**.
   `aztfexport` captured them as user configuration, so every plan in any new
   environment showed a permanent diff — and Terraform would have pushed the
   source estate's identifier into the target. Only a real apply surfaced this.

Neither is a fault in `aztfexport`. An exporter reads ARM and cannot distinguish
"the user set this" from "Azure stamped this". **Act 5 is not optional** — it is
the only act that tests what the exercise is for.

### What AVM did and did not fix

`avm-refactor` moved 5 of 16 resources onto Azure Verified Modules. Four AVM
defaults are *more secure* than the imported estate — Key Vault network ACLs
deny-by-default, purge protection on, RBAC authorisation, Log Analytics internet
ingestion off — and all four had to be **explicitly overridden** to preserve plan
equivalence.

That is correct refactoring discipline, and it is the useful result: modernising
onto Microsoft's modules did not fix the security findings, but it turned four of
them into named lines of configuration you can now flip deliberately.

Four more resources have AVM modules that were rejected for a concrete reason:
they implement their core resource via `azapi_resource` rather than `azurerm_*`,
so there is no valid `moved`-block path and adoption would force destroy/recreate
of most of the estate.

---

## The pipeline

Each stage produces an artifact the next one consumes, so the whole thing is
re-runnable and reviewable rather than a one-off session.

| Stage | Agent | Input | Output | Pass condition |
|---|---|---|---|---|
| 1. Understand | `expert-agents:azure-architect` | `discovery/` export | severity-tagged findings + WAF view | planted flaws found, traps not flagged |
| 2. Document | `workflow-agents:iac-docs-writer` | `terraform/` | `docs/` | every claim cites a resolving `file:line` |
| 3. Reverse-engineer | `workflow-agents:terraform-import` | live resource group | `terraform/` | **`terraform plan` returns zero changes** |
| 4. Pre-flight | `platform-agents:landing-zone-preflight-validator` | target subscription | go/no-go report | findings match reality |
| 5. Prove it | *(human)* | `terraform/` | a working environment | `apply` into a fresh RG produces an equivalent |
| 6. Modernise | `workflow-agents:avm-refactor` | `terraform/` | `terraform-avm/` | plan equivalence, every diff justified |

No agent in the chain deploys anything. `azure-architect` holds no write tools at
all; `terraform-import` and `avm-refactor` are plan-verified and never apply.
**The apply is yours.**

---

## Layout

```
scripts/        preflight.sh, deploy-sandbox.sh, discover.sh, diagram.py, teardown.sh
docs/           RUNBOOK.md (how to demo this), architecture.md (generated)
discovery/      live export (gitignored) + architect-review.md
terraform/      imported configuration — the proven baseline
terraform-avm/  the same estate refactored onto Azure Verified Modules
grading/        ground truth and scores — DO NOT point an agent here
```

### The grading directory

`grading/grading-key.md` holds the answers: which flaws were deliberately
planted in the sandbox and which sound-looking choices are traps.

**Scope every agent to a specific subdirectory, never the repo root.** An agent
given the root can `Glob` its way into `grading/` and the probe becomes
worthless. Point `azure-architect` at `discovery/`, `terraform-import` at
`terraform/`, `avm-refactor` at its own copy.

When two agents run in parallel, give each its own working directory. Both want
to rewrite Terraform, and neither may touch the proven baseline.

### Discovery exports are gitignored

Raw exports carry tenant IDs, subscription IDs and full resource IDs. For a
throwaway sandbox that hardly matters; for a client estate it matters a lot, and
the habit should be the same in both cases. Commit curated summaries under
`docs/`, never the raw dumps.

---

## Running it

Prerequisites: `az`, `terraform`, `aztfexport`, and a subscription where you hold
**Owner** or **User Access Administrator** — the sandbox creates a role
assignment, which Contributor alone cannot do.

```bash
az login
./scripts/preflight.sh                       # check prerequisites, change nothing
./scripts/deploy-sandbox.sh --what-if        # see what it would build
./scripts/deploy-sandbox.sh                  # build it
./scripts/discover.sh rg-agentpoc-xxxxxxxx   # export live state to discovery/
python scripts/diagram.py                    # regenerate docs/architecture.md
```

`deploy-sandbox.sh` is idempotent — re-run it with the same `RG=` and `SUFFIX=`
to resume after a failure rather than starting over.

**Demonstrating this to people:** follow [docs/RUNBOOK.md](docs/RUNBOOK.md).

### Terraform variables

`subscription_id` and `tenant_id` have **no defaults** — supply them per
environment so no tenant identifier is committed. `suffix` and
`resource_group_name` default to the original estate; override both to deploy a
second copy, because the storage account and key vault names are globally unique
and a deleted vault's name is held for 7 days by soft delete:

```bash
cd terraform
cat > terraform.tfvars <<'EOF'
subscription_id     = "<your subscription id>"
tenant_id           = "<your tenant id>"
suffix              = "restore01"
resource_group_name = "rg-agentpoc-restore01"
EOF
terraform init && terraform plan
```

`terraform.tfvars` is gitignored. Alternatively export `TF_VAR_*`.

### Teardown

```bash
./scripts/teardown.sh rg-agentpoc-xxxxxxxx    # the az-built sandbox
cd terraform && terraform destroy             # anything Terraform applied
```

`teardown.sh` refuses any resource group not tagged `purpose=agent-pipeline-poc`,
prints what it will destroy, and makes you type the group name.

Cost is pennies per day — the private endpoint is the only meaningful line item.

---

## Environment hazards

Every one of these cost real time on a Windows machine, and every one failed
*silently* rather than loudly. They are documented because the next person will
hit them too.

| Hazard | Symptom |
|---|---|
| **MSYS path rewriting** in Git Bash | Azure resource IDs become `C:/Program Files/Git/subscriptions/...`. Export `MSYS_NO_PATHCONV=1` and `MSYS2_ARG_CONV_EXCL="*"`. |
| **`az … -o tsv` emits CRLF** on multi-line output | A stray `\r` inside a resource ID corrupts any URL built from it, and ARM answers with an HTML *"Bad Request — Invalid URL"* that reads like a server fault. Pipe through `tr -d '\r'`. |
| **Free-trial subscriptions have 0 App Service quota** at *every* tier, F1 included | The sandbox falls back to a user-assigned managed identity. Set `DEPLOY_WEBAPP=true` on pay-as-you-go. |
| **`winget` does not add `aztfexport` to PATH** | Invoke it by full path. `preflight.sh` detects this and warns rather than failing. |
| **`aztfexport --dev-provider`** at v0.20.0 | Resolves to azurerm 5.6.0 and fails resource-group export with "no state" *while appearing to succeed*. Omit the flag. |
| **`az monitor diagnostic-settings list`** | Returns Bad Request for several resource types whether or not settings exist, so it cannot distinguish "none configured" from "query failed". `discover.sh` uses the REST API and records the query status. |

That last one is the important one. An earlier version of `discover.sh` recorded
every failed query as *zero diagnostic settings* — fabricated evidence, and here
it would have wrecked the probe outright, because one of the planted flaws **is**
a resource with no diagnostic settings. A false zero is indistinguishable from
the real thing. Never record an unanswered question as a negative answer.

---

## Why a synthetic estate first

You cannot grade a review of infrastructure you do not already understand. When
the architect returns eight findings against a real estate, there is no way to
know whether it missed four.

The sandbox is built with known defects and known-good choices, so every stage
has an objective pass/fail. Once the pipeline passes here, the catalogue's own
[probe discipline](https://github.com/angrayOne/agent-catalog/blob/main/docs/probes.md)
calls for one live-validation run against a real application — synthetic fixtures
cannot surface permission denials mid-run, shell friction, or the false positives
that only appear in messy real data.
