# AGENTS.md

Guidelines for AI coding agents working on `gravlift`.

## Project Overview

`gravlift` is a standalone Bash installer and update manager for **Antigravity 2.0** on Linux.

- **Entrypoint:** `gravlift` (single self-contained Bash script, zero external dependencies beyond POSIX/GNU core utilities).
- **Test Suite:** `tests/run_tests.sh` (hermetic unit test runner).
- **Build & Task Runner:** `Makefile`.

## Commands

- **Run all tests:** `make test` (or `./tests/run_tests.sh`)
- **Syntax & lint checks:** `make check` (runs `bash -n` and `shellcheck` if installed)
- **Build release archive:** `make dist` (outputs tarball and SHA-256 checksum to `dist/`)
- **Clean artifacts:** `make clean`

## Versioning Policy

- Follow standard Semantic Versioning (`MAJOR.MINOR.PATCH`, e.g., `2.0.2`):
  - **Patch (`2.0.1` -> `2.0.2`):** Bug fixes, logging adjustments, maintenance updates, minor tweaks.
  - **Minor (`2.0.2` -> `2.1.0`):** New functionality, new subcommands, new options/flags.
  - **Major (`2.x.y` -> `3.0.0`):** Breaking changes, architectural overhauls.
- Note: Upstream **Antigravity** packages also follow standard SemVer (`X.Y.Z`). Do not confuse mock Antigravity archive versions in tests with `gravlift`'s own version.
- **Single Source of Truth (SSOT):** `GRAVLIFT_VERSION` in `gravlift` is the sole source of truth for the project's version.
  - `Makefile` and `tests/run_tests.sh` dynamically parse `GRAVLIFT_VERSION` from `gravlift`.
  - `README.md` does not hardcode specific release versions in command references.
- When bumping the version number, update only `GRAVLIFT_VERSION` in `gravlift`.

## Architecture & Safety Invariants

- **Standalone Script:** Keep all runtime logic inside `gravlift`. Do not introduce external runtime dependencies beyond standard system tools (`tar`, `find`, `cut`, `uniq`, `mktemp`, `ln`, `rm`, `cp`, `realpath`).
- **Path Safety:** All destructive operations in `gravlift` must validate targets via `verify_safe_path()`. Never operate on `/`, `$HOME`, or unverified paths. User configuration (`~/.config/Antigravity`) must always be preserved during uninstallation.
- **Hermetic Testing:** All tests in `tests/run_tests.sh` must execute strictly inside the temporary sandbox directory (`/tmp/tmp.XXXXXX`) with mocked `$HOME`, `$TMPDIR`, and `$PATH`. Always use `safe_rm_rf` in tests and ensure all tests pass (`make test` and `make check`) before proposing commits.
