# Running import-duty

The operator's manual: layout, prerequisites, commands, variables, teardown, and environment notes. The project write-up is in the [README](../README.md).

---

## Layout

```
scripts/           preflight.sh, deploy-sandbox.sh, discover.sh, diagram.py, teardown.sh
docs/              architecture.md (as-built design), waf-review.md (assessment),
                   generated-inventory.md (regenerated), RUNBOOK.md (how to demo this)
discovery/         live export (gitignored) + architect-review.md
terraform/         imported configuration — the proven baseline
terraform-avm/     the same estate refactored onto Azure Verified Modules
terraform-hybrid/  the same estate authored first, then bound with import blocks
grading/           ground truth and scores — DO NOT point an agent here
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
python scripts/diagram.py                    # regenerate docs/generated-inventory.md
```

`deploy-sandbox.sh` is idempotent — re-run it with the same `RG=` and `SUFFIX=`
to resume after a failure rather than starting over.

**Demonstrating this to people:** follow [docs/RUNBOOK.md](RUNBOOK.md).

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
