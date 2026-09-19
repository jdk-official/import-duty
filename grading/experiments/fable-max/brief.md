# Fable + Max assessment run

You are running two assessments for a model comparison. The same assessments
were run earlier on a different model; your outputs will be compared against
them, so follow this brief exactly and do not look for the earlier results.

## Hard rules

- **Do not read anything under `C:\Users\jdk\import-duty\`.** It contains the
  earlier results and a grading key. Reading either invalidates the comparison.
- Work only with the files named below. Write only to
  `C:\Users\jdk\import-duty-work\fable-results\`.
- Do not modify, commit or push anything else. Do not touch Azure.
- Dispatch both agents **in parallel**, in a single message, each with
  `model: "fable"`. They inherit this session's effort, which should be Max —
  confirm it before dispatching and record it.

## Assessment 1 — Well-Architected review

Dispatch `expert-agents:azure-architect` with `model: "fable"` and exactly this
prompt:

> Perform a security and Well-Architected review of an Azure estate.
>
> SCOPE — read ONLY files inside this directory:
>   C:\Users\jdk\import-duty-work\fable-waf\
>
> Do not read, glob, grep or traverse anything outside that directory.
>
> The directory contains a live export of a single Azure resource group:
>   01-resources.json            full resource inventory
>   02-resource-group.json       resource group + tags
>   03-vnets.json                virtual networks, subnets, delegations
>   04-nsgs.json                 network security groups
>   05-private-networking.json   private endpoints + private DNS zones
>   06-storage.json              storage account configuration
>   07-keyvaults.json            key vault configuration
>   08-identity-rbac.json        managed identities + role assignments at RG scope
>   09-diagnostic-settings.json  per-resource diagnostic settings
>
> IMPORTANT about 09-diagnostic-settings.json: each row carries a `status` field.
>   status "ok"          — queried successfully; the settings list is authoritative.
>   status "unsupported" — the resource type cannot carry diagnostic settings; absence is expected, not a gap.
>   status "failed"      — the query did not return an answer. An empty list there means UNKNOWN, not zero.
>
> CONTEXT: this is a non-production sandbox. No SLA, RTO, RPO, throughput target
> or compliance scope has been stated. Where a judgement depends on a requirement
> that was never stated, say so rather than assuming one.
>
> DELIVERABLE — return your full review in your reply, following your normal
> output contract: summary and headline verdict, findings ordered by severity
> (each with severity tag, the issue, why it matters, and a concrete
> remediation), Well-Architected notes per pillar, and open questions /
> assumptions.

## Assessment 2 — Architecture

Dispatch `expert-agents:azure-architect` with `model: "fable"` and exactly this
prompt:

> Reverse-engineer a high-level design document for an Azure estate from a live
> export. No design documentation exists for it.
>
> SCOPE — read ONLY files inside this directory:
>   C:\Users\jdk\import-duty-work\fable-arch\
>
> Do not read, glob, grep or traverse anything outside that directory. The
> directory holds twelve JSON files exported from one resource group: inventory,
> networking, private endpoints and DNS, storage, key vault, identity and role
> assignments, diagnostic settings, private-endpoint DNS zone groups, storage
> detail, and resource-scoped role assignments.
>
> Produce the document you judge most useful to an engineer inheriting this
> estate: what it appears to be for, how it is built, and anything a reader
> should know before changing it. Where you infer something no file states,
> say it is an inference and what it rests on. Include a Mermaid diagram if it
> helps.
>
> This is a description of the design, not a security review — do not produce a
> findings list.
>
> DELIVERABLE — return the full document in your reply.

## When both finish

1. Save each agent's reply **verbatim**:
   - `C:\Users\jdk\import-duty-work\fable-results\waf-review.md`
   - `C:\Users\jdk\import-duty-work\fable-results\architecture.md`
2. Write `C:\Users\jdk\import-duty-work\fable-results\run-record.md` with: this
   session's model and effort as confirmed, and for each agent its token count,
   tool-call count and duration from its completion notice.
3. Reply with one line: done, and the three paths.
