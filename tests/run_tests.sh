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
# Register cleanup trap for the master sandbox
cleanup_master_sandbox() {
    rm -rf "$SANDBOX_DIR"
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
    rm -f "$MOCK_BIN"/*
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

# Creates a mock Antigravity or Antigravity IDE tarball
create_mock_archive() {
    local type="$1"       # "antigravity" or "ide"
    local dest_path="$2"  # output archive path
    local version="$3"    # version inside package.json
    local layout="${4:-standard}" # "standard", "nested", or "no-json"

    local temp_build_dir
    temp_build_dir=$(mktemp -d "$MOCK_TMP/build_tarball.XXXXXX")
    
    local app_dir="$temp_build_dir/extracted"
    mkdir -p "$app_dir"

    # Define binary name
    local exe_name="antigravity"
    if [ "$type" = "ide" ]; then
        exe_name="antigravity-ide"
    fi

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
EOF
    chmod +x "$run_dir/$exe_name"

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
    rm -rf "$temp_build_dir"
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
        PATH="$MOCK_BIN:$PATH" bash "$GRAVLIFT_PATH" "$@"
    ) > "$LAST_OUTPUT_FILE" 2>&1
    LAST_EXIT_CODE=$?
    set -e
    LAST_OUTPUT=$(cat "$LAST_OUTPUT_FILE")
}

setup() {
    # Clean and recreate home directory and mock files
    rm -rf "$TEST_HOME"
    mkdir -p "$TEST_HOME" "$TEST_HOME/Downloads"
    reset_mocks
}

teardown() {
    # Clean up files created during the test
    rm -rf "$MOCK_TMP"/*
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
    
    # Mock archive in the custom downloads folder
    create_mock_archive "antigravity" "$custom_download/Antigravity.tar.gz" "2.0.1"
    # An IDE archive that should be ignored during auto-detection
    create_mock_archive "ide" "$custom_download/Antigravity IDE.tar.gz" "1.2.3"
    
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
    rm -rf "$lock_dir"
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
    # We will trigger a failure in extraction to check trap cleanup.
    # How? Let's pass a corrupt tarball (a text file renamed as .tar.gz)
    echo "not a tarball" > "$TEST_HOME/Downloads/Antigravity.tar.gz"
    
    run_gravlift
    assert_failure 1
    assert_output_contains "Failed to extract tarball archive"
    
    # Verify that the temporary extraction directory is deleted.
    # Any directory created by mktemp should be cleaned up.
    # Since we set TMPDIR="$MOCK_TMP", let's check that no directories are left under $MOCK_TMP.
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
    assert_output_contains "gravlift v1.0.0"
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
    if [[ "$ver_out" != *"gravlift v1.0.0"* ]]; then
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
