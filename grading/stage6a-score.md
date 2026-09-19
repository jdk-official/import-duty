# Act 6a score — design-then-import

**Run:** 2026-09-18 · **Agent:** `expert-agents:devops-infrastructure-expert` (sonnet)
**Scored against:** [stage6a-criteria.md](stage6a-criteria.md), committed before the run
**Agent cost:** 194,909 tokens, 135 tool calls, 18m04s

## Verdict: PASS — hypothesis held

```
Plan: 15 to import, 0 to add, 0 to change, 0 to destroy.
```

Re-run independently by the orchestrator with **no state file present**, so the
result is a genuine plan-time evaluation of the import blocks.

## Defect class 1 — literal where a reference belonged: AVOIDED

```hcl
principal_id = module.identity.principal_id
```

No literal principal GUID anywhere in the configuration.

## Defect class 2 — Azure-managed values captured as config: AVOIDED

```hcl
records = ["10.42.2.4"]              # placeholder only
tags    = { creator = "placeholder" }
lifecycle { ignore_changes = [records, tags] }
```

None of the source estate's GUIDs (identity, NIC suffix, private-endpoint
resource GUIDs) appears in the configuration.

It also identified a **third** Azure-managed value not named in the brief — the
private endpoint's auto-generated NIC name — and handled it the same way.

## The azapi question

Four AVM modules (resource group, VNet, storage account, private DNS zone)
implement their core resource with `azapi_resource`. Confirmed from source.

Refinement of Act 6's claim: `azapi_resource` **does** accept import blocks.
The reason to prefer `azurerm_*` here is diff granularity — `azapi` compares an
opaque `body` document, `azurerm` a typed schema — not a hard technical block.

## Where the approach was awkward

The AVM Log Analytics module could not be imported cleanly: it declares an
internal helper resource with no Azure counterpart, and a provider refresh gap
produced a phantom diff. A caller has no `lifecycle` access to a module's
internal resources, so the workspace was kept as a raw resource. Three AVM
modules were adopted (identity, key vault, private endpoint).

## Effort

| | Act 3 (generate-then-fix) | Act 6a (design-then-import) |
|---|---|---|
| Tokens | 147,223 | 194,909 |
| Tool calls | 74 | 135 |
| Wall time | 15m51s | 18m04s |
| Defects in output | 2, found later | 0 |

Roughly a third more effort for a result that needed no correction.

## Open

15 resources imported against Act 3's 16. The difference is
`azurerm_storage_account_queue_properties`, which holds only default values.
Not yet established whether omitting it is correct or a gap.
