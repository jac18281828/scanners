# Scanners — Orchestration State

Machine-readable progress ledger. The orchestrator reads this file first on every
(re)start and updates it after every gate. Commit it with each phase. Never delete
history — append.

## Phase status

Legend: `todo` | `in-progress` | `review` | `done` | `blocked(<reason>)`

| Phase | Prompt | Status | Commit | Review verdict |
|-------|--------|--------|--------|----------------|
| 1 Scaffold | prompts/01-scaffold.md | in-progress | — | — |
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
