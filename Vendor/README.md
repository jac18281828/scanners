# Vendor/

Build artifacts, not committed. Everything here except this file and `patches/` is
gitignored and reproduced by `Scripts/build-sane.sh`.

```
Vendor/
├── README.md          tracked — this file
├── patches/           tracked — patches applied to upstream source at build time
├── .cache/            gitignored — downloaded, hash-verified source tarballs
├── .build/            gitignored — extract/configure/make scratch, safe to delete
├── lib/                gitignored — libsane.dylib, libusb-1.0.dylib (what the app bundles)
└── include/            gitignored — sane/sane.h, sane/saneopts.h (for the Phase 3 CSane module map)
```

Regenerate everything with:

```
Scripts/build-sane.sh
```

It's idempotent — safe to re-run; it wipes `Vendor/.build`, `Vendor/lib`, and
`Vendor/include` and rebuilds from scratch every time (tarballs are cached in
`Vendor/.cache` by verified SHA-256, so re-runs don't re-download).

## Pinned versions

- **sane-backends 1.4.0** — `https://gitlab.com/-/project/429008/uploads/843c156420e211859e974f78f64c3ea3/sane-backends-1.4.0.tar.gz`
  SHA-256 `f99205c903dfe2fb8990f0c531232c9a00ec9c2c66ac7cb0ce50b4af9f407a72`
- **libusb 1.0.30** — `https://github.com/libusb/libusb/releases/download/v1.0.30/libusb-1.0.30.tar.bz2`
  SHA-256 `fea36f34f9156400209595e300840767ab1a385ede1dc7ee893015aea9c6dbaf`

Bump these deliberately in `Scripts/build-sane.sh`, and re-verify the hash by hand
before trusting a new pin.

## Build dependencies

Installed via Homebrew, not bundled:

- `pkgconf` (`pkg-config`) — sane-backends' `configure` uses
  `PKG_CHECK_MODULES([USB], [libusb-1.0], ...)` to find our just-built,
  not-yet-installed libusb; without `pkg-config` on `PATH` it falls back to
  system/Homebrew libusb (or fails), defeating the point of vendoring.
  `Scripts/build-sane.sh` installs it automatically if missing.
- Xcode command-line tools (`clang`, `make`, `libtool`, `install_name_tool`, `otool`,
  `codesign`) — assumed present on any Mac set up to build this project.

`autoconf`/`automake` are **not** required and the script does not install them —
see "Why we hand-patch `Makefile.in`" below for why.

## The `--enable-preload` duplicate-symbol bug (sane-backends 1.4.0)

DESIGN.md decision #1 bundles SANE as a single `libsane.dylib` with the `hp5590`
backend statically linked in (`--enable-preload`), so the app needs no dlopen
path games, no `dll.conf`, no `SANE_CONFIG_DIR`. sane-backends 1.4.0's `configure`
accepts `--enable-preload` fine, but the **link** step for `libsane.la` fails with
30 duplicate-symbol errors (`_sanei_usb_open`, `_sanei_usb_read`, etc.) on both
Apple's default `ld` and `ld-classic`.

Root cause, in `backend/Makefile.am`: `libsane_la_LIBADD` includes both
`libdll_preload.la` (unconditionally, for the preload frontend) and the separate
blanket `PRELOADABLE_BACKENDS_LIBS` list. `libdll_preload.la`'s own `LIBADD`
already bundles `../sanei/sanei_usb.lo` (plus `$(USB_LIBS)` and `$(XML_LIBS)`):

```
libdll_preload_la_LIBADD = ../sanei/sanei_usb.lo \
     $(USB_LIBS) $(XML_LIBS)
```

`PRELOADABLE_BACKENDS_LIBS` lists `../sanei/sanei_usb.lo` again, unconditionally,
regardless of which backends are actually preloaded:

```
PRELOADABLE_BACKENDS_LIBS = \
    ../sanei/sanei_config2.lo \
    ../sanei/sanei_usb.lo \
    ../sanei/sanei_scsi.lo \
    ...
```

Because a libtool convenience library's own `LIBADD` objects get pulled along
wherever that `.la` is itself linked in, `../sanei/sanei_usb.lo`'s ~30 symbols
end up on the final `libsane.la` link line twice. Upstream's own comment admits
the blanket list is broader than it should be:

> ```
> # FIXME: This is using every possibly needed library and dependency
> # when the user is using any PRELOADABLE_BACKENDS, irrespective of
> # what backends are preloaded.  It should include what is needed by
> # those backends that are actually preloaded.
> ```

### The fix

`Vendor/patches/sane-backends-1.4.0-dedupe-preload-libadd.patch` removes exactly
the one redundant `../sanei/sanei_usb.lo` line from `PRELOADABLE_BACKENDS_LIBS`
(it's already supplied via `libdll_preload.la`, which is unconditional regardless
of which backends are preloaded). It does not otherwise touch the "kitchen sink"
behavior the FIXME describes — `PRELOADABLE_BACKENDS_LIBS` still links every
optional backend dependency it always did (v4l, gphoto2, poppler-glib, curl,
etc. via their own `_LIBS` variables), just without the one duplicated `.lo`.
Those unrelated optional deps are trimmed separately at `configure` time (see
below), not by this patch.

Applied by `Scripts/build-sane.sh` via `patch -p1` right after extracting the
sane-backends tarball, before `./configure`.

### Why we hand-patch `Makefile.in`, not just `Makefile.am`

The patch touches **both** `backend/Makefile.am` (the human-maintained autotools
source) and `backend/Makefile.in` (the pre-generated file the release tarball
ships, which is what `./configure && make` actually reads). Normally you'd patch
only `Makefile.am` and let `autoreconf` regenerate `Makefile.in`. We didn't,
because:

- This build environment has `libtool` and `pkgconf` but not `autoconf` or
  `automake` (confirmed via `brew list`). Installing a full autotools chain just
  to regenerate one file adds a dependency and a version-skew risk — a different
  autoconf/automake version than upstream used can rewrite far more of
  `Makefile.in` than the one line we care about, turning a reviewable one-line
  fix into a large, uncontrolled diff.
- Hand-patching both files keeps the diff exactly as narrow as the bug: one
  line removed in each. `diff -u` against pristine 1.4.0 shows nothing else
  changed.

The two edits must stay in lockstep if this patch is ever updated — the `.am`
line and the `@preloadable_backends_enabled_TRUE@`-prefixed `.in` line are the
same logical edit in two file formats.

### Timestamp note

`Scripts/build-sane.sh` extracts a fresh tarball on every run and applies the
patch with plain `patch -p1` (never `cp -R` of an already-extracted tree). This
matters: autotools' generated `Makefile` has rules like
`configure: $(am__configure_deps)` that invoke `autoconf`/`automake` (via the
`missing` script) if a source file's mtime looks newer than what it generates.
A fresh tar extraction preserves the tarball's internally-consistent timestamps;
`patch` only touches the mtime of the two files it edits, and does not disturb
`configure`, `aclocal.m4`, or `configure.ac`, so no maintainer-mode rule fires
and `autoconf`/`automake` are never invoked. (Copying an already-extracted
directory tree with `cp -R` resets every file's mtime to copy time in
unpredictable order and **does** trigger this — confirmed by hitting
`missing: line 81: autoconf: command not found` while prototyping this script.)

## Other optional deps trimmed at configure time

`--without-poppler-glib` — without it, `PRELOADABLE_BACKENDS_LIBS`' blanket
`$(POPPLER_GLIB_LIBS)` pulls in Homebrew's poppler-glib, cairo, glib, gobject,
and gettext (five Homebrew-path entries in `otool -L`), none of which hp5590
needs. `--without-libcurl`, `--without-gphoto2`, `--without-v4l` trim the rest
of the "kitchen sink" the FIXME above describes. `--without-snmp` per the phase
spec. After these, the only non-system dependency in `libsane.dylib` is our own
vendored `libusb-1.0.dylib`; the remaining `libxml2.2.dylib` reference resolves
to macOS's system copy in `/usr/lib`, not Homebrew.

## Install names

Both dylibs get `-id @rpath/<name>.dylib`, and `libsane.dylib`'s reference to
libusb is rewritten from the build-time staging path to `@rpath/libusb-1.0.dylib`
via `install_name_tool`. Both are re-signed ad-hoc (`codesign -s -`) afterward —
`install_name_tool` invalidates the existing signature, and dyld on Apple
Silicon refuses to load an unsigned-but-modified dylib even for a local ad-hoc
build.

`Scripts/build-sane.sh` verifies with `otool -L` that neither dylib references
anything under `/opt/homebrew` or `/usr/local/Cellar`/`/usr/local/opt`, and
fails the build if it finds one.
