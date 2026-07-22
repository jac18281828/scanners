# Phase 6 — Packaging, signing, release pipeline, README

You are implementing Phase 6 of the Scanners project. Read `DESIGN.md` first. Repo:
`/Users/john/src/scanners`. Phases 1–5 done: working app via `swift run`, vendored SANE
build script, CI green.

## Tasks

1. **`Scripts/make-app.sh`** — assemble `build/Scanners.app`:
   - `swift build -c release --arch arm64`.
   - Bundle layout: executable → `Contents/MacOS/Scanners`; vendored dylibs →
     `Contents/Frameworks/`; `Info.plist` (bundle id `com.2ad.scanners`, version from
     git tag/describe, `LSMinimumSystemVersion`, `NSHumanReadableCopyright` BSD-3);
     app icon — generate a clean scanner glyph icon set with `iconutil` (simple, flat,
     no clip-art; an SF-symbol-derived design rendered to icns is fine).
   - `install_name_tool` so the executable resolves dylibs via
     `@executable_path/../Frameworks`; verify with `otool -L` and a launch from a path
     containing spaces.
   - Codesign: every dylib then the app. Ad-hoc (`-`) by default; if
     `CODESIGN_IDENTITY` env is set, use it and enable hardened runtime + timestamp
     (Developer ID arrives later — the script must already support it).
2. **`Scripts/make-dist.sh`** — zip the .app (`ditto -c -k --keepParent`) as
   `Scanners-<version>-arm64.zip`.
3. **`.github/workflows/release.yml`** — on tag `v*`: build vendored SANE (cached),
   make-app, make-dist, create GitHub Release with the zip and generated notes. If
   signing secrets (`MACOS_CERT_P12`, `MACOS_CERT_PASSWORD`, `APPLE_TEAM_ID`,
   `NOTARY_*`) exist, import cert, sign with Developer ID, notarize + staple; otherwise
   ad-hoc. The workflow must be green in ad-hoc mode today.
4. **README.md** — the real one:
   - What it is, screenshot (take one of the actual app, commit under `Docs/`).
   - **Install**: download zip from Releases → unzip → drag to Applications →
     first-launch right-click → Open (explain the one-time Gatekeeper step for ad-hoc
     builds, with the `xattr -dr com.apple.quarantine /Applications/Scanners.app`
     alternative). Plug in scanner, launch, scan. No brew, no drivers.
   - Supported hardware (HP 4570c validated; other hp5590-backend models likely work:
     4500C/5500C/5550C/5590/7650), build-from-source section, license.
5. Cut **v0.1.0**: tag, let release.yml produce the artifact, download that artifact
   fresh (simulating a user), install to `/Applications`, launch, and do a real scan.

## Acceptance gates

- Fresh-download install test passes on this Mac: unquarantined via documented steps,
  launches from /Applications, finds scanner, scans, saves a PDF.
- `otool -L Contents/MacOS/Scanners` shows no Homebrew or build-tree paths.
- Release workflow run green; release v0.1.0 public with the zip attached.
- README install steps executed literally, not aspirationally.

## Escalation

If ad-hoc signed app + bundled dylibs hit a Gatekeeper/AMFI wall that right-click-open
doesn't clear, stop and report the exact error — options (no hardened runtime, removing
quarantine, early Developer ID) are John's call.
