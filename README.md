# gravlift

`gravlift` is a standalone installer and update manager for **Antigravity 2.0** on Linux. It handles binary deployment, symbolic linking, automatic updates, safety backups, and GNOME desktop integration in user space (`~/opt` and `~/.local/bin`).

Official **Antigravity 2.0** releases: [https://antigravity.google/download](https://antigravity.google/download)

## Features

- **Safe installs & updates:** Extracts and validates releases in a staging directory and backs up existing installations to `~/.cache/gravlift/backups/` before swapping.
- **Desktop integration:** Generates `.desktop` application launchers and extracts icons (`app.asar` fallback supported).
- **Downgrade protection:** Compares semantic versions before upgrading (override with `--force`).
- **Self-managing:** Installs itself to `~/.local/bin/gravlift` and provides clean `uninstall` targets (`app`, `self`, or `all`).
- **Zero dependencies:** Single Bash script using standard POSIX/GNU core utilities.

## Quick Start

### 1. Install `gravlift`

```bash
git clone https://github.com/thom/gravlift.git
cd gravlift
make install   # or: ./gravlift self-install
```

Or download the script directly:
```bash
curl -fsSL https://raw.githubusercontent.com/thom/gravlift/main/gravlift -o gravlift
chmod +x gravlift
./gravlift self-install
```

### 2. Install or Update Antigravity 2.0

Download the Linux `.tar.gz` archive from [antigravity.google/download](https://antigravity.google/download) to `~/Downloads`, then run:

```bash
gravlift install
```

## Usage

```bash
gravlift <command> [options]
```

| Command | Options | Description |
| :--- | :--- | :--- |
| `install [archive]` | `--dry-run`, `--skip-backup`, `--force`, `--no-self-install`, `--bin-dir <dir>` | Install Antigravity from an archive or scan `~/Downloads` |
| `update` | `--dry-run`, `--skip-backup`, `--force`, `--no-self-install`, `--bin-dir <dir>` | Scan download directories and install newer versions |
| `self-install` | `--dry-run`, `--self-install-dir <dir>`, `--bin-dir <dir>` | Install `gravlift` to `~/opt/gravlift` and symlink to PATH |
| `uninstall [target]`| `app` (default), `self`, `all`, `--purge`, `-y`/`--yes`, `--dry-run` | Remove Antigravity, `gravlift`, or both |
| `check` | `--bin-dir <dir>` | Run pre-flight checks (dependencies, glibc, disk space, PATH) |
| `version` | | Display `gravlift` version |
| `help [command]` | | Show general or command-specific help |

### Common Examples

```bash
# Install a specific archive
gravlift install ~/Downloads/Antigravity.tar.gz

# Preview an update without modifying files
gravlift update --dry-run

# Uninstall Antigravity (preserves user settings in ~/.config/Antigravity)
gravlift uninstall app

# Uninstall Antigravity, gravlift, and cached backups
gravlift uninstall all --purge -y
```

### Configuration (Optional)

Persistent defaults can be set in `~/.config/gravlift/config`:

```ini
SELF_INSTALL_DIR=~/opt/gravlift
BIN_DIR=~/.local/bin
AUTO_SELF_INSTALL=true
```

## File Layout

```text
~ (HOME)
├── opt/
│   ├── antigravity/             # Antigravity 2.0 installation
│   └── gravlift/                # Installed gravlift script
├── .local/
│   ├── bin/
│   │   ├── antigravity          # Symlink -> ~/opt/antigravity/antigravity
│   │   └── gravlift             # Symlink -> ~/opt/gravlift/gravlift
│   └── share/
│       ├── applications/antigravity.desktop
│       └── icons/antigravity.png
└── .cache/gravlift/backups/     # Automatic pre-upgrade backups
```

## Development

```bash
make test    # Run the 36-test hermetic test suite
make check   # Validate shell syntax (bash -n / shellcheck)
make dist    # Build release tarball and SHA-256 checksum in dist/
```

## License

Released under the [MIT License](LICENSE).
