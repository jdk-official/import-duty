# Experiment — Fable 5.1 at max effort against Opus 5

**Run:** 2026-09-19 · **Question:** does a stronger model at maximum effort
produce materially better architecture and Well-Architected assessments of the
same estate, and at what cost?

## Method

The same catalogue agent, `expert-agents:azure-architect`, was run twice more,
on `claude-fable-5-1` at `max` effort, from a separate session so the effort
setting would apply. See [brief.md](brief.md) and [run-record.md](run-record.md).

| | Baseline | Experiment |
|---|---|---|
| WAF review | Act 1 — Opus 5 via this repo's orchestration session, effort `medium` | Fable 5.1, effort `max` |
| Architecture | [`docs/architecture.md`](../../../docs/architecture.md) — written by the orchestrating session (Opus 5, `medium`), not by an agent | Fable 5.1 agent, effort `max` |

**Fairness controls**

- The WAF run read the **same nine export files** the Opus review read, copied to
  an isolated directory with no prior review in it. Its brief was the Opus brief
  word for word, except that it asked for the review in the reply rather than a
  file — which is what Opus did anyway.
- The architecture brief was **neutral**: it did not give Fable the structure of
  the existing document.
- The Fable session was told not to read this repository, where the grading key
  and the Opus outputs live.

**Confounds, stated rather than hidden**

- **Model and effort both changed.** Fable ran at `max`, the baseline at
  `medium`. A difference cannot be attributed to the model alone.
- One run each. No variance estimate.
- The architecture comparison is an agent against the orchestrating session, not
  agent against agent.
- The Fable subagents inherit the session's effort; that was not independently
  observed.

## Well-Architected review — scored against the same key

Outputs: Opus [`discovery/architect-review.md`](../../../discovery/architect-review.md) ·
Fable [waf-review.md](waf-review.md). Key: [grading-key.md](../../grading-key.md).

| | Opus 5 (medium) | Fable 5.1 (max) |
|---|---|---|
| Planted: public blob access (floor HIGH) | HIGH — pass | CRITICAL — pass |
| Planted: Key Vault unlogged (floor MEDIUM) | HIGH — pass | MEDIUM — pass |
| Planted: Contributor at RG scope (floor HIGH) | HIGH — pass | HIGH — pass |
| **Trap:** Microsoft-managed encryption keys | **Clean pass** — reasoned about it and declined to raise it | **Borderline** — raised as LOW finding L2, marked "no action for the sandbox" |
| Hallucinated findings | 0 of 9 claims checked | 0 of 13 claims checked; one inference stated as read from the export |
| Findings | 14 (1 C, 5 H, 5 M, 3 L) | 13 (2 C, 3 H, 3 M, 5 L) |
| Measured cost (API-equivalent) | $1.29 | $8.25 |
| Duration | 4 min 40 s | 12 min 30 s |

**On the trap.** Fable never calls platform-managed keys a defect; L2 concerns
create-time immutability of infrastructure encryption and the key scope of queues
and tables. But it gives encryption its own numbered finding, and the key fails a
run that flags the choice. A strict grader would mark it a fail.

**The unlabelled inference.** Fable says the queue and table key scope *"is
Service"*. The export shows `null` for both. `Service` is the platform default for
an unconfigured service, and Fable cites Microsoft Learn for it, so the claim is
correct — but it is presented as read from the export.

**Found by Fable, not by Opus**

- Contributor lets the identity add a **federated credential to itself** — durable
  access from outside Azure with no secret.
- **No private route for operators exists** — no VPN, Bastion or jump host — so
  closing public access locks operators out. Opus said to prove the private path
  first; Fable noticed there is none to prove, and gave an interim option.
- `bypass: None` was set deliberately but is inert while the default action is
  `Allow`.
- Quantified ceilings: Key Vault 4,000 transactions per 10 seconds, Storage 40,000
  requests per second in UK South, integration capped at 125 instances.

**Done better by Opus**

- Rated the unlogged Key Vault HIGH, which fits the most valuable resource in the
  estate being the least observable.
- Kept the private-endpoint network-policy trap as its own finding rather than
  folding it into the NSG finding.

## Architecture

Outputs: baseline [`docs/architecture.md`](../../../docs/architecture.md) ·
Fable [architecture.md](architecture.md).

**Fable's document is the stronger one.** Each point below was checked against the
export.

- **Purpose.** From the `agent-pipeline-poc` tag and a Contributor grant shaped
  like a deployer rather than a workload, Fable offered as one reading that the
  estate is *"a disposable target for automation agents"* — which is what it is.
  The baseline asserted a private web application.
- **Build forensics, correct to the second.** A serial, scripted CLI build under
  the owner's sign-in (role assignment 7.3 seconds after the identity was
  created); a newly created subscription (Owner assignment 9.0 minutes before the
  first resource); a storage update 18 minutes 11 seconds after creation, which
  was the deploy script being re-run.
- **Hazards predicted from the export alone.** *"The endpoint IP is dynamic… recreating
  the endpoint can move it"* — the pinned-IP defect [Act 4](../../act4-score.md)
  found only by deploying. And that a rebuild reusing the name suffix must purge
  the soft-deleted vault first, which Act 4 sidestepped with a new suffix.
- **Provenance on every statement** — the export file it rests on, and whether it
  is an inference or checked against Microsoft Learn. The baseline labelled
  inference only for the purpose.

**Done better by the baseline:** a single intended-versus-realised section rather
than the same substance spread across several; shorter; and it carried no tenant
identifiers, where Fable's output needed anonymising before it could be committed
here.

## Cost

Measured from the session transcripts and priced at API list rates. The work ran
on a subscription; these are API-equivalent figures.

| | Cost |
|---|---|
| Fable orchestrating session | $4.86 |
| Fable WAF review | $8.25 |
| Fable architecture | $7.17 |
| **Fable run total** | **$20.27** |
| Opus WAF review, for comparison | $1.29 |

Rates used: Fable 5.1 $10 input / $50 output per million tokens, cache reads
$0.25; Opus 5 $5 / $25, cache reads $0.50; cache writes at twice input.

## Conclusion

**On a checklist-shaped review, Opus found every planted flaw, avoided the trap
cleanly and cost a sixth as much.** Fable's additions were real and one was
serious, but it came closer to the trap and cost more.

**On open-ended reasoning — reconstructing intent, build forensics, predicting
hazards — Fable was clearly stronger**, and it predicted two defects that
otherwise only a deployment surfaced.

Tentatively: keep `azure-architect` reviews on Opus, and trial Fable for as-built
architecture and reverse-engineering work. With one run per model and model and
effort changed together, this is a direction, not a finding.

## Next

Run Fable at `medium` on the same inputs. That changes only the model against the
baseline and separates the effect of the model from the effect of effort.
