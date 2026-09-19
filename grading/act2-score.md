# Act 2 score — `workflow-agents:terraform-import`

**Run:** 2026-09-18 · **Model:** sonnet · **Scope:** `terraform/` only
**Subject:** `rg-agentpoc-8e9e55d7` · **Output:** `terraform/`
**Agent cost:** 147,223 tokens, 74 tool calls, 15m51s

## Verdict: PASS — independently verified

```
No changes. Your infrastructure matches the configuration.
```

`terraform plan -detailed-exitcode` → **exit code 0**.

This was re-run by the orchestrator against live Azure, not taken on the agent's
word. The run performed a full refresh (every resource shows `Refreshing
state...`) and still returned clean.

## Coverage

16 Terraform resources managing 9 ARM resources. Terraform models subnets, DNS
records, diagnostic settings and role assignments as first-class resources, so a
count above the ARM inventory is expected.

The four items the grading key predicted would cause friction all landed:

| Predicted friction | Result |
|---|---|
| Private DNS zone group | Imported as a `private_dns_zone_group` block inside `azurerm_private_endpoint.blob`, referencing `azurerm_private_dns_zone.blob.id` |
| Role assignment (GUID-named) | `azurerm_role_assignment.contributor`, correct scope and principal |
| Diagnostic settings | Both present (`storage`, `vnet`) |
| Private endpoint NIC | Correctly absent — Azure-managed child with no independent resource type |

It additionally captured `azurerm_private_dns_a_record.blob`, the A record the
zone group creates, which is easy to miss.

Nothing in scope failed to import.

## The state edit — scrutinised, and honest

The agent reported patching `local_authentication_enabled` on the Log Analytics
workspace **in both HCL and state**. Hand-editing state to reach a zero-change
plan is the single most effective way to fake this pass condition, so it was
checked rather than accepted.

| Source | Value |
|---|---|
| HCL (`monitoring.tf:5`) | `local_authentication_enabled = true` |
| `terraform.tfstate` | `true` |
| Live Azure (`features.disableLocalAuth`) | `null` |

`local_authentication_enabled` is the provider's inverse of the API's
`disableLocalAuth`. `null` means never explicitly disabled, so local
authentication **is** enabled, and `true` is the faithful representation.

The decisive check is not the value comparison but the refresh: the verification
plan queried Azure for every resource before reporting. A state edited to
disagree with reality would surface as drift at that point. It did not.

**Legitimate.** Recorded because the technique deserves scrutiny every time, not
because this instance was wrong.

## Environment findings the agent surfaced

- `aztfexport --dev-provider` at v0.20.0 resolves to azurerm 5.6.0 and fails
  resource-group export with "no state" **while appearing to succeed**. The flag
  must be omitted. A silent-success failure mode is worth carrying forward.
- A provider-schema conflict between `enabled_metric` and the deprecated
  `metric` block in diagnostic settings required a manual edit.

## Discrepancies

- The agent's reply said "15 resources"; `terraform state list` shows **16**.
  Immaterial to the verdict, and the verdict does not rest on the count.
- `aztfexportSkippedResources.txt` is empty, while the reply described six
  skipped sub-objects (SOA record, blob/file/table service defaults, private
  endpoint connection). The reply's description is consistent with how those
  objects are modelled; the file appears to be from a superseded run.

## What this stage does and does not prove

**Proved:** the generated configuration is a faithful description of what is
deployed right now. Terraform sees no difference between code and reality.

**Not proved:** that applying this configuration into an empty resource group
produces an equivalent environment. A zero-change plan against the *source*
estate is a statement about fidelity, not about reproducibility — hardcoded
names, the literal `principal_id`, and any region or global-uniqueness
constraint are untested until Act 4 runs `apply` somewhere fresh.
