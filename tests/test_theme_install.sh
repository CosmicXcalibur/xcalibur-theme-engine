#!/usr/bin/env bash

set -Eeuo pipefail
shopt -s nullglob

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(dirname "$TEST_DIR")"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/xcalibur-theme-test.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

TEST_BIN="$TEST_ROOT/bin"
TMPDIR="$TEST_ROOT/staging"
THEMES_DIR="$TEST_ROOT/themes"
CURRENT_THEME_FILE="$TEST_ROOT/state/current_theme"
TEST_REAL_CP="$(command -v cp)"
TEST_REAL_MKDIR="$(command -v mkdir)"
export TMPDIR TEST_REAL_CP TEST_REAL_MKDIR
export THEMES_DIR

mkdir -p "$TEST_BIN" "$TMPDIR" "$THEMES_DIR" "$(dirname "$CURRENT_THEME_FILE")"

source "$REPOSITORY_ROOT/engine/lib/common.sh"
source "$REPOSITORY_ROOT/engine/lib/theme_manifest.sh"
source "$REPOSITORY_ROOT/engine/lib/theme_definition.sh"
source "$REPOSITORY_ROOT/engine/lib/theme_pack.sh"
source "$REPOSITORY_ROOT/engine/lib/theme_install.sh"

cat > "$TEST_BIN/git" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
: > "$TEST_GIT_CLONE_MARKER"
[[ "${TEST_GIT_FAIL:-0}" != 1 ]] || exit 1
destination=""
for argument in "$@"; do
    destination="$argument"
done
mkdir -p "$destination"
"$TEST_REAL_CP" -a -- "$TEST_GIT_SOURCE/." "$destination/"
cat > "$destination/remote-code.sh" <<'REMOTE'
#!/usr/bin/env bash
touch "${XCALIBUR_ADAPTER_TEST_MARKER:?}"
REMOTE
chmod +x "$destination/remote-code.sh"
EOF

cat > "$TEST_BIN/cp" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
destination="${@: -1}"
if [[ "${TEST_FAIL_INSTALL_COPY:-0}" == 1 &&
      "$destination" == "$THEMES_DIR/catppuccin-mocha/palette.conf" ]]; then
    exit 1
fi
exec "$TEST_REAL_CP" "$@"
EOF

cat > "$TEST_BIN/mkdir" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ -n "${TEST_RACE_MKDIR_DESTINATION:-}" &&
      "$#" -eq 1 && "$1" == "$TEST_RACE_MKDIR_DESTINATION" &&
      ! -e "$TEST_RACE_MKDIR_MARKER" ]]; then
    "$TEST_REAL_MKDIR" "$1"
    printf 'created by competing process\n' > "$1/competitor.txt"
    : > "$TEST_RACE_MKDIR_MARKER"
fi
exec "$TEST_REAL_MKDIR" "$@"
EOF

chmod +x "$TEST_BIN/git" "$TEST_BIN/cp" "$TEST_BIN/mkdir"
PATH="$TEST_BIN:$PATH"
export PATH

TEST_GIT_SOURCE=""
TEST_GIT_CLONE_MARKER="$TEST_ROOT/git-clone-called"
TEST_GIT_FAIL=0
TEST_FAIL_INSTALL_COPY=0
TEST_RACE_MKDIR_DESTINATION=""
TEST_RACE_MKDIR_MARKER="$TEST_ROOT/competing-mkdir-ran"
XCALIBUR_ADAPTER_TEST_MARKER="$TEST_ROOT/remote-code-ran"
export TEST_GIT_SOURCE TEST_GIT_CLONE_MARKER TEST_GIT_FAIL TEST_FAIL_INSTALL_COPY
export TEST_RACE_MKDIR_DESTINATION TEST_RACE_MKDIR_MARKER XCALIBUR_ADAPTER_TEST_MARKER

TEST_APPLY_CALLED=0
theme_apply() {
    TEST_APPLY_CALLED=1
}

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_no_staging_directories() {
    local staging_directories=("$TMPDIR"/xcalibur-theme-install.*)
    [[ "${#staging_directories[@]}" -eq 0 ]] ||
        fail "temporary staging directory was not cleaned up"
}

assert_installed_files() {
    local theme_dir="$1"
    local files=("$theme_dir"/*)
    [[ "${#files[@]}" -eq 2 ]] || fail "expected exactly two files in $theme_dir"
    [[ -f "$theme_dir/theme.conf" && -f "$theme_dir/palette.conf" ]] ||
        fail "expected native theme files in $theme_dir"
}

printf 'current-before\n' > "$CURRENT_THEME_FILE"

# Catppuccin installation converts only palette.json and leaves unrelated
# repository content in staging, without executing or installing it.
TEST_GIT_SOURCE="$TEST_DIR/fixtures/catppuccin"
export TEST_GIT_SOURCE
if ! theme_install install catppuccin/palette --format catppuccin --variant mocha; then
    fail "valid local Catppuccin fixture did not install"
fi
assert_installed_files "$THEMES_DIR/catppuccin-mocha"
[[ ! -e "$THEMES_DIR/catppuccin-mocha/malicious.sh" ]] || fail "remote shell file was installed"
[[ ! -e "$XCALIBUR_ADAPTER_TEST_MARKER" ]] || fail "remote shell file was executed"
[[ "$(< "$CURRENT_THEME_FILE")" == current-before ]] || fail "current theme state changed"
[[ "$TEST_APPLY_CALLED" == 0 ]] || fail "theme_apply was called during installation"
assert_no_staging_directories

# The native command continues to install root-level native packs.
TEST_GIT_SOURCE="$TEST_DIR/fixtures/native"
export TEST_GIT_SOURCE
if ! theme_install install test/native-fixture; then
    fail "valid local native fixture did not install"
fi
assert_installed_files "$THEMES_DIR/native-fixture"
assert_no_staging_directories

# Every external variant uses the same native installation boundary.
TEST_GIT_SOURCE="$TEST_DIR/fixtures/catppuccin"
export TEST_GIT_SOURCE
for variant in latte frappe macchiato; do
    if ! theme_install install catppuccin/palette --format catppuccin --variant "$variant"; then
        fail "Catppuccin $variant fixture did not install"
    fi
    assert_installed_files "$THEMES_DIR/catppuccin-$variant"
    assert_no_staging_directories
done

TEST_GIT_SOURCE="$TEST_DIR/fixtures/rose_pine"
export TEST_GIT_SOURCE
for variant in main moon dawn; do
    theme_id=rose-pine
    [[ "$variant" == main ]] || theme_id="rose-pine-$variant"
    if ! theme_install install rose-pine/rose-pine-palette --format rose-pine --variant "$variant"; then
        fail "Rosé Pine $variant fixture did not install"
    fi
    assert_installed_files "$THEMES_DIR/$theme_id"
    assert_no_staging_directories
done

TEST_GIT_SOURCE="$TEST_DIR/fixtures/nord"
export TEST_GIT_SOURCE
if ! theme_install install nordtheme/nord --format nord; then
    fail "Nord fixture did not install"
fi
assert_installed_files "$THEMES_DIR/nord"
assert_no_staging_directories
[[ ! -e "$XCALIBUR_ADAPTER_TEST_MARKER" ]] || fail "remote code was executed"

# External installations refuse an existing destination as native packs do.
nord_manifest_before="$(< "$THEMES_DIR/nord/theme.conf")"
if theme_install install nordtheme/nord --format nord; then
    fail "existing Nord destination was overwritten"
fi
[[ "$(< "$THEMES_DIR/nord/theme.conf")" == "$nord_manifest_before" ]] ||
    fail "existing Nord manifest changed after overwrite refusal"
assert_no_staging_directories

# Keep later failure-path checks isolated from the successful install above.
rm -rf -- "$THEMES_DIR/catppuccin-mocha"

# Existing destinations are never overwritten.
TEST_GIT_SOURCE="$TEST_DIR/fixtures/native"
export TEST_GIT_SOURCE
native_manifest_before="$(< "$THEMES_DIR/native-fixture/theme.conf")"
if theme_install install test/native-fixture; then
    fail "existing native theme destination was overwritten"
fi
[[ "$(< "$THEMES_DIR/native-fixture/theme.conf")" == "$native_manifest_before" ]] ||
    fail "existing theme manifest changed after overwrite refusal"
assert_no_staging_directories

# A competing process can create the destination after the existence check.
# The install must fail without removing or changing the competing directory.
rm -rf -- "$THEMES_DIR/native-fixture"
TEST_RACE_MKDIR_DESTINATION="$THEMES_DIR/native-fixture"
export TEST_RACE_MKDIR_DESTINATION
if theme_install install test/native-fixture; then
    fail "installation succeeded after a competing process created the destination"
fi
TEST_RACE_MKDIR_DESTINATION=""
export TEST_RACE_MKDIR_DESTINATION
[[ -e "$TEST_RACE_MKDIR_MARKER" ]] || fail "competing mkdir was not simulated"
[[ -f "$THEMES_DIR/native-fixture/competitor.txt" ]] ||
    fail "competing destination contents were removed"
[[ "$(< "$THEMES_DIR/native-fixture/competitor.txt")" == "created by competing process" ]] ||
    fail "competing destination contents were changed"
[[ "$(find "$THEMES_DIR/native-fixture" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1 ]] ||
    fail "installer added files to the competing destination"
assert_no_staging_directories

# The installer layer rejects a root palette.json symlink.
TEST_GIT_SOURCE="$TEST_ROOT/symlink-repository"
mkdir -p "$TEST_GIT_SOURCE"
"$TEST_REAL_CP" -a -- "$TEST_DIR/fixtures/catppuccin/." "$TEST_GIT_SOURCE/"
rm -- "$TEST_GIT_SOURCE/palette.json"
ln -s "$TEST_DIR/fixtures/catppuccin/palette.json" "$TEST_GIT_SOURCE/palette.json"
export TEST_GIT_SOURCE
if theme_install install catppuccin/palette --format catppuccin --variant mocha; then
    fail "symlinked palette.json was accepted"
fi
[[ ! -e "$THEMES_DIR/catppuccin-mocha" ]] || fail "symlink failure left an installed destination"
assert_no_staging_directories

# The Rosé Pine root data file must also be regular and not a symlink.
TEST_GIT_SOURCE="$TEST_ROOT/rose-symlink-repository"
mkdir -p "$TEST_GIT_SOURCE"
ln -s "$TEST_DIR/fixtures/rose_pine/palette.json" "$TEST_GIT_SOURCE/palette.json"
export TEST_GIT_SOURCE
rm -rf -- "$THEMES_DIR/rose-pine"
if theme_install install rose-pine/rose-pine-palette --format rose-pine --variant main; then
    fail "symlinked Rosé Pine palette.json was accepted"
fi
[[ ! -e "$THEMES_DIR/rose-pine" ]] || fail "symlink failure left a Rosé Pine destination"
assert_no_staging_directories

# A nested source path cannot traverse a repository symlink.
TEST_GIT_SOURCE="$TEST_ROOT/nord-symlink-repository"
mkdir -p "$TEST_GIT_SOURCE"
ln -s "$TEST_DIR/fixtures/nord/src" "$TEST_GIT_SOURCE/src"
export TEST_GIT_SOURCE
rm -rf -- "$THEMES_DIR/nord"
if theme_install install nordtheme/nord --format nord; then
    fail "symlinked Nord source directory was accepted"
fi
[[ ! -e "$THEMES_DIR/nord" ]] || fail "symlink failure left a Nord destination"
assert_no_staging_directories

# Bad external data must fail before creating an installed destination.
TEST_GIT_SOURCE="$TEST_ROOT/invalid-rose-repository"
mkdir -p "$TEST_GIT_SOURCE"
printf '{"main": [' > "$TEST_GIT_SOURCE/palette.json"
export TEST_GIT_SOURCE
rm -rf -- "$THEMES_DIR/rose-pine"
if theme_install install rose-pine/rose-pine-palette --format rose-pine --variant main; then
    fail "malformed Rosé Pine palette was installed"
fi
[[ ! -e "$THEMES_DIR/rose-pine" ]] || fail "bad conversion left a Rosé Pine destination"
assert_no_staging_directories

TEST_GIT_SOURCE="$TEST_ROOT/invalid-nord-repository"
mkdir -p "$TEST_GIT_SOURCE/src"
printf ':root { --nord0: #123456; }\n' > "$TEST_GIT_SOURCE/src/nord.css"
export TEST_GIT_SOURCE
rm -rf -- "$THEMES_DIR/nord"
if theme_install install nordtheme/nord --format nord; then
    fail "incomplete Nord palette was installed"
fi
[[ ! -e "$THEMES_DIR/nord" ]] || fail "bad conversion left a Nord destination"
assert_no_staging_directories

# A failed second copy removes the newly created partial destination.
TEST_GIT_SOURCE="$TEST_DIR/fixtures/catppuccin"
TEST_FAIL_INSTALL_COPY=1
export TEST_GIT_SOURCE TEST_FAIL_INSTALL_COPY
if theme_install install catppuccin/palette --format catppuccin --variant mocha; then
    fail "injected installation copy failure unexpectedly succeeded"
fi
TEST_FAIL_INSTALL_COPY=0
export TEST_FAIL_INSTALL_COPY
[[ ! -e "$THEMES_DIR/catppuccin-mocha" ]] || fail "partial Catppuccin destination was not removed"
assert_no_staging_directories

# Clone failures also clean up their staging directory.
TEST_GIT_FAIL=1
export TEST_GIT_FAIL
if theme_install install catppuccin/palette --format catppuccin --variant mocha; then
    fail "injected clone failure unexpectedly succeeded"
fi
TEST_GIT_FAIL=0
export TEST_GIT_FAIL
assert_no_staging_directories

# Adapter options are parsed strictly before any retrieval is attempted.
rm -- "$TEST_GIT_CLONE_MARKER"
if theme_install install catppuccin/palette --variant mocha; then
    fail "variant without explicit format was accepted"
fi
if theme_install install catppuccin/palette --format catppuccin --variant Mocha; then
    fail "incorrectly cased variant was accepted by installer"
fi
if theme_install install catppuccin/palette --format catppuccin --variant mocha --extra; then
    fail "unknown install option was accepted"
fi
if theme_install install another-owner/palette --format catppuccin --variant mocha; then
    fail "Catppuccin adapter accepted a non-official repository"
fi
if theme_install install rose-pine/rose-pine-palette --format rose-pine; then
    fail "Rosé Pine install accepted an omitted variant"
fi
if theme_install install rose-pine/rose-pine-palette --format rose-pine --variant Main; then
    fail "Rosé Pine install accepted an invalid variant"
fi
if theme_install install another-owner/rose-pine-palette --format rose-pine --variant main; then
    fail "Rosé Pine adapter accepted a non-official repository"
fi
if theme_install install nordtheme/nord --format nord --variant dark; then
    fail "Nord install accepted an unsupported variant"
fi
if theme_install install another-owner/nord --format nord; then
    fail "Nord adapter accepted a non-official repository"
fi
if theme_install install catppuccin/palette --format unknown --variant mocha; then
    fail "unsupported adapter format was accepted"
fi
if theme_install install catppuccin/palette --format catppuccin --format catppuccin --variant mocha; then
    fail "duplicate format option was accepted"
fi
if theme_install install catppuccin/palette --format catppuccin --variant mocha --variant latte; then
    fail "duplicate variant option was accepted"
fi
if theme_install install nordtheme/nord --format; then
    fail "format option without a value was accepted"
fi
if theme_install install catppuccin/palette --format catppuccin --variant; then
    fail "variant option without a value was accepted"
fi
[[ ! -e "$TEST_GIT_CLONE_MARKER" ]] || fail "invalid CLI arguments triggered retrieval"
assert_no_staging_directories

[[ "$(< "$CURRENT_THEME_FILE")" == current-before ]] || fail "current theme state changed"
[[ "$TEST_APPLY_CALLED" == 0 ]] || fail "theme_apply was called during installation"
printf 'Theme install tests passed.\n'
