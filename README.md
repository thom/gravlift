# 🚀 gravlift

`gravlift` is a smart installer and update manager for **Antigravity 2.0** on Linux. It handles binary deployment, symbolic linking, automatic updates, safety backups, and desktop integrations.

Official releases are available at [https://antigravity.google/download](https://antigravity.google/download).

---

## Key Features

* **Atomic Directory Swap:** Installs are staged in `.new` folders and swapped atomically to prevent leaving files in a corrupted state if interrupted.
* **Automatic Backups:** Before replacing an existing installation, a gzip compressed tarball backup is created under `~/.cache/gravlift/backups/`.
* **Zero-Race Concurrency Locks:** Uses atomic directory locks to prevent parallel executions of `gravlift` from corrupting your installation paths.
* **Gnome Launcher Integration:** Creates compliant `.desktop` shortcuts under `~/.local/share/applications/` and extracts app branding icons to `~/.local/share/icons/` so they appear in your app launcher menu instantly.
* **Smart Binary Depth Routing:** Dynamically parses complex portable app structures (like wrapper scripts) and routes symlinks to the shallowest executable path.
* **Advanced Version Logic:** Reads unpacked JSON package specifications or runs the Electron runtime headlessly to dynamically query versions packaged inside `.asar` files, blocking downgrades unless overridden.
* **POSIX Compliance & Portability:** Written using safe shell patterns that run correctly on standard GNU/Busybox/POSIX setups without failing under strict `pipefail` settings.

---

## Installation & Usage

### 1. Automatic Archive Scan
If run without arguments, `gravlift` queries your configured download directory via `xdg-user-dir DOWNLOAD` (falling back to `~/Downloads`). It scans both the current working directory and that download folder for archives matching `*antigravity*.tar.gz` (case-insensitively).

```bash
./gravlift
```

### 2. Manual Archive Specification
You can also pass the target `.tar.gz` archive directly:

```bash
./gravlift ~/Downloads/Antigravity.tar.gz
```

### 3. Force Reinstallation or Downgrades
Use the `--force` flag to overwrite or downgrade installations:

```bash
./gravlift --force ~/Downloads/Antigravity.tar.gz
```

### 4. dry-run Mode
Simulate all verification steps, version checks, and routing destinations without writing any changes:

```bash
./gravlift --dry-run ~/Downloads/Antigravity.tar.gz
```

### 5. Installing the `gravlift` Tool
You can install `gravlift` itself as a system command without installing an archive:

```bash
./gravlift --self-install
```

By default, the script executable is placed in `~/opt/gravlift/gravlift` and a symlink is created in your user binary directory (`~/.local/bin/gravlift`, discovered dynamically via `systemd-path user-binaries`).

You can override these locations with flags:
```bash
./gravlift --self-install --self-install-dir ~/tools/gravlift --bin-dir ~/bin
```

Or configure defaults in `~/.config/gravlift/config`:
```ini
SELF_INSTALL_DIR=~/opt/gravlift
BIN_DIR=~/.local/bin
AUTO_SELF_INSTALL=true   # Set to false to opt out of auto-installing gravlift during app installs
```

#### Opting Out of Automatic Self-Installation
When installing Antigravity, `gravlift` automatically self-installs to your path so you can update Antigravity easily in the future. To opt out, pass `--no-self-install`:

```bash
./gravlift --no-self-install
```
Or set `AUTO_SELF_INSTALL=false` in `~/.config/gravlift/config` (or environment variable `GRAVLIFT_AUTO_SELF_INSTALL=false`).

---

## CLI Options Reference

| Option | Alias | Description |
| :--- | :--- | :--- |
| `-h` | `--help` | Display usage instructions and exit |
| `-v` | `--version` | Display `gravlift` script version and exit |
| | `--dry-run` | Run pre-flight checks and simulate operations without altering files |
| | `--skip-backup` | Skip compressing a backup of the existing version before overwriting |
| | `--force` | Force update/downgrade even if the target version is not newer |
| | `--self-install` | Install `gravlift` to `~/opt/gravlift` and link to user bin directory |
| | `--no-self-install` | Opt out of installing/updating `gravlift` itself during app installations |
| | `--self-install-dir <dir>` | Override self-installation directory (default: `~/opt/gravlift`) |
| | `--bin-dir <dir>` | Override user binary directory (default: `~/.local/bin`) |

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

## Testing the Installer

`gravlift` includes a comprehensive unit testing suite that executes inside an isolated sandbox environment.

### Run tests:
```bash
./tests/run_tests.sh
```

The test runner will create temporary directories, mock tools like `df`, `ldd`, `systemd-path`, and `xdg-user-dir`, generate dummy tarball layouts, and execute 22 test cases covering CLI flags, self-installation, opt-out mechanisms, version checks, locks, traps, and fallback logic.

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
