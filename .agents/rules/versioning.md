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
- When bumping the version number, always update:
  1. `GRAVLIFT_VERSION` in `gravlift`
  2. The version reference in `README.md`
  3. The version assertions in `tests/run_tests.sh`
- Ensure all automated unit tests in `tests/run_tests.sh` pass with the updated version number before proposing commits.
