# Phase 1 — Repo scaffold, CI, quality gates

You are implementing Phase 1 of the Scanners project. Read `DESIGN.md` at the repo root
first; it is the authority. Working directory: `/Users/john/src/scanners`.

## Tasks

1. `git init` in the current directory (it is not yet a repo). First commit includes the
   existing `DESIGN.md`, `STATE.md`, and `prompts/` — these are project artifacts, keep them.
2. Add `LICENSE` — BSD-3-Clause, copyright 2026 John (use the name from `git config user.name`).
3. Create the SwiftPM package `Scanners`:
   - Targets: `ScannersApp` (executable), `ScannerKit` (library), `OutputKit` (library),
     plus test targets `ScannerKitTests`, `OutputKitTests`.
   - Swift 6 language mode, macOS 14+ platform, arm64.
   - Stub source files that compile and one trivial passing test per test target.
4. Tooling config, enforced not decorative:
   - `.swift-format` (Apple swift-format) and `.swiftlint.yml`. Pick strict-but-sane rules;
     no disabled-by-default free-for-all. `swiftlint` installable via brew in CI.
   - `.gitignore` for Swift/Xcode/macOS.
5. `.github/workflows/ci.yml`: on push/PR — macOS arm64 runner (`macos-15` or newer),
   `swift build`, `swift test`, `swiftlint --strict`, `swift-format lint --strict`.
6. `README.md` stub: one-paragraph description, badge for CI, "Getting Started" placeholder
   noting binary install lands in a later phase.
7. Create the GitHub repo: `gh repo create scanners --public --source . --push`
   (gh is authenticated). Confirm CI goes green on the pushed commit.

## Out of scope

No SANE code, no UI beyond stubs, no release workflow. Do not touch `prompts/` content.

## Acceptance gates (all must pass before you report done)

- `swift build && swift test` clean locally.
- `swiftlint --strict` and `swift-format lint --strict` clean.
- GitHub repo exists, CI workflow run is green (verify with `gh run watch` / `gh run list`).
- `LICENSE` is verbatim BSD-3-Clause.

## Escalation

If the arm64 GitHub runner label or tool availability differs from expectations, fix
forward with the closest equivalent and note it in your report. Anything that would change
DESIGN.md decisions: stop and report instead of improvising.
