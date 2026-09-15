# 🚀 gravlift

`gravlift` is a smart installer and update manager for **Antigravity 2.0** on Linux. It handles binary deployment, symbolic linking, automatic updates, safety backups, and desktop integrations.

Official releases are available at [https://antigravity.google/download](https://antigravity.google/download).

---

## Key Features

* **Safe installs & updates:** Stages extractions before swapping files and creates a backup in `~/.cache/gravlift/backups/` before upgrades.
* **Desktop integration:** Creates `.desktop` application launchers and extracts icons so Antigravity shows up in your application menu.
* **Downgrade protection:** Checks version numbers before installing to prevent accidental downgrades (override with `--force`).
* **Self-managing:** Can install itself to `~/.local/bin` and provides clean uninstall commands (`app`, `self`, or `all`).
* **Standalone:** A single bash script with no external dependencies beyond standard core tools.

---

## Installation & Usage

`gravlift` supports both modern Git-style subcommands and direct backward-compatible invocations:

```bash
gravlift <command> [options] [arguments]
```

### Subcommands Overview

| Command | Description |
| :--- | :--- |
| `install` | Install Antigravity 2.0 from an archive or auto-scan Downloads |
| `update` | Scan download folders and apply available updates |
| `self-install` | Install `gravlift` to `~/opt/gravlift` and link to user bin |
| `uninstall` | Uninstall Antigravity (`app`), `gravlift` (`self`), or everything (`all`) |
| `check` | Run pre-flight diagnostics (dependencies, glibc, disk space, PATH) |
| `version` | Display `gravlift` version |
| `help` | Show command reference or detailed command help |

---

### 1. Installing Antigravity 2.0 (`install`)

Pass an archive file directly:
```bash
gravlift install ~/Downloads/Antigravity.tar.gz
```

Or omit the archive argument to automatically scan the current directory and your configured download directory (`xdg-user-dir DOWNLOAD` or `~/Downloads`):
```bash
gravlift install
```

#### Force Reinstallation or Downgrades
Use `--force` to install even if the archive version is not newer than the currently installed version:
```bash
gravlift install --force ~/Downloads/Antigravity.tar.gz
```

#### Dry Run Mode
Simulate extraction, version checks, and paths without modifying the filesystem:
```bash
gravlift install --dry-run ~/Downloads/Antigravity.tar.gz
```

---

### 2. Updating Antigravity (`update`)

Scan download directories and install newer versions automatically:
```bash
gravlift update
```

---

### 3. Pre-Flight Diagnostics (`check`)

Verify system prerequisites without installing:
```bash
gravlift check
```
Checks:
- Command dependencies (`tar`, `find`, `cut`, `uniq`, `mktemp`, `ln`, `rm`, `cp`, `realpath`)
- Minimum glibc version (>= 2.28)
- Partition disk space (>= 1 GB free)
- User bin directory presence in `$PATH`
- Installed `gravlift` version status (detects if installed copy is outdated)

---

### 4. Installing the `gravlift` Tool (`self-install`)

Install `gravlift` into `~/opt/gravlift` and symlink to `~/.local/bin/gravlift`:
```bash
gravlift self-install
```

Override default directories:
```bash
gravlift self-install --self-install-dir ~/tools/gravlift --bin-dir ~/bin
```

Configure persistent defaults in `~/.config/gravlift/config`:
```ini
SELF_INSTALL_DIR=~/opt/gravlift
BIN_DIR=~/.local/bin
AUTO_SELF_INSTALL=true   # Set to false to opt out of auto-installing gravlift during app installs
```

#### Opting Out of Auto Self-Installation
When installing Antigravity, `gravlift` automatically self-installs to your path so you can update Antigravity easily in the future. To opt out:
```bash
gravlift install --no-self-install ~/Downloads/Antigravity.tar.gz
```
Or set `AUTO_SELF_INSTALL=false` in `~/.config/gravlift/config` (or environment variable `GRAVLIFT_AUTO_SELF_INSTALL=false`).

---

### 5. Uninstallation (`uninstall`)

Cleanly remove Antigravity 2.0, the `gravlift` tool, or both:

#### Uninstall Antigravity 2.0
Removes `~/opt/antigravity`, symlink `~/.local/bin/antigravity`, desktop launcher, and icon:
```bash
gravlift uninstall app
```
*(Or simply `gravlift uninstall`)*

#### Uninstall gravlift
Removes `~/opt/gravlift` and `~/.local/bin/gravlift`:
```bash
gravlift uninstall self
```

#### Uninstall Everything & Purge
Removes Antigravity, `gravlift`, and cached backup archives:
```bash
gravlift uninstall all --purge -y
```

> [!NOTE]
> User configuration files and editor workspaces (e.g. `~/.config/Antigravity`) are always preserved to prevent accidental loss of settings and project histories.

---

### 6. Backward Compatibility

All prior invocation formats and flags continue to work seamlessly:
- Direct archive install: `gravlift Antigravity.tar.gz`
- Default update scan: `gravlift`
- Flag-based self-install: `gravlift --self-install`
- Flag-based uninstall: `gravlift --uninstall`, `gravlift --uninstall-self`, `gravlift --uninstall-all`

---

## Command Reference

| Subcommand | Options | Description |
| :--- | :--- | :--- |
| `install [archive]` | `--dry-run`, `--skip-backup`, `--force`, `--no-self-install`, `--bin-dir <dir>` | Install Antigravity from archive or scan |
| `update` | `--dry-run`, `--skip-backup`, `--force`, `--no-self-install`, `--bin-dir <dir>` | Scan downloads and apply available updates |
| `self-install` | `--dry-run`, `--self-install-dir <dir>`, `--bin-dir <dir>` | Install `gravlift` utility to `~/opt` & PATH |
| `uninstall [target]`| `app` (default), `self`, `all`, `--purge`, `-y`/`--yes`, `--dry-run` | Remove application, utility, or all |
| `check` | `--bin-dir <dir>` | Run pre-flight diagnostic checks |
| `version` | | Display version (`v2.0.1`) |
| `help [command]` | | Show help for gravlift or a specific command |

---

## Environment Setup

To run `antigravity` from any terminal, add the user binary directory to your system path:

### For Bash & Zsh
Append the following line to your shell configuration (e.g. `~/.bashrc` or `~/.zshrc`):

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Reload your shell:
```bash
source ~/.bashrc
```

### For Fish Shell
Run this command once to persist the path dynamically:

```fish
fish_add_path ~/.local/bin
```
*(Or add `set -gx PATH $HOME/.local/bin $PATH` to your `~/.config/fish/config.fish`)*

---

## Development & Testing

`gravlift` includes an automated test suite that executes inside an isolated sandbox environment without touching host configurations or files.

### Running Tests

Run via `make`:
```bash
make test
```

Or run the test script directly:
```bash
./tests/run_tests.sh
```

### Syntax & Linting

Validate shell script syntax across `gravlift` and tests:
```bash
make check
```

### How the Test Suite Works
The test runner executes **36 automated unit tests** in a clean hermetic sandbox:
- **Hermetic sandbox:** Spawns a dedicated temporary environment under `/tmp/tmp.XXXXXX` with mocked `$HOME`, `$XDG_*`, and `$PATH` directories.
- **Mocked tooling:** Simulates system utilities (`df`, `ldd`, `systemd-path`, `xdg-user-dir`, and Electron runtime environments) to test edge cases deterministically.
- **Full workflow coverage:** Verifies archive installation, version upgrades/downgrades, auto-scan update detection, desktop launchers, symlinks, safety backups, lock concurrency, opt-out mechanisms, uninstallation targets, diagnostics (`check`), and self-install upgrade detection.

---

## File Layout

The installer organizes files in user-space as follows:

```
~ (HOME)
├── opt/
│   ├── antigravity/             # Antigravity 2.0 Standalone Electron folder
│   └── gravlift/               # Installed gravlift script directory
│       └── gravlift            # Script executable
├── .local/
│   ├── bin/
│   │   ├── gravlift            # Symlink -> ~/opt/gravlift/gravlift
│   │   └── antigravity          # Symlink -> ~/opt/antigravity/antigravity
│   └── share/
│       ├── applications/
│       │   └── antigravity.desktop  # Desktop launcher for Antigravity 2.0
│       └── icons/
│           └── antigravity.png      # Extracted branding icon
└── .cache/
    └── gravlift/
        ├── backups/             # Tarball backups of previous versions
        └── gravlift.lock.dir/  # Concurrency lock folder
```
