# Act 5a criteria — design-then-import

**Written before the run, deliberately.** The hypothesis is mine, so the
temptation to grade it generously is real. These criteria are fixed now.

## The hypothesis

Writing the configuration first and binding reality into it with native
`import` blocks avoids, *by construction*, the two defect classes that
`aztfexport` produced in Act 2 — because a human (or agent) writing config
declares intent, whereas a generator can only transcribe state.

## The gate

`terraform plan` reports the resources **to import**, with **0 to add, 0 to
change, 0 to destroy**.

Binary. `to add` means the config does not describe what exists. `to change`
means a value was captured wrongly. Neither is explainable away.

Plan-only: no state is written, nothing in Azure is touched. Import blocks are
evaluated at plan time, which is what makes this test free.

## Defect class 1 — literal where a reference belonged

Act 2 emitted `principal_id = "<literal GUID>"`, pinning the role assignment to the
source estate's identity. Act 4 proved a fresh apply would have granted
Contributor on a new resource group to the old estate's identity.

**Avoided** if the role assignment's principal is a resource reference and no
literal principal GUID appears anywhere in the config.

**Not avoided** if a literal appears, whatever the justification.

## Defect class 2 — Azure-managed values captured as user config

Act 2 emitted the private DNS A record's `creator` tag (carrying the private
endpoint's resource GUID) and its runtime-allocated IP as though both were
authored. Only a live apply into a fresh environment surfaced it.

**Avoided** if neither the source estate's PE GUID nor a pinned IP appears as an
authored value. An explicit `lifecycle { ignore_changes = … }` with a stated
reason counts as avoided — that is a declaration of intent, which is exactly the
distinction being tested.

**Not avoided** if either value is written as configuration.

## Scoring the approach, not just the output

Three things matter beyond pass/fail, and a PASS that ignores them is not
interesting:

1. **Effort.** Act 2 cost 147k tokens and 74 tool calls end to end. If this path
   costs materially more for nine resources, that is the finding — it does not
   scale to four hundred, whatever its correctness advantages.
2. **The azapi question.** The Act 5 refactor rejected four AVM modules because
   they implement via `azapi_resource`, blocking `moved` blocks. Importing is a
   *different* operation from moving. Whether the same constraint applies is
   genuinely unknown and the answer is useful either way.
3. **Where it was awkward.** Module-internal addresses must be read from module
   source. If that is painful for four modules, it is prohibitive for forty.

## What a FAIL would mean

Not that the approach is wrong — that it costs more than stated, or that
Terraform's import-block support has gaps for these resource types. Either is
worth knowing before recommending it for client work.

## What would falsify the hypothesis outright

A plan showing `to change` on the A record or the role assignment. That would
mean designing first did **not** avoid the defect classes, and the difference
between the two approaches is smaller than argued.
