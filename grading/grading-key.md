# Grading key — agent pipeline PoC

**Keep this directory out of any path an agent is pointed at.** It lives as a
sibling of `azure-poc/` rather than inside it so an agent doing a broad `Glob`
over the working folder cannot stumble into the answers.

Ground truth for the estate built by `azure-poc/deploy-sandbox.sh`.

---

## Stage 1 — `expert-agents:azure-architect`

### Must find (3)

| # | Ref | Floor | What was planted |
|---|---|---|---|
| 1 | `storage-public-blob-access` | HIGH | Storage account created with `--allow-blob-public-access true`. The platform default has been `false` since 2023; this is an explicit deviation that permits anonymous container/blob reads. |
| 2 | `keyvault-no-diagnostics` | MEDIUM | No diagnostic settings on the Key Vault. Storage and the web app both have them wired to the Log Analytics workspace, so this is a gap in an otherwise-instrumented estate, not a blanket absence. |
| 3 | `identity-contributor-at-rg` | HIGH | The web app's system-assigned managed identity holds **Contributor at resource-group scope**. The catalogue's own security defaults say never Contributor on a workload identity. Correct remediation is a narrow data-plane role (e.g. Storage Blob Data Contributor scoped to the storage account). |

Severity is a **floor** — flagging higher is fine and does not fail the probe.

### Must NOT flag (1 trap)

| Ref | Why it is sound |
|---|---|
| `default-encryption-keys` | The storage account uses default Microsoft-managed encryption keys. This is encrypted at rest and is the correct choice absent a stated regulatory requirement for customer-managed keys. Flagging it as a defect is a false positive and **fails the probe**, regardless of how many real flaws were caught. |

### Legitimately arguable (neither credit nor penalty)

These are real characteristics of the estate that a thorough review may raise.
Do not score them either way — note them for interest.

- `publicNetworkAccess: Enabled` on the storage account alongside the private
  endpoint. Defensible during migration, worth flagging in a hardening review.
- Single region, no zone redundancy. No SLA was stated, so there is no target
  to measure against — the architect should say so rather than assume one.
- `Standard_LRS` rather than ZRS/GRS. Same reasoning.
- B1 App Service plan has no autoscale and no redundancy.
- No NSGs on either subnet.

### Pass condition

All 3 planted flaws identified at or above their floor, each with a concrete
remediation; the encryption-key trap **not** flagged as a defect.

---

## Stage 2 — `workflow-agents:iac-docs-writer`

Pass: every factual claim in the generated document carries a `file:line`
citation that resolves to the stated line in the generated Terraform. Spot-check
ten at random; any that does not resolve is a fail.

---

## Stage 3 — `workflow-agents:terraform-import`

Pass: `terraform plan` against the imported state returns **zero changes**.
Binary. No interpretation, no "only cosmetic drift".

Expect friction on, in rough order of likelihood:
- the private DNS zone group (`az` models it differently from the provider)
- the role assignment (GUID-named, frequently skipped by exporters)
- diagnostic settings (often not exported at all)
- the VNet integration on the web app (a swift/regional delegation, easily missed)

Any of these appearing as a diff is a **fail** that needs fixing, not a caveat
to wave through. An honest "these four could not be imported, here is why" is a
different and acceptable outcome — record which.

---

## Stage 4 — `platform-agents:landing-zone-preflight-validator`

No planted flaws; this one is graded on whether its report matches reality.
Verify by hand against the target subscription:
- policy assignments it lists actually exist at that scope
- the vCPU quota numbers match `az vm list-usage`
- resource providers it reports as unregistered really are
- CIDR overlap findings match the actual address space

Fail if it asserts a blocker that is not real, or misses one that is.

---

## Stage 5 — end-to-end

Pass: `terraform apply` of the generated configuration into a **fresh, empty**
resource group produces a working equivalent of the original — same topology,
same identity wiring, same private endpoint resolution.

This is the one that decides whether the pipeline is worth using on the real
estate. Everything before it is inference; this is proof.
