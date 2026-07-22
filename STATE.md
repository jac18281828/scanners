# Scanners — Orchestration State

Machine-readable progress ledger. The orchestrator reads this file first on every
(re)start and updates it after every gate. Commit it with each phase. Never delete
history — append.

## Phase status

Legend: `todo` | `in-progress` | `review` | `done` | `blocked(<reason>)`

| Phase | Prompt | Status | Commit | Review verdict |
|-------|--------|--------|--------|----------------|
| 1 Scaffold | prompts/01-scaffold.md | done | 21468556b7cdf91676a2b43df53467b523cd92ab | pass (plan-critic, non-blocking notes only) |
| 2 SANE vendor | prompts/02-sane-vendor.md | todo | — | — |
| 3 ScannerKit | prompts/03-scannerkit.md | todo | — | — |
| 4 OutputKit | prompts/04-output-pipeline.md | todo | — | — |
| 5 App UI | prompts/05-app-ui.md | todo | — | — |
| 6 Packaging | prompts/06-packaging.md | todo | — | — |
| 7 Validation | prompts/07-validation.md | todo | — | — |

## Resume notes

(Orchestrator: when pausing, append a dated entry here — what was in flight, what the
next action is, any uncommitted state and where it lives.)

- 2026-07-22: Project initialized. Design + prompts authored by architect (Fable).
  Hardware pre-validated: HP 4570c scans via SANE hp5590 backend on this Mac
  (sane-backends 1.4.0 via brew — dev convenience only; app bundles its own).

## Open questions for John

(Orchestrator: append here when blocked on a decision; mark resolved with the answer.)

- none

## Decision log

(Orchestrator: append one line per notable decision made during implementation.)

- 2026-07-22: Phase 1 landed. Repo `jac18281828/scanners` created PUBLIC per John's explicit
  approval (asked via AskUserQuestion before dispatch, since public-repo creation is a
  visible/hard-to-reverse action). CI green (run 29930974176), all local gates verified
  independently by the orchestrator (not just the implementer's report).
- 2026-07-22: `.swiftlint.yml` uses a curated ~40-rule `opt_in_rules` list instead of
  `opt_in_rules: all`, because `all` pulls in `contrasted_opening_brace` (Allman braces)
  and `explicit_type_interface`, both of which fight swift-format's K&R/inference style.
  Adversarial review confirmed this is a reasonable "strict-but-sane" call, not a
  weakening — no correctness rule was dropped.
- 2026-07-22: Known non-blocking follow-up (not gate-blocking, deferred): `.swiftlint.yml`
  declares `analyzer_rules` (unused_import, unused_declaration) that CI never runs, since
  CI uses `swiftlint lint --strict` not `swiftlint analyze`. Either wire up an analyze step
  or drop the block in a later phase.
