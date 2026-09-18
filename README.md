# import-duty

Reverse-engineering live Azure infrastructure into Terraform, using the
[agent-catalog](https://github.com/angrayOne/agent-catalog) agents — and proving
the pipeline works before pointing it at anything real.

The name is what you pay for clickops.

---

## The pipeline

Four stages, four agents. Each stage produces an artifact the next one consumes,
so the whole thing is re-runnable and reviewable rather than a one-off session.

| Stage | Agent | Input | Output | Pass condition |
|---|---|---|---|---|
| 1. Understand | `expert-agents:azure-architect` | `discovery/` export | severity-tagged findings + WAF view | planted flaws found, traps not flagged |
| 2. Document | `workflow-agents:iac-docs-writer` | `terraform/` | `docs/` | every claim cites a resolving `file:line` |
| 3. Reverse-engineer | `workflow-agents:terraform-import` | live resource group | `terraform/` | **`terraform plan` returns zero changes** |
| 4. Pre-flight | `platform-agents:landing-zone-preflight-validator` | target subscription | go/no-go report | findings match reality |
| 5. Prove it | *(human)* | `terraform/` | a working environment | `apply` into a fresh RG produces an equivalent |

Nothing in stages 1–4 deploys anything. `azure-architect` has no write tools at
all; `terraform-import` and `iac-troubleshooter` are plan-verified and never
apply. **Stage 5 is yours.**

---

## Layout

```
scripts/     preflight.sh (readiness), deploy-sandbox.sh, teardown.sh
docs/        RUNBOOK.md — how to demo this; generated documentation
discovery/   raw exports from the live tenant (gitignored — see below)
terraform/   generated configuration
grading/     ground truth for the PoC — DO NOT point an agent here
```

### The grading directory

`grading/grading-key.md` holds the answers: which flaws were deliberately
planted in the sandbox and which sound-looking choices are traps.

**Scope every agent to a specific subdirectory, never the repo root.** An agent
given the root can `Glob` its way into `grading/` and the probe becomes
worthless. Point `azure-architect` at `discovery/`, `iac-docs-writer` at
`terraform/`.

### Discovery exports are gitignored

Raw exports carry tenant IDs, subscription IDs and full resource IDs. For a
throwaway sandbox that hardly matters; for a client estate it matters a lot, and
the habit should be the same in both cases. Commit curated summaries under
`docs/`, never the raw dumps.

---

## Running the PoC

Prerequisites: `az`, `terraform`, `aztfexport`, and a subscription where you
hold **Owner** or **User Access Administrator** — the sandbox creates a role
assignment, which Contributor alone cannot do.

```bash
az login
./scripts/preflight.sh                  # check every prerequisite, change nothing
./scripts/deploy-sandbox.sh --what-if   # see what it would build
./scripts/deploy-sandbox.sh             # build it
```

`deploy-sandbox.sh` is idempotent — re-run it with the same `RG=` and `SUFFIX=`
to resume after a failure rather than starting over.

**Demonstrating this to people:** follow [docs/RUNBOOK.md](docs/RUNBOOK.md).

Then work the stages in order. Teardown when done:

```bash
./scripts/teardown.sh rg-agentpoc-xxxxxxxx
```

### Terraform variables

`subscription_id` and `tenant_id` have **no defaults** — supply them per
environment so no tenant identifier is committed:

```bash
cd terraform
cat > terraform.tfvars <<'EOF'
subscription_id = "<your subscription id>"
tenant_id       = "<your tenant id>"
EOF
terraform plan
```

`terraform.tfvars` is gitignored. Alternatively export `TF_VAR_subscription_id`
and `TF_VAR_tenant_id`.

`teardown.sh` refuses any resource group not tagged
`purpose=agent-pipeline-poc`, so it cannot be aimed at something real.

Cost is roughly £0.50–£1 per day, dominated by the B1 App Service plan and the
private endpoint. Same-day teardown makes it pennies.

---

## Why a synthetic estate first

You cannot grade a review of infrastructure you do not already understand. When
the architect returns eight findings against a real estate, there is no way to
know whether it missed four.

The sandbox is built with known defects and known-good choices, so every stage
has an objective pass/fail. Once the pipeline passes here, the catalogue's own
[probe discipline](https://github.com/angrayOne/agent-catalog/blob/main/docs/probes.md)
calls for one live-validation run against a real application — synthetic
fixtures cannot surface permission denials mid-run, shell friction, or the false
positives that only appear in messy real data.
