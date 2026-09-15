---
title: Project Versioning Policy
trigger: always_on
---

# gravlift Versioning Policy

- Follow standard Semantic Versioning (`MAJOR.MINOR.PATCH`, e.g., `2.0.0`):
  - **Patch (`2.0.0` -> `2.0.1`):** Bug fixes, logging adjustments, maintenance updates, minor tweaks.
  - **Minor (`2.0.1` -> `2.1.0`):** New functionality, new subcommands, new options/flags.
  - **Major (`2.x.y` -> `3.0.0`):** Breaking changes, architectural overhauls.
- Note: Upstream **Antigravity** packages also follow standard SemVer (`X.Y.Z`).
- **Single Source of Truth (SSOT):** `GRAVLIFT_VERSION` in `gravlift` is the sole source of truth for the project's version.
  - `Makefile` and `tests/run_tests.sh` dynamically parse this variable.
  - `README.md` does not hardcode specific release versions in command references.
- When bumping the version number, update only `GRAVLIFT_VERSION` in `gravlift`.
- Ensure all automated unit tests pass (`make test`) after bumping the version number before proposing commits.
