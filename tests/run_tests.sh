#!/usr/bin/env bash

# run_tests.sh - Comprehensive unit tests for gravlift installer
# Follows shell script testing best practices.

set -euo pipefail

# Locate workspace root and installer script
WORKSPACE_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
GRAVLIFT_PATH="$WORKSPACE_ROOT/gravlift"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Test suite status
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Create a master sandbox directory for the test execution
SANDBOX_DIR=$(mktemp -d)

# Hard guard to prevent deleting anything outside SANDBOX_DIR
safe_rm_rf() {
    local target="$1"
    if [ -z "$target" ]; then
        echo "CRITICAL SAFETY: Refusing to delete empty path." >&2
        exit 1
    fi
    # Block root, user homes, system dirs
    if [[ "$target" == "/" || "$target" == "/home" || "$target" == "/home/"* || "$target" == "/etc"* || "$target" == "/usr"* ]]; then
        echo "CRITICAL SAFETY: Refusing to delete system or home path '$target'." >&2
        exit 1
    fi
    # STRICT ENFORCEMENT: Target MUST be inside $SANDBOX_DIR
    if [[ "$target" != "$SANDBOX_DIR"* ]]; then
        echo "CRITICAL SAFETY: Refusing to delete path outside sandbox '$SANDBOX_DIR': '$target'." >&2
        exit 1
    fi
    rm -rf "$target"
}

# Register cleanup trap for the master sandbox
cleanup_master_sandbox() {
    if [[ -n "$SANDBOX_DIR" && "$SANDBOX_DIR" == "/tmp/"* && -d "$SANDBOX_DIR" ]]; then
        rm -rf "$SANDBOX_DIR"
    fi
}
trap cleanup_master_sandbox EXIT

# Set up sandbox paths
TEST_HOME="$SANDBOX_DIR/home"
MOCK_BIN="$SANDBOX_DIR/bin"
MOCK_ARCHIVES="$SANDBOX_DIR/archives"
MOCK_TMP="$SANDBOX_DIR/tmp"

mkdir -p "$TEST_HOME" "$MOCK_BIN" "$MOCK_ARCHIVES" "$MOCK_TMP"

# Export environments to sandbox the execution
export HOME="$TEST_HOME"
export TMPDIR="$MOCK_TMP"

# Verify sandbox invariants immediately before executing any tests
if [[ -z "$SANDBOX_DIR" || "$SANDBOX_DIR" != "/tmp/"* || ! -d "$SANDBOX_DIR" ]]; then
    echo "CRITICAL SAFETY: Invalid sandbox directory '$SANDBOX_DIR'. Aborting immediately." >&2
    exit 1
fi
if [[ "$HOME" != "$SANDBOX_DIR/home" ]]; then
    echo "CRITICAL SAFETY: HOME does not point to sandbox directory: '$HOME'. Aborting immediately." >&2
    exit 1
fi

# Variables for the last executed command state
LAST_EXIT_CODE=0
LAST_OUTPUT=""
LAST_OUTPUT_FILE="$SANDBOX_DIR/last_output.log"

# --- Mocking Helpers ---

# Set mock df output
set_mock_df() {
    local kb_avail="$1"
    cat > "$MOCK_BIN/df" <<EOF
#!/usr/bin/env bash
echo "Filesystem     1K-blocks      Used Available Use% Mounted on"
echo "/dev/mock      200000000 100000000 $kb_avail  50% /"
EOF
    chmod +x "$MOCK_BIN/df"
}

# Set mock ldd version
set_mock_ldd() {
    local glibc_ver="$1"
    cat > "$MOCK_BIN/ldd" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "--version" ]; then
    echo "ldd (GNU libc) $glibc_ver"
else
    # Fallback to system ldd bypassing MOCK_BIN to prevent recursion
    local sys_ldd
    sys_ldd=\$(PATH="\${PATH//"$MOCK_BIN:"/}" type -P ldd || true)
    if [ -n "\$sys_ldd" ]; then
        "\$sys_ldd" "\$@"
    fi
fi
EOF
    chmod +x "$MOCK_BIN/ldd"
}

# Set mock xdg-user-dir download directory
set_mock_xdg_user_dir() {
    local download_dir="$1"
    cat > "$MOCK_BIN/xdg-user-dir" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "DOWNLOAD" ]; then
    echo "$download_dir"
else
    echo "\$HOME"
fi
EOF
    chmod +x "$MOCK_BIN/xdg-user-dir"
}

# Set mock systemd-path output
set_mock_systemd_path() {
    local user_bin="$1"
    cat > "$MOCK_BIN/systemd-path" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "user-binaries" ]; then
    echo "$user_bin"
else
    echo "\$HOME/.local/bin"
fi
EOF
    chmod +x "$MOCK_BIN/systemd-path"
}

# Restore default mocks
reset_mocks() {
    safe_rm_rf "$MOCK_BIN"
    mkdir -p "$MOCK_BIN"
    # 2GB available (plenty of space)
    set_mock_df 2097152
    # Glibc 2.35 (compatible)
    set_mock_ldd 2.35
    # Default Downloads directory
    set_mock_xdg_user_dir "$TEST_HOME/Downloads"
    # Mock update-desktop-database to isolate tests from host environment
    echo '#!/usr/bin/env bash' > "$MOCK_BIN/update-desktop-database"
    chmod +x "$MOCK_BIN/update-desktop-database"
    # Mock systemd-path
    set_mock_systemd_path "$TEST_HOME/.local/bin"
}

# --- Mock Archive Generator ---

# Creates a mock application tarball (e.g. "antigravity" or foreign app)
create_mock_archive() {
    local type="$1"       # executable name (e.g. "antigravity" or "other-app")
    local dest_path="$2"  # output archive path
    local version="$3"    # version inside package.json
    local layout="${4:-standard}" # "standard", "nested", or "no-json"

    local temp_build_dir
    temp_build_dir=$(mktemp -d "$MOCK_TMP/build_tarball.XXXXXX")
    
    local app_dir="$temp_build_dir/extracted"
    mkdir -p "$app_dir"

    # Define binary name
    local exe_name="$type"

    # Create directory layout
    local run_dir="$app_dir"
    if [ "$layout" = "nested" ]; then
        # VS Code layouts might have a nested binary but a shallow wrapper
        mkdir -p "$app_dir/bin"
        run_dir="$app_dir/bin"
        
        # Create shallow script wrapper
        cat > "$app_dir/$exe_name" <<EOF
#!/usr/bin/env bash
# Wrapper script
exec "\$(dirname "\$0")/bin/$exe_name" "\$@"
EOF
        chmod +x "$app_dir/$exe_name"
    fi

    # Write the mock executable that supports head-less Node execution (-e)
    # for icon extraction and package.json reading inside app.asar.
    cat > "$run_dir/$exe_name" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "-e" ]; then
    # Headless Node simulation
    # If it contains fs.copyFileSync, extract destination path and create empty mock png
    if [[ "\$2" == *"fs.copyFileSync"* ]]; then
        dest=\$(echo "\$2" | grep -oE "'[^']+\.png'" | tail -n 1 | tr -d "'")
        if [ -n "\$dest" ]; then
            mkdir -p "\$(dirname "\$dest")"
            echo "mock icon data" > "\$dest"
        fi
    elif [[ "\$2" == *"package.json"* ]]; then
        echo "$version"
    fi
fi
echo "Mock Antigravity App executed"
EOF
    chmod +x "$run_dir/$exe_name"

    # Write package.json if not "no-json"
    if [ "$layout" != "no-json" ]; then
        # Create package.json or app.asar to simulate version information
        mkdir -p "$app_dir/resources/app"
        cat > "$app_dir/resources/app/package.json" <<EOF
{
  "name": "$exe_name",
  "version": "$version"
}
EOF
    fi

    # If it's standard Antigravity, also create a mock app.asar file to test asar fallback logic
    if [ "$type" = "antigravity" ]; then
        mkdir -p "$app_dir/resources"
        echo "mock app.asar content" > "$app_dir/resources/app.asar"
        # We can also put a mock icon in the resources directory
        echo "mock icon" > "$app_dir/resources/icon.png"
    fi

    # Pack the archive
    tar -czf "$dest_path" -C "$temp_build_dir" extracted
    safe_rm_rf "$temp_build_dir"
}

# --- Assertion Helpers ---

assert_success() {
    if [ "$LAST_EXIT_CODE" -ne 0 ]; then
        echo -e "  ${RED}FAIL:${NC} Expected exit code 0, but got $LAST_EXIT_CODE"
        echo -e "  Output was:\n$LAST_OUTPUT"
        return 1
    fi
    return 0
}

assert_failure() {
    local expected_code="${1:-}"
    if [ "$LAST_EXIT_CODE" -eq 0 ]; then
        echo -e "  ${RED}FAIL:${NC} Expected command to fail, but it succeeded"
        return 1
    fi
    if [ -n "$expected_code" ] && [ "$LAST_EXIT_CODE" -ne "$expected_code" ]; then
        echo -e "  ${RED}FAIL:${NC} Expected exit code $expected_code, but got $LAST_EXIT_CODE"
        echo -e "  Output was:\n$LAST_OUTPUT"
        return 1
    fi
    return 0
}

assert_output_contains() {
    local substring="$1"
    if [[ "$LAST_OUTPUT" != *"$substring"* ]]; then
        echo -e "  ${RED}FAIL:${NC} Output did not contain expected text: '${substring}'"
        echo -e "  Output was:\n$LAST_OUTPUT"
        return 1
    fi
    return 0
}

assert_file_exists() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo -e "  ${RED}FAIL:${NC} File does not exist: $file"
        return 1
    fi
    return 0
}

assert_file_not_exists() {
    local file="$1"
    if [ -f "$file" ]; then
        echo -e "  ${RED}FAIL:${NC} File should NOT exist: $file"
        return 1
    fi
    return 0
}

assert_link_exists() {
    local link="$1"
    local target="${2:-}"
    if [ ! -L "$link" ]; then
        echo -e "  ${RED}FAIL:${NC} Link does not exist: $link"
        return 1
    fi
    if [ -n "$target" ]; then
        local real_target
        real_target=$(readlink -f "$link")
        if [ "$real_target" != "$target" ]; then
            echo -e "  ${RED}FAIL:${NC} Link points to $real_target, but expected $target"
            return 1
        fi
    fi
    return 0
}

# --- Test Runner Core ---

run_gravlift() {
    # Run the gravlift script with prepended mock bin path inside test home directory
    set +e
    (
        cd "$TEST_HOME"
        PATH="$MOCK_BIN:$PATH" bash "$GRAVLIFT_PATH" "$@" < /dev/null
    ) > "$LAST_OUTPUT_FILE" 2>&1
    LAST_EXIT_CODE=$?
    set -e
    LAST_OUTPUT=$(cat "$LAST_OUTPUT_FILE")
}

setup() {
    # Clean and recreate home directory and mock files
    safe_rm_rf "$TEST_HOME"
    mkdir -p "$TEST_HOME" "$TEST_HOME/Downloads"
    reset_mocks
}

teardown() {
    # Clean up files created during the test
    safe_rm_rf "$MOCK_TMP"
    mkdir -p "$MOCK_TMP"
}

run_test() {
    local test_func="$1"
    local test_desc="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    
    echo -ne "Running test $((TESTS_RUN)): $test_desc ... "
    
    setup
    
    set +e
    (
        set -e
        $test_func
    )
    local test_status=$?
    set -e
    
    teardown
    
    if [ $test_status -eq 0 ]; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        # Keep moving to next test
    fi
}

# --- Test Cases ---

# T1: Help option output
test_help() {
    run_gravlift --help
    assert_success
    assert_output_contains "Usage:"
    assert_output_contains "Installer/Updater"
}

# T2: Unknown CLI options fail
test_unknown_option() {
    run_gravlift --non-existent-option
    assert_failure 1
    assert_output_contains "Unknown option"
}

# T3: Command dependencies check fails when dependency is missing
test_dependencies_missing() {
    local dep_bin="$SANDBOX_DIR/dep_bin"
    mkdir -p "$dep_bin"
    # Create symlinks to all dependencies in system PATH except 'tar'
    for cmd in bash find cut uniq mktemp ln rm cp realpath; do
        local cmd_path
        cmd_path=$(type -p "$cmd" 2>/dev/null || echo "")
        if [ -n "$cmd_path" ]; then
            ln -s "$cmd_path" "$dep_bin/$cmd"
        fi
    done
    # We do NOT symlink tar
    # Now run gravlift with PATH set to ONLY dep_bin and MOCK_BIN
    set +e
    PATH="$MOCK_BIN:$dep_bin" bash "$GRAVLIFT_PATH" --help > "$LAST_OUTPUT_FILE" 2>&1
    LAST_EXIT_CODE=$?
    set -e
    LAST_OUTPUT=$(cat "$LAST_OUTPUT_FILE")
    
    assert_failure 1
    assert_output_contains "Missing required command dependencies"
}

# T4: Auto-detection (custom XDG user dir)
test_auto_detection() {
    local custom_download="$TEST_HOME/custom_inbox"
    mkdir -p "$custom_download"
    
    # Mock Antigravity 2.0 archive in the custom downloads folder
    create_mock_archive "antigravity" "$custom_download/Antigravity.tar.gz" "2.0.1"
    # A foreign/legacy archive that should be ignored during auto-detection
    create_mock_archive "other-app" "$custom_download/Antigravity IDE.tar.gz" "1.2.3"
    
    # Configure custom download dir in the mock xdg-user-dir
    set_mock_xdg_user_dir "$custom_download"
    
    # Run in dry run
    run_gravlift --dry-run
    assert_success
    assert_output_contains "Found 1 archive(s) to process"
    assert_output_contains "Antigravity.tar.gz"
}

# T5: Uniqueness check prevents duplicate archives
test_uniqueness_check() {
    create_mock_archive "antigravity" "$TEST_HOME/Downloads/Antigravity-1.tar.gz" "1.0.0"
    create_mock_archive "antigravity" "$TEST_HOME/Downloads/Antigravity-2.tar.gz" "2.0.0"
    
    run_gravlift
    assert_failure 1
    assert_output_contains "Multiple archives found for Antigravity 2.0"
    assert_output_contains "Installation aborted"
}

# T6: Version comparison upgrade vs downgrade
test_version_comparison() {
    # 1. Install 1.0.0 first
    create_mock_archive "antigravity" "$TEST_HOME/Downloads/Antigravity.tar.gz" "1.0.0"
    run_gravlift
    assert_success
    assert_file_exists "$TEST_HOME/opt/antigravity/antigravity"
    assert_file_exists "$TEST_HOME/opt/antigravity/resources/app/package.json"
    
    # 2. Try to install same version 1.0.0 (fails without --force)
    create_mock_archive "antigravity" "$TEST_HOME/Downloads/Antigravity.tar.gz" "1.0.0"
    run_gravlift
    assert_failure 1
    assert_output_contains "is not newer than installed version"
    
    # 3. Upgrade to 1.1.0 (succeeds)
    create_mock_archive "antigravity" "$TEST_HOME/Downloads/Antigravity.tar.gz" "1.1.0"
    run_gravlift
    assert_success
}

# T7: Force override flag allows same or downgrade
test_force_override() {
    # 1. Install 2.0.0 first
    create_mock_archive "antigravity" "$TEST_HOME/Downloads/Antigravity.tar.gz" "2.0.0"
    run_gravlift
    assert_success
    
    # 2. Downgrade to 1.0.0 with --force (succeeds)
    create_mock_archive "antigravity" "$TEST_HOME/Downloads/Antigravity.tar.gz" "1.0.0"
    run_gravlift --force
    assert_success
    assert_output_contains "forcing installation as requested"
}

# T8: Backup created during upgrade
test_backup_created() {
    # Install 1.0.0
    create_mock_archive "antigravity" "$TEST_HOME/Downloads/Antigravity.tar.gz" "1.0.0"
    run_gravlift
    assert_success
    
    # Upgrade to 2.0.0
    create_mock_archive "antigravity" "$TEST_HOME/Downloads/Antigravity.tar.gz" "2.0.0"
    run_gravlift
    assert_success
    
    # Assert backup file is created under ~/.cache/gravlift/backups/
    local backup_count
    backup_count=$(find "$TEST_HOME/.cache/gravlift/backups" -name "antigravity_backup_*.tar.gz" | wc -l)
    if [ "$backup_count" -ne 1 ]; then
        echo -e "  ${RED}FAIL:${NC} Expected 1 backup file, found $backup_count"
        return 1
    fi
}

# T9: Nested executable path-depth routing
test_depth_routing() {
    # Create Antigravity archive with "nested" layout (executable at bin/antigravity and a shell wrapper at antigravity)
    create_mock_archive "antigravity" "$TEST_HOME/Downloads/Antigravity.tar.gz" "1.0.0" "nested"
    
    run_gravlift
    assert_success
    
    # Verify symlink points to the shallowest wrapper at the root, NOT the one in bin/
    assert_link_exists "$TEST_HOME/.local/bin/antigravity" "$TEST_HOME/opt/antigravity/antigravity"
}

# T10: Clean install removes old files
test_clean_install() {
    create_mock_archive "antigravity" "$TEST_HOME/Downloads/Antigravity.tar.gz" "1.0.0"
    run_gravlift
    assert_success
    
    # Add a residual file inside the installation directory
    echo "residual file" > "$TEST_HOME/opt/antigravity/residual.txt"
    
    # Upgrade
    create_mock_archive "antigravity" "$TEST_HOME/Downloads/Antigravity.tar.gz" "2.0.0"
    run_gravlift
    assert_success
    
    # Verify residual.txt is deleted
    assert_file_not_exists "$TEST_HOME/opt/antigravity/residual.txt"
}

# T11: GNOME launcher creation and icon extraction
test_gnome_launcher() {
    create_mock_archive "antigravity" "$TEST_HOME/Downloads/Antigravity.tar.gz" "1.0.0"
    run_gravlift
    assert_success
    
    # Verify desktop launcher exists and contains execution and icon commands
    local desktop_file="$TEST_HOME/.local/share/applications/antigravity.desktop"
    assert_file_exists "$desktop_file"
    assert_output_contains "Creating desktop launcher"
    
    # Verify custom icon extracted/copied to ~/.local/share/icons/antigravity.png
    assert_file_exists "$TEST_HOME/.local/share/icons/antigravity.png"
}

# T12: Concurrency lock prevents parallel executions
test_concurrency_lock() {
    # 1. Write lock directory and pid file with current test process PID
    local lock_dir="$TEST_HOME/.cache/gravlift/gravlift.lock.dir"
    mkdir -p "$lock_dir"
    echo "$$" > "$lock_dir/pid"
    
    create_mock_archive "antigravity" "$TEST_HOME/Downloads/Antigravity.tar.gz" "1.0.0"
    
    # 2. Run gravlift, should abort
    run_gravlift
    assert_failure 1
    assert_output_contains "Another instance of gravlift"
    
    # Clean lock
    safe_rm_rf "$lock_dir"
}

# T13: Disk space pre-flight validation
test_disk_space_check() {
    # Mock df to return only 500MB (512000 KB) which is less than 1GB requirement
    set_mock_df 512000
    
    create_mock_archive "antigravity" "$TEST_HOME/Downloads/Antigravity.tar.gz" "1.0.0"
    run_gravlift
    assert_failure 1
    assert_output_contains "Insufficient disk space"
}

# T14: Signal trap cleans up temp directories
test_trap_cleanup() {
    local archive="$TEST_HOME/Downloads/Antigravity.tar.gz"
    create_mock_archive "antigravity" "$archive" "1.0.0"

    # Mock tar so that table-of-contents inspection (-tf) succeeds,
    # but extraction (-xzf) fails (simulating corrupted payload blocks).
    local real_tar
    real_tar=$(which tar)
    cat > "$MOCK_BIN/tar" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == *"-tf"* ]]; then
    exec "$real_tar" "\$@"
elif [[ "\$*" == *"-xzf"* ]]; then
    echo "tar: corrupted payload block" >&2
    exit 2
fi
exec "$real_tar" "\$@"
EOF
    chmod +x "$MOCK_BIN/tar"
    
    run_gravlift "$archive"
    assert_failure 1
    assert_output_contains "Failed to extract tarball archive"
    
    # Verify that the temporary extraction directory is deleted.
    # Since we set TMPDIR="$MOCK_TMP", check that no directories are left under $MOCK_TMP.
    local dir_count
    dir_count=$(find "$MOCK_TMP" -mindepth 1 -maxdepth 1 -type d | wc -l)
    if [ "$dir_count" -ne 0 ]; then
        echo -e "  ${RED}FAIL:${NC} Expected 0 leftover temp directories, found $dir_count"
        return 1
    fi
}

# T15: Version flag outputs script version
test_version_flag() {
    run_gravlift --version
    assert_success
    assert_output_contains "gravlift v2.0.0"
}

# T16: Version fallback to Electron Node execution when package.json is packaged inside app.asar
test_electron_version_fallback() {
    # Create archive without standard package.json file, version is inside the mock executable
    create_mock_archive "antigravity" "$TEST_HOME/Downloads/Antigravity.tar.gz" "2.1.0" "no-json"
    
    run_gravlift
    assert_success
    
    # Verify that version fallback successfully retrieved the version and completed installation
    assert_file_exists "$TEST_HOME/opt/antigravity/antigravity"
}

# T17: Self-installation default to ~/opt/gravlift and link to ~/.local/bin
test_self_install_default() {
    run_gravlift --self-install
    assert_success
    
    # Assert script is installed in ~/opt/gravlift/gravlift and is executable
    assert_file_exists "$TEST_HOME/opt/gravlift/gravlift"
    if [ ! -x "$TEST_HOME/opt/gravlift/gravlift" ]; then
        echo -e "  ${RED}FAIL:${NC} Expected $TEST_HOME/opt/gravlift/gravlift to be executable"
        return 1
    fi
    
    # Assert symlink in ~/.local/bin/gravlift points to ~/opt/gravlift/gravlift
    assert_link_exists "$TEST_HOME/.local/bin/gravlift" "$TEST_HOME/opt/gravlift/gravlift"
    
    # Verify that the installed symlink works by running --version
    local ver_out
    ver_out=$("$TEST_HOME/.local/bin/gravlift" --version)
    if [[ "$ver_out" != *"gravlift v2.0.0"* ]]; then
        echo -e "  ${RED}FAIL:${NC} Installed symlink failed to execute correctly"
        return 1
    fi
}

# T18: Self-installation with CLI directory overrides
test_self_install_cli_overrides() {
    local custom_install="$TEST_HOME/custom/tools/gravlift"
    local custom_bin="$TEST_HOME/custom/bin"
    
    run_gravlift --self-install --self-install-dir "$custom_install" --bin-dir "$custom_bin"
    assert_success
    
    assert_file_exists "$custom_install/gravlift"
    assert_link_exists "$custom_bin/gravlift" "$custom_install/gravlift"
    assert_output_contains "Installing 'gravlift' script to $custom_install"
    assert_output_contains "Symlink created: $custom_bin/gravlift -> $custom_install/gravlift"
}

# T19: Self-installation dynamically discovers bin directory via systemd-path
test_self_install_dynamic_systemd_path() {
    local custom_sys_bin="$TEST_HOME/systemd_detected_bin"
    set_mock_systemd_path "$custom_sys_bin"
    
    run_gravlift --self-install
    assert_success
    
    assert_file_exists "$TEST_HOME/opt/gravlift/gravlift"
    assert_link_exists "$custom_sys_bin/gravlift" "$TEST_HOME/opt/gravlift/gravlift"
}

# T20: Self-installation respects ~/.config/gravlift/config
test_self_install_config_file() {
    local config_dir="$TEST_HOME/.config/gravlift"
    mkdir -p "$config_dir"
    
    cat > "$config_dir/config" <<EOF
# Custom configuration
SELF_INSTALL_DIR=~/my_tools/gravlift
BIN_DIR=~/my_bin
EOF

    run_gravlift --self-install
    assert_success
    
    assert_file_exists "$TEST_HOME/my_tools/gravlift/gravlift"
    assert_link_exists "$TEST_HOME/my_bin/gravlift" "$TEST_HOME/my_tools/gravlift/gravlift"
}

# T21: Self-installation opt-out via --no-self-install CLI flag
test_self_install_opt_out_flag() {
    local archive="$MOCK_ARCHIVES/Antigravity-test-opt-out.tar.gz"
    create_mock_archive "antigravity" "$archive" "2.1.0"

    run_gravlift --no-self-install "$archive"
    assert_success

    # Antigravity itself should be installed and linked
    assert_file_exists "$TEST_HOME/opt/antigravity/antigravity"
    assert_link_exists "$TEST_HOME/.local/bin/antigravity"

    # gravlift itself should NOT be installed or linked
    assert_file_not_exists "$TEST_HOME/opt/gravlift/gravlift"
    if [ -L "$TEST_HOME/.local/bin/gravlift" ] || [ -f "$TEST_HOME/.local/bin/gravlift" ]; then
        echo -e "  ${RED}FAIL:${NC} Expected $TEST_HOME/.local/bin/gravlift to NOT exist"
        return 1
    fi
    assert_output_contains "Skipping gravlift self-installation (opted out"
}

# T22: Self-installation opt-out via config file AUTO_SELF_INSTALL=false
test_self_install_opt_out_config() {
    local config_dir="$TEST_HOME/.config/gravlift"
    mkdir -p "$config_dir"
    cat > "$config_dir/config" <<EOF
AUTO_SELF_INSTALL=false
EOF

    local archive="$MOCK_ARCHIVES/Antigravity-test-opt-out-cfg.tar.gz"
    create_mock_archive "antigravity" "$archive" "2.1.0"

    run_gravlift "$archive"
    assert_success

    # Antigravity should be installed
    assert_file_exists "$TEST_HOME/opt/antigravity/antigravity"

    # gravlift should NOT be installed
    assert_file_not_exists "$TEST_HOME/opt/gravlift/gravlift"
    if [ -L "$TEST_HOME/.local/bin/gravlift" ] || [ -f "$TEST_HOME/.local/bin/gravlift" ]; then
        echo -e "  ${RED}FAIL:${NC} Expected $TEST_HOME/.local/bin/gravlift to NOT exist"
        return 1
    fi
    assert_output_contains "Skipping gravlift self-installation (opted out"
}

# T23: Uninstall Antigravity application, symlink, launcher, and icon
test_uninstall_antigravity() {
    local archive="$MOCK_ARCHIVES/Antigravity-test-uninstall.tar.gz"
    create_mock_archive "antigravity" "$archive" "2.1.0"
    
    run_gravlift "$archive"
    assert_success
    assert_file_exists "$TEST_HOME/opt/antigravity/antigravity"
    assert_link_exists "$TEST_HOME/.local/bin/antigravity"

    run_gravlift --uninstall -y
    assert_success
    
    assert_file_not_exists "$TEST_HOME/opt/antigravity/antigravity"
    if [ -d "$TEST_HOME/opt/antigravity" ]; then
        echo -e "  ${RED}FAIL:${NC} Expected $TEST_HOME/opt/antigravity directory to be deleted"
        return 1
    fi
    if [ -L "$TEST_HOME/.local/bin/antigravity" ] || [ -f "$TEST_HOME/.local/bin/antigravity" ]; then
        echo -e "  ${RED}FAIL:${NC} Expected $TEST_HOME/.local/bin/antigravity to be deleted"
        return 1
    fi
    assert_file_not_exists "$TEST_HOME/.local/share/applications/antigravity.desktop"
    assert_file_not_exists "$TEST_HOME/.local/share/icons/antigravity.png"
    assert_output_contains "Antigravity 2.0 uninstallation completed successfully"
}

# T24: Uninstall Antigravity dry run displays actions without deleting files
test_uninstall_antigravity_dry_run() {
    local archive="$MOCK_ARCHIVES/Antigravity-test-uninstall-dry.tar.gz"
    create_mock_archive "antigravity" "$archive" "2.1.0"
    
    run_gravlift "$archive"
    assert_success
    
    run_gravlift --uninstall --dry-run
    assert_success
    
    assert_file_exists "$TEST_HOME/opt/antigravity/antigravity"
    assert_link_exists "$TEST_HOME/.local/bin/antigravity"
    assert_output_contains "[DRY-RUN] The following Antigravity items would be removed:"
}

# T25: Uninstall gravlift tool removes executable and symlink
test_uninstall_self() {
    run_gravlift --self-install
    assert_success
    assert_file_exists "$TEST_HOME/opt/gravlift/gravlift"
    assert_link_exists "$TEST_HOME/.local/bin/gravlift"

    run_gravlift --uninstall-self -y
    assert_success
    
    assert_file_not_exists "$TEST_HOME/opt/gravlift/gravlift"
    if [ -L "$TEST_HOME/.local/bin/gravlift" ] || [ -f "$TEST_HOME/.local/bin/gravlift" ]; then
        echo -e "  ${RED}FAIL:${NC} Expected $TEST_HOME/.local/bin/gravlift to be deleted"
        return 1
    fi
    assert_output_contains "gravlift tool uninstallation completed successfully"
}

# T26: Uninstall all with --purge removes app, tool, backups, and config
test_uninstall_all_with_purge() {
    local archive="$MOCK_ARCHIVES/Antigravity-test-uninstall-all.tar.gz"
    create_mock_archive "antigravity" "$archive" "2.1.0"
    
    run_gravlift "$archive"
    assert_success

    # Setup mock backups and config
    mkdir -p "$TEST_HOME/.cache/gravlift/backups"
    touch "$TEST_HOME/.cache/gravlift/backups/test.tar.gz"
    mkdir -p "$TEST_HOME/.config/gravlift"
    touch "$TEST_HOME/.config/gravlift/config"

    run_gravlift --uninstall-all --purge -y
    assert_success

    assert_file_not_exists "$TEST_HOME/opt/antigravity/antigravity"
    assert_file_not_exists "$TEST_HOME/opt/gravlift/gravlift"
    if [ -L "$TEST_HOME/.local/bin/antigravity" ]; then
        echo -e "  ${RED}FAIL:${NC} Expected antigravity bin link to be deleted"
        return 1
    fi
    if [ -L "$TEST_HOME/.local/bin/gravlift" ]; then
        echo -e "  ${RED}FAIL:${NC} Expected gravlift bin link to be deleted"
        return 1
    fi
    if [ -d "$TEST_HOME/.cache/gravlift/backups" ]; then
        echo -e "  ${RED}FAIL:${NC} Expected backup directory to be purged"
        return 1
    fi
    if [ -d "$TEST_HOME/.config/gravlift" ]; then
        echo -e "  ${RED}FAIL:${NC} Expected config directory to be purged"
        return 1
    fi
    assert_output_contains "Antigravity 2.0 uninstallation completed successfully"
    assert_output_contains "gravlift tool uninstallation completed successfully"
}

# T27: Non-interactive uninstallation requires -y/--yes
test_uninstall_non_interactive_requires_yes() {
    local archive="$MOCK_ARCHIVES/Antigravity-test-requires-yes.tar.gz"
    create_mock_archive "antigravity" "$archive" "2.1.0"
    
    run_gravlift "$archive"
    assert_success

    # Running in non-interactive subshell without -y should fail safely
    run_gravlift --uninstall
    assert_failure 1
    assert_output_contains "Non-interactive environment detected. Use '-y' or '--yes'"
}

# T28: Subcommand 'version' displays version
test_subcommand_version() {
    run_gravlift version
    assert_success
    assert_output_contains "gravlift v2.0.0"
}

# T29: Subcommand 'help' and 'help <cmd>' display usage information
test_subcommand_help() {
    run_gravlift help
    assert_success
    assert_output_contains "Commands:"
    assert_output_contains "install [archive.tar.gz]"

    run_gravlift help install
    assert_success
    assert_output_contains "Usage: gravlift install [options] [archive.tar.gz]"

    run_gravlift help uninstall
    assert_success
    assert_output_contains "Usage: gravlift uninstall [target] [options]"
}

# T30: Subcommand 'check' runs pre-flight diagnostics
test_subcommand_check() {
    run_gravlift check
    assert_success
    assert_output_contains "Running pre-flight diagnostics..."
    assert_output_contains "All required system dependencies are installed."
    assert_output_contains "Disk space check passed"
    assert_output_contains "Diagnostics completed."
}

# T31: Subcommand 'install' installs archive with proper routing and desktop entries
test_subcommand_install() {
    local archive="$MOCK_ARCHIVES/Antigravity-test-subcmd-install.tar.gz"
    create_mock_archive "antigravity" "$archive" "2.1.0"

    run_gravlift install "$archive"
    assert_success

    assert_file_exists "$TEST_HOME/opt/antigravity/antigravity"
    assert_link_exists "$TEST_HOME/.local/bin/antigravity"
    assert_file_exists "$TEST_HOME/.local/share/applications/antigravity.desktop"
    assert_output_contains "Antigravity 2.0 installed/updated successfully"
}

# T32: Subcommand 'update' scans Downloads directory and installs
test_subcommand_update() {
    local archive="$TEST_HOME/Downloads/Antigravity-update-test.tar.gz"
    create_mock_archive "antigravity" "$archive" "2.2.0"

    run_gravlift update
    assert_success

    assert_file_exists "$TEST_HOME/opt/antigravity/antigravity"
    assert_link_exists "$TEST_HOME/.local/bin/antigravity"
    assert_output_contains "Found 1 archive(s) to process"
    assert_output_contains "Antigravity 2.0 installed/updated successfully"
}

# T33: Subcommand 'self-install' installs gravlift executable and symlink
test_subcommand_self_install() {
    run_gravlift self-install
    assert_success

    assert_file_exists "$TEST_HOME/opt/gravlift/gravlift"
    assert_link_exists "$TEST_HOME/.local/bin/gravlift"
    assert_output_contains "Script installed at: $TEST_HOME/opt/gravlift/gravlift"
}

# T34: Subcommand 'uninstall app' and 'uninstall self'
test_subcommand_uninstall_targets() {
    local archive="$MOCK_ARCHIVES/Antigravity-test-uninstall-target.tar.gz"
    create_mock_archive "antigravity" "$archive" "2.1.0"

    # Install both app and self
    run_gravlift install "$archive"
    assert_success
    assert_file_exists "$TEST_HOME/opt/antigravity/antigravity"
    assert_file_exists "$TEST_HOME/opt/gravlift/gravlift"

    # Uninstall app target
    run_gravlift uninstall app -y
    assert_success
    assert_file_not_exists "$TEST_HOME/opt/antigravity/antigravity"
    assert_file_exists "$TEST_HOME/opt/gravlift/gravlift"
    assert_output_contains "Antigravity 2.0 uninstallation completed successfully"

    # Uninstall self target
    run_gravlift uninstall self -y
    assert_success
    assert_file_not_exists "$TEST_HOME/opt/gravlift/gravlift"
    assert_output_contains "gravlift tool uninstallation completed successfully"
}

# T35: Subcommand 'uninstall all --purge -y' cleans everything
test_subcommand_uninstall_all_purge() {
    local archive="$MOCK_ARCHIVES/Antigravity-test-uninstall-all-subcmd.tar.gz"
    create_mock_archive "antigravity" "$archive" "2.1.0"

    run_gravlift install "$archive"
    assert_success

    mkdir -p "$TEST_HOME/.cache/gravlift/backups"
    touch "$TEST_HOME/.cache/gravlift/backups/test.tar.gz"
    mkdir -p "$TEST_HOME/.config/gravlift"
    touch "$TEST_HOME/.config/gravlift/config"

    run_gravlift uninstall all --purge -y
    assert_success

    assert_file_not_exists "$TEST_HOME/opt/antigravity/antigravity"
    assert_file_not_exists "$TEST_HOME/opt/gravlift/gravlift"
    if [ -d "$TEST_HOME/.cache/gravlift/backups" ]; then
        echo -e "  ${RED}FAIL:${NC} Expected backups to be purged"
        return 1
    fi
    if [ -d "$TEST_HOME/.config/gravlift" ]; then
        echo -e "  ${RED}FAIL:${NC} Expected config to be purged"
        return 1
    fi
    assert_output_contains "Antigravity 2.0 uninstallation completed successfully"
    assert_output_contains "gravlift tool uninstallation completed successfully"
}

# T36: Self-install detects and upgrades older installed versions of gravlift
test_self_install_version_upgrade() {
    # Pre-install an older version (v1.0.0)
    mkdir -p "$TEST_HOME/opt/gravlift" "$TEST_HOME/.local/bin"
    cat > "$TEST_HOME/opt/gravlift/gravlift" << 'EOF'
#!/usr/bin/env bash
GRAVLIFT_VERSION="1.0.0"
echo "gravlift v${GRAVLIFT_VERSION}"
EOF
    chmod +x "$TEST_HOME/opt/gravlift/gravlift"
    ln -s "$TEST_HOME/opt/gravlift/gravlift" "$TEST_HOME/.local/bin/gravlift"

    # Run check to verify detection of older installed version
    run_gravlift check
    assert_success
    assert_output_contains "Installed gravlift (v1.0.0) is older than running script (v2.0.0)"

    # Run self-install to upgrade
    run_gravlift self-install
    assert_success
    assert_output_contains "Upgrading installed gravlift (v1.0.0 -> v2.0.0)"
    assert_output_contains "Script upgraded at: $TEST_HOME/opt/gravlift/gravlift"

    # Running self-install again reports up-to-date
    run_gravlift self-install
    assert_success
    assert_output_contains "Installed gravlift is already up to date (v2.0.0)"
}

# --- Main Test Execution ---

echo -e "${BOLD}Starting gravlift test suite...${NC}"
echo "Sandbox directory: $SANDBOX_DIR"
echo "================================================="

run_test test_help "Help options output"
run_test test_unknown_option "Unknown CLI options fail"
run_test test_dependencies_missing "Fail-fast on missing dependency check"
run_test test_auto_detection "XDG Download directory scanning"
run_test test_uniqueness_check "Aborts if duplicate archives are found"
run_test test_version_comparison "Semantic version comparison and update routing"
run_test test_force_override "Override check using --force"
run_test test_backup_created "Backup created before installation overwrite"
run_test test_depth_routing "Nested shallow executable path-routing"
run_test test_clean_install "Existing installs are cleaned completely"
run_test test_gnome_launcher "GNOME launcher creation and app.asar icon extraction"
run_test test_concurrency_lock "Concurrency PID locking protects install path"
run_test test_disk_space_check "Pre-flight disk space warning check"
run_test test_trap_cleanup "Temporary directory signal trap cleanup"
run_test test_version_flag "Version option outputs script version"
run_test test_electron_version_fallback "Version fallback to Electron Node evaluation"
run_test test_self_install_default "Self-installation defaults to ~/opt/gravlift with symlink"
run_test test_self_install_cli_overrides "Self-installation with CLI directory overrides"
run_test test_self_install_dynamic_systemd_path "Self-installation dynamically discovers bin directory via systemd-path"
run_test test_self_install_config_file "Self-installation respects ~/.config/gravlift/config"
run_test test_self_install_opt_out_flag "Self-installation opt-out via --no-self-install flag"
run_test test_self_install_opt_out_config "Self-installation opt-out via AUTO_SELF_INSTALL=false in config"
run_test test_uninstall_antigravity "Uninstall Antigravity app, symlink, launcher, and icon"
run_test test_uninstall_antigravity_dry_run "Uninstall dry run displays actions without deleting files"
run_test test_uninstall_self "Uninstall gravlift tool removes executable and symlink"
run_test test_uninstall_all_with_purge "Uninstall all with --purge removes app, tool, backups, and config"
run_test test_uninstall_non_interactive_requires_yes "Non-interactive uninstallation requires -y/--yes"
run_test test_subcommand_version "Subcommand 'version' displays version"
run_test test_subcommand_help "Subcommand 'help' and 'help <cmd>' display usage information"
run_test test_subcommand_check "Subcommand 'check' runs pre-flight diagnostics"
run_test test_subcommand_install "Subcommand 'install' installs archive with proper routing and desktop entries"
run_test test_subcommand_update "Subcommand 'update' scans Downloads directory and installs"
run_test test_subcommand_self_install "Subcommand 'self-install' installs gravlift executable and symlink"
run_test test_subcommand_uninstall_targets "Subcommand 'uninstall app' and 'uninstall self'"
run_test test_subcommand_uninstall_all_purge "Subcommand 'uninstall all --purge -y' cleans everything"
run_test test_self_install_version_upgrade "Self-install detects and upgrades older installed versions of gravlift"

echo "================================================="
echo -e "${BOLD}Test Suite Summary:${NC}"
echo -e "  Total Tests:  $TESTS_RUN"
echo -e "  Passed:       ${GREEN}$TESTS_PASSED${NC}"
fail_color="$NC"
if [ "$TESTS_FAILED" -gt 0 ]; then
    fail_color="$RED"
fi
echo -e "  Failed:       ${fail_color}${TESTS_FAILED}${NC}"

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}ALL TESTS PASSED!${NC}"
    exit 0
else
    echo -e "${RED}${BOLD}SOME TESTS FAILED!${NC}"
    exit 1
fi
