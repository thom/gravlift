# 🚀 gravlift

`gravlift` is a smart installer and update manager for **Antigravity 2.0** (Electron agent orchestrator) and **Antigravity IDE** (VS Code development suite fork) on Linux. It handles binary deployment, symbolic linking, automatic updates, safety backups, and desktop integrations.

---

## Key Features

* **Atomic Directory Swap:** Installs are staged in `.new` folders and swapped atomically to prevent leaving files in a corrupted state if interrupted.
* **Automatic Backups:** Before replacing an existing installation, a gzip compressed tarball backup is created under `~/.cache/gravlift/backups/`.
* **Zero-Race Concurrency Locks:** Uses atomic directory locks to prevent parallel executions of `gravlift` from corrupting your installation paths.
* **Gnome Launcher Integration:** Creates compliant `.desktop` shortcuts under `~/.local/share/applications/` and extracts app branding icons to `~/.local/share/icons/` so they appear in your app launcher menu instantly.
* **Smart Binary Depth Routing:** Dynamically parses complex portable app structures (like VS Code layout wrappers) and routes symlinks to the shallowest executable path.
* **Advanced Version Logic:** Reads unpacked JSON package specifications or runs the Electron runtime headlessly to dynamically query versions packaged inside `.asar` files, blocking downgrades unless overridden.
* **POSIX Compliance & Portability:** Written using safe shell patterns that run correctly on standard GNU/Busybox/POSIX setups without failing under strict `pipefail` settings.

---

## Installation & Usage

### 1. Automatic Archive Scan
If run without arguments, `gravlift` queries XDG user directories and scans the current directory and your downloads directory (e.g. `~/Downloads` or `~/inbox`) for archives matching `*antigravity*.tar.gz` (case-insensitively).

```bash
./gravlift
```

### 2. Manual Archive Specification
You can pass target `.tar.gz` archives directly:

```bash
./gravlift ~/Downloads/Antigravity.tar.gz ~/Downloads/Antigravity_IDE.tar.gz
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

---

## CLI Options Reference

| Option | Alias | Description |
| :--- | :--- | :--- |
| `-h` | `--help` | Display usage instructions and exit |
| `-v` | `--version` | Display `gravlift` script version and exit |
| | `--dry-run` | Run pre-flight checks and simulate installation without altering files |
| | `--skip-backup` | Skip compressing a backup of the existing version before overwriting |
| | `--force` | Force update/downgrade even if the target version is not newer |

---

## Environment Setup

To run `antigravity` or `antigravity-ide` from any terminal, add the user binary directory to your system path:

### For Bash & Zsh
Append the following line to your shell configuration (e.g. `~/.bashrc` or `~/.zshrc`):

```bash
export PATH="$HOME/opt/bin:$PATH"
```

Reload your shell:
```bash
source ~/.bashrc
```

### For Fish Shell
Run this command once to persist the path dynamically:

```fish
fish_add_path ~/opt/bin
```
*(Or add `set -gx PATH $HOME/opt/bin $PATH` to your `~/.config/fish/config.fish`)*

---

## Testing the Installer

`gravlift` includes a comprehensive unit testing suite that executes inside an isolated sandbox environment.

### Run tests:
```bash
./tests/run_tests.sh
```

The test runner will create temporary directories, mock tools like `df`, `ldd`, and `xdg-user-dir`, generate dummy tarball layouts, and execute 16 test cases covering CLI flags, version checks, locks, traps, and fallback logic.

---

## File Layout

The installer organizes files in user-space as follows:

```
~ (HOME)
├── opt/
│   ├── antigravity/             # Antigravity 2.0 Standalone Electron folder
│   ├── antigravity-ide/         # Antigravity IDE VS Code fork folder
│   └── bin/
│       ├── gravlift            # Self-installed copy of this installer script
│       ├── antigravity          # Symlink to opt/antigravity/antigravity
│       └── antigravity-ide      # Symlink to opt/antigravity-ide/antigravity-ide
├── .local/share/
│   ├── applications/
│   │   ├── antigravity.desktop  # Desktop launcher for standard app
│   │   └── antigravity-ide.desktop # Desktop launcher for IDE
│   └── icons/
│       ├── antigravity.png      # Extracted branding icon
│       └── antigravity-ide.png  # Extracted IDE branding icon
└── .cache/
    └── gravlift/
        ├── backups/             # Tarball backups of previous versions
        └── gravlift.lock.dir/  # Concurrency lock folder
```
