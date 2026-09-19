# Act 4 score — end-to-end reproducibility

**Run:** 2026-09-18 · **Applied by:** the user (agents hold no apply rights)
**Source estate:** `rg-agentpoc-8e9e55d7` · **Target:** `rg-agentpoc-restore01` (fresh, empty)

## Verdict: PASS — with one real defect, now fixed

The reverse-engineered configuration stood up an equivalent environment in an
empty resource group. Everything before this act was inference; this is the
proof the pipeline is worth pointing at a real estate.

## What the apply proved

| Test | Result |
|---|---|
| Plan against empty target | 16 to add, 0 to change, **0 to destroy** |
| Apply | all 9 ARM resources created |
| **Role assignment binds to the NEW identity** | **correct** |
| Delegated subnet accepted on a fresh VNet | `Microsoft.Web/serverFarms` |
| Private DNS A record resolves | `stagentpocrestore01` → `10.42.2.4` |
| Globally-unique names | no collision after parameterisation |

### The role assignment is the headline

This was the defect found before Act 4 ran: `aztfexport` emitted
`principal_id` as a literal GUID pinned to the identity in the *source* resource
group. Applied unchanged, a fresh deployment would have created a new identity
and then granted Contributor on the new resource group to the **old** one — a
silent cross-environment privilege grant.

| | |
|---|---|
| Source estate identity | `<source-identity>` |
| New estate identity | `<new-identity>` |
| Contributor holder on new RG | `<new-identity>` |

Correct. The fix — `azurerm_user_assigned_identity.this.principal_id` in place
of the literal — is proved by apply, not by reading.

## The defect Act 4 caught

Immediately after a successful apply, `terraform plan` returned **exit 2**:

```
# azurerm_private_dns_a_record.blob will be updated in-place
  ~ tags = {
      ~ "creator" = "…resource guid 8d3f492b-…" -> "…resource guid f269f680-…"
    }
Plan: 0 to add, 1 to change, 0 to destroy.
```

The A record is created by the private endpoint's DNS zone group. **Azure owns
it**, stamps a `creator` tag carrying the private endpoint's resource GUID, and
allocates its address from `snet-pe` at deploy time. `aztfexport` captured both
as user configuration.

Consequences, none of which a zero-change plan against the source estate would
ever reveal:

- The config is **not idempotent across environments** — every plan in any new
  deployment shows a diff, permanently.
- Terraform would overwrite Azure's value with the source estate's, carrying an
  identifier from one environment into another.
- The address `10.42.2.4` is likewise pinned; it happened to match here, and
  would not in a VNet with different addressing.

**Fixed** with `lifecycle { ignore_changes = [tags, records] }` and a comment
explaining why. Verified: baseline plan still clean (exit 0), restored estate
now clean (exit 0).

The cleaner fix is to drop the A record from Terraform management entirely,
since it is a side-effect of the zone group rather than an independent
resource. That was not taken here — it changes state as well as config, and the
minimal fix restores idempotence.

## What this says about the pipeline

A zero-change plan against the source estate is **fidelity**. It is a strong
result and it is not reproducibility. Act 2 passed cleanly and the config still
carried two reproducibility defects — one caught by reading it before the apply
(the role assignment), one that only a real apply into a fresh environment could
surface (the Azure-managed tag).

Both are inherent to reverse-engineering, not to this tool: an exporter reads
ARM and cannot distinguish "the user set this" from "Azure stamped this".

**Act 4 is not optional.** It is the only act that tests the thing the exercise
is actually for.

## Cost note

Two estates now deployed — `rg-agentpoc-8e9e55d7` and `rg-agentpoc-restore01`.
Tear the restored one down with `terraform destroy` from
`import-duty-work/restore`, which is cleaner than `teardown.sh` since it has
state behind it.
