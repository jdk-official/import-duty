# Run record — Fable + Max assessment run

Date: 2026-09-19. Brief: `C:\Users\jdk\import-duty-work\fable-brief.md`.

## Session (confirmed before dispatch)

| Field | Value | Source |
|---|---|---|
| Model | `claude-fable-5-1` | `get_session("self")` |
| Effort | `max` | `get_session("self")` |
| Fast mode | off | `get_session("self")` |
| Session created | 2026-09-19T11:53:38Z | `get_session("self")` |

Subagents inherit the session effort. The completion notices do not report effort, so the subagents' effort was not independently observed.

## Dispatch

- Both agents: `expert-agents:azure-architect`, `model: "fable"`, prompts exactly as written in the brief.
- Launched in parallel in a single message, background mode, at about 2026-09-19T11:54:33Z (task-file timestamps).
- `model: "fable"` is per the brief; it overrides the `opus` tier this agent normally gets.

## Agents (from their completion notices)

| Assessment | Saved reply | Status | Tokens | Tool calls | Duration |
|---|---|---|---|---|---|
| 1 — Well-Architected review | `waf-review.md` | completed | 264,573 | 29 | 750,109 ms (12 min 30 s) |
| 2 — Architecture | `architecture.md` | completed | 203,551 | 29 | 860,600 ms (14 min 21 s) |

## Fidelity notes

- Replies were saved from the `<result>` text of each completion notice, whole, including the architecture reply's one-sentence preamble.
- The notice envelope XML-escapes `<` and `>`: Mermaid arrows arrived as `--&gt;` and label line breaks as `&lt;br/&gt;`. The saved files restore the literal characters. Affected text: `waf-review.md`, one line in C2 (`<acct>`, `<rg>`); `architecture.md`, the Mermaid block in section 3 and `<type>` in section 8. No other edits. Checked after saving: no `&lt;`, `&gt;` or `&amp;` remains in either file.
- The subagent transcripts were not available (task output files were 0 bytes), so the saved text could not be byte-compared with the raw replies, and each agent's adherence to its read scope is self-reported in its reply. Both replies state that one oversized Learn fetch was auto-saved by the tool outside the scoped directory and was not opened.
- This session read nothing under `C:\Users\jdk\import-duty\`, wrote only to `fable-results\`, and made no Azure calls.
