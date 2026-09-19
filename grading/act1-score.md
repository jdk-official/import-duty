# Act 1 score — `expert-agents:azure-architect`

**Run:** 2026-09-18 · **Model:** opus · **Scope:** `discovery/` only
**Subject:** `rg-agentpoc-8e9e55d7` · **Review:** `discovery/architect-review.md`
**Agent cost:** 76,385 tokens, 16 tool calls, 4m40s

## Verdict: PASS

All three planted flaws found. The reject trap was not tripped — it was
explicitly reasoned about and declined. No hallucinated findings.

## Planted flaws

| # | Ref | Floor | Found as | Result |
|---|---|---|---|---|
| 1 | `storage-public-blob-access` | HIGH | HIGH-2 | **PASS** — at floor |
| 2 | `keyvault-no-diagnostics` | MEDIUM | HIGH-6 | **PASS** — above floor |
| 3 | `identity-contributor-at-rg` | HIGH | HIGH-3 + MEDIUM-8 | **PASS** — see note |

### Note on flaw 3

The agent split this across two findings rather than raising it as one:

- **HIGH-3** names the Contributor assignment as half of a composed control
  bypass — Contributor grants `listKeys`, Shared Key auth is live, therefore the
  identity reaches all data as the account rather than as itself, outside RBAC
  scoping and invisible to Conditional Access.
- **MEDIUM-8** raises the over-privilege on its own terms.

Scored PASS at HIGH: the substance is present at HIGH severity with a concrete
remediation, and the composed framing is a **better** analysis than the grading
key anticipated. The key assumed over-privilege was the whole finding; the agent
found the mechanism that makes it exploitable.

Worth recording as a grading-key weakness rather than an agent weakness. A
future key for this estate should state flaw 3 as the composition, not the
assignment alone.

## Reject trap

| Ref | Result |
|---|---|
| `default-encryption-keys` | **PASS — not flagged** |

MEDIUM-11 addresses encryption directly and declines to call it a defect:

> "Infrastructure encryption (double encryption at rest) and customer-managed
> keys are both absent. **Neither is a finding on its own** — platform-managed
> encryption at rest is on and is sufficient absent a stated compliance
> requirement, and no such requirement was stated."

This is the strongest single result of the run. The agent did not merely avoid
the trap by omission; it reasoned about the exact thing the trap tests, stated
why it is sound, and recorded the create-time-immutability caveat that makes it
worth mentioning at all.

## Arguable items — scored neither way

| Item | How it was handled |
|---|---|
| Public network access alongside the PE | Escalated to CRITICAL-1, its top finding |
| No NSGs | HIGH-5 |
| Single region / `Standard_LRS` | Recorded as trade-off, explicitly not scored as a gap |
| Empty delegated subnet | LOW-14 |

Escalating the public-access/PE combination to CRITICAL is a legitimate reading
and is not penalised. The reasoning given — that it makes every other network
control in the group ineffective — is sound.

## Unplanted findings — all verified true

The agent found four significant issues that were not planted. Every factual
claim was checked against the raw export:

| Claim | Export value | True? |
|---|---|---|
| `allowSharedKeyAccess` null → Shared Key live | `None` | yes |
| Storage `networkRuleSet.defaultAction` | `Allow` | yes |
| Storage `publicNetworkAccess` | `Enabled` | yes |
| KV `publicNetworkAccess` | `Enabled` | yes |
| KV `networkAcls` | `None` | yes |
| KV `enablePurgeProtection` | `None` | yes |
| KV `softDeleteRetentionInDays` | `7` | yes |
| NSG count | `0` | yes |
| `privateEndpointNetworkPolicies` both subnets | `Disabled` | yes |

**Zero hallucinations.** Under the catalogue's seeded-defect probe rules,
hallucinated findings count against the score; there are none to count.

The Shared Key finding (HIGH-3) is the standout. It was not planted, it is real,
and it is arguably the most serious issue in the estate — the deployment script
never set `allowSharedKeyAccess`, so it inherited the permissive null default
without anyone deciding to.

## Degradation reported honestly

Two things the agent flagged rather than papering over:

1. **Microsoft Learn MCP tools were not reachable.** It fell back to `WebFetch`
   against learn.microsoft.com and named the four articles and their publication
   dates. This confirms the concern raised before the run: the agent declares
   Learn MCP tools under `mcp__microsoft-learn__*` while the installed plugin
   exposes them under a longer prefixed name, so the grounding path does not
   resolve. The documented fallback worked.
2. **Eight specific things it could not verify** from the export, including the
   one that would change its own findings: role assignments scoped *below* the
   resource group. It stated that if a data-plane role exists at resource scope,
   effective permissions are wider than shown, not narrower.

## Actions arising

- **Fix the discovery export** to include container access levels, the
  `blobServices/default` sub-resource, and resource-scoped role assignments.
  Three of the agent's "could not verify" items are export gaps, not estate
  gaps, and they are cheap to close.
- **Update the grading key** for flaw 3 to describe the composition.
- **Investigate the Learn MCP tool-name mismatch** — the agent works without it,
  but grounding is slower and less precise over `WebFetch`.
