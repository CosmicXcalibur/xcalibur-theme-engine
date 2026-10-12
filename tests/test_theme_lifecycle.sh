#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(dirname "$TEST_DIR")"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/xcalibur-lifecycle-test.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

THEMES_DIR="$TEST_ROOT/themes"
STATE_DIR="$TEST_ROOT/state"
CURRENT_THEME_FILE="$STATE_DIR/current_theme"
mkdir -p "$THEMES_DIR" "$STATE_DIR" "$TEST_ROOT/staging"
mkdir -p "$TEST_ROOT/staging/cat" "$TEST_ROOT/staging/rose" "$TEST_ROOT/staging/nord"

source "$REPOSITORY_ROOT/engine/lib/common.sh"
source "$REPOSITORY_ROOT/engine/lib/theme_manifest.sh"
source "$REPOSITORY_ROOT/engine/lib/theme_definition.sh"
source "$REPOSITORY_ROOT/engine/lib/theme_pack.sh"
source "$REPOSITORY_ROOT/engine/lib/theme_install.sh"
source "$REPOSITORY_ROOT/engine/commands/theme.sh"

TEST_APPLY_CALLED=0
theme_apply() { TEST_APPLY_CALLED=1; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
run_fail() {
    if "$@" > "$TEST_ROOT/output" 2>&1; then
        fail "unexpected success: $*"
    fi
}
contains() {
    rg -F -- "$1" "$TEST_ROOT/output" > /dev/null || fail "missing output: $1"
}
copy_pack() {
    local id="$1"
    mkdir "$THEMES_DIR/$id"
    cp -- "$TEST_DIR/fixtures/native/theme.conf" "$THEMES_DIR/$id/theme.conf"
    cp -- "$TEST_DIR/fixtures/native/palette.conf" "$THEMES_DIR/$id/palette.conf"
    sed -i "s/THEME_ID=native-fixture/THEME_ID=$id/" "$THEMES_DIR/$id/theme.conf"
}

# Install native and all three adapter formats through the existing shared
# installer. The real repository and active state are never used by this test.
theme_install_native_pack "$TEST_DIR/fixtures/native" > "$TEST_ROOT/output"
printf 'native-fixture\n' > "$CURRENT_THEME_FILE"
theme_install_staged_repository "$TEST_DIR/fixtures/catppuccin" catppuccin mocha "$TEST_ROOT/staging/cat" > "$TEST_ROOT/output"
theme_install_staged_repository "$TEST_DIR/fixtures/rose_pine" rose-pine moon "$TEST_ROOT/staging/rose" > "$TEST_ROOT/output"
theme_install_staged_repository "$TEST_DIR/fixtures/nord" nord '' "$TEST_ROOT/staging/nord" > "$TEST_ROOT/output"

for id in native-fixture catppuccin-mocha rose-pine-moon nord; do
    theme_info info "$id" > "$TEST_ROOT/output"
    contains "Theme ID: $id"
    contains 'Validation: valid'
    contains 'Definition version: 1'
    theme_validate validate "$id" > "$TEST_ROOT/output"
    contains "valid: $id"
    [[ -f "$THEMES_DIR/$id/theme.conf" && -f "$THEMES_DIR/$id/palette.conf" ]] || fail "pack missing: $id"
done
theme_info info catppuccin-mocha > "$TEST_ROOT/output"
contains 'Name: Catppuccin Mocha'
contains 'BACKGROUND=#1E1E2E'
theme_info info rose-pine-moon > "$TEST_ROOT/output"
contains 'BACKGROUND=#232136'
theme_info info nord > "$TEST_ROOT/output"
contains 'BACKGROUND=#2E3440'

# Selection uses the same pack validation before writing state. This apply is
# mocked, so no application or real active theme is changed.
theme_set set rose-pine-moon > "$TEST_ROOT/output"
[[ "$(< "$CURRENT_THEME_FILE")" == rose-pine-moon && "$TEST_APPLY_CALLED" == 1 ]] || fail 'valid adapter pack could not be selected'
TEST_APPLY_CALLED=0
theme_set set native-fixture > "$TEST_ROOT/output"
[[ "$(< "$CURRENT_THEME_FILE")" == native-fixture && "$TEST_APPLY_CALLED" == 1 ]] || fail 'valid native pack could not be selected'
TEST_APPLY_CALLED=0

before_state="$(sha256sum "$CURRENT_THEME_FILE")"
before_manifest="$(sha256sum "$THEMES_DIR/native-fixture/theme.conf")"
before_palette="$(sha256sum "$THEMES_DIR/native-fixture/palette.conf")"
theme_list > "$TEST_ROOT/output"
contains 'native-fixture'
contains 'yes'
contains 'valid'
theme_current > "$TEST_ROOT/output"
contains 'Native Fixture'
theme_validate validate --all > "$TEST_ROOT/output"
contains 'Checked: 4; valid: 4; invalid: 0'
[[ "$(sha256sum "$CURRENT_THEME_FILE")" == "$before_state" ]] || fail 'inspection changed state'
[[ "$(sha256sum "$THEMES_DIR/native-fixture/theme.conf")" == "$before_manifest" ]] || fail 'inspection changed manifest'
[[ "$(sha256sum "$THEMES_DIR/native-fixture/palette.conf")" == "$before_palette" ]] || fail 'inspection changed palette'
[[ "$TEST_APPLY_CALLED" == 0 ]] || fail 'inspection or installation applied a theme'

copy_pack missing-manifest
rm -- "$THEMES_DIR/missing-manifest/theme.conf"
copy_pack missing-palette
rm -- "$THEMES_DIR/missing-palette/palette.conf"
copy_pack bad-metadata
printf 'UNKNOWN_FIELD=value\n' >> "$THEMES_DIR/bad-metadata/theme.conf"
copy_pack bad-palette
printf 'ACCENT=#xyzxyz\n' >> "$THEMES_DIR/bad-palette/palette.conf"
copy_pack id-mismatch
sed -i 's/THEME_ID=id-mismatch/THEME_ID=other-pack/' "$THEMES_DIR/id-mismatch/theme.conf"
copy_pack bad-version
sed -i 's/XCALIBUR_DEFINITION_VERSION=1/XCALIBUR_DEFINITION_VERSION=2/' "$THEMES_DIR/bad-version/palette.conf"
copy_pack duplicate-metadata
printf 'THEME_NAME=Again\n' >> "$THEMES_DIR/duplicate-metadata/theme.conf"
copy_pack bad-alias
printf 'ACCENT=COLOR16\n' >> "$THEMES_DIR/bad-alias/palette.conf"
copy_pack duplicate-palette
printf 'BACKGROUND=#FFFFFF\n' >> "$THEMES_DIR/duplicate-palette/palette.conf"
copy_pack extra-file
printf 'unexpected\n' > "$THEMES_DIR/extra-file/extra.txt"
copy_pack symlink-palette
rm -- "$THEMES_DIR/symlink-palette/palette.conf"
ln -s "$TEST_DIR/fixtures/native/palette.conf" "$THEMES_DIR/symlink-palette/palette.conf"
copy_pack symlink-manifest
rm -- "$THEMES_DIR/symlink-manifest/theme.conf"
ln -s "$TEST_DIR/fixtures/native/theme.conf" "$THEMES_DIR/symlink-manifest/theme.conf"
ln -s "$TEST_DIR/fixtures/native" "$THEMES_DIR/symlink-pack"
printf 'not a directory\n' > "$THEMES_DIR/stray-file"

for id in missing-manifest missing-palette bad-metadata bad-palette id-mismatch bad-version duplicate-metadata bad-alias duplicate-palette extra-file symlink-palette symlink-manifest symlink-pack stray-file; do
    run_fail theme_validate validate "$id"
    contains "$id"
done
run_fail theme_validate validate bad-palette
contains 'invalid color value for ACCENT'
run_fail theme_validate validate bad-version
contains 'unsupported XCALIBUR_DEFINITION_VERSION'
run_fail theme_validate validate duplicate-palette
contains 'duplicate field: BACKGROUND'
run_fail theme_validate validate --all
contains 'valid: native-fixture'
contains 'invalid: missing-manifest'
contains 'invalid: bad-palette'
contains 'invalid: symlink-pack'
contains 'Checked: 18; valid: 4; invalid: 14'
unsafe_name=$'bad\nrow\033[31m'
mkdir "$THEMES_DIR/$unsafe_name"
theme_list > "$TEST_ROOT/output"
contains 'missing-manifest'
contains 'invalid:'
contains 'native-fixture'
if LC_ALL=C rg $'\033' "$TEST_ROOT/output" > /dev/null; then
    fail 'untrusted library name injected a terminal escape'
fi
contains '\n'
printf 'ghost-theme\n' > "$CURRENT_THEME_FILE"
theme_list > "$TEST_ROOT/output"
rg 'native-fixture.*\?' "$TEST_ROOT/output" > /dev/null || fail 'missing active pack was not shown as unknown'
printf 'native-fixture\n' > "$CURRENT_THEME_FILE"
run_fail theme_info info missing-manifest
contains 'Validation: invalid'
contains 'theme.conf'
run_fail theme_set set bad-palette
contains 'palette.conf'
GENERATED_DIR="$TEST_ROOT/generated"
source "$REPOSITORY_ROOT/engine/services/color_engine.sh"
printf 'bad-palette\n' > "$CURRENT_THEME_FILE"
run_fail color_apply_selected_theme_overlay
contains 'palette.conf'
printf 'native-fixture\n' > "$CURRENT_THEME_FILE"
[[ "$(sha256sum "$CURRENT_THEME_FILE")" == "$before_state" ]] || fail 'failed validation or set changed state'
[[ "$TEST_APPLY_CALLED" == 0 ]] || fail 'invalid theme was applied'

# Declarative metadata is displayed safely and never executed.
copy_pack untrusted-text
printf 'THEME_NAME=$(touch %s)\n' "$TEST_ROOT/remote-code-ran" > "$TEST_ROOT/untrusted-name"
sed -i "s|^THEME_NAME=.*|$(< "$TEST_ROOT/untrusted-name")|" "$THEMES_DIR/untrusted-text/theme.conf"
theme_info info untrusted-text > "$TEST_ROOT/output"
contains 'touch'
[[ ! -e "$TEST_ROOT/remote-code-ran" ]] || fail 'manifest content was executed'

run_fail theme_remove remove native-fixture
contains 'switch to another valid theme first'
run_fail theme_remove remove missing-theme
contains 'not installed'
for unsafe in ../native-fixture /tmp/native-fixture ./native-fixture '--help'; do
    run_fail theme_remove remove "$unsafe"
done
[[ -d "$THEMES_DIR/native-fixture" ]] || fail 'unsafe removal damaged active pack'
[[ -L "$THEMES_DIR/symlink-pack" ]] || fail 'symlinked pack was altered'
run_fail theme_remove remove symlink-pack
[[ -L "$THEMES_DIR/symlink-pack" ]] || fail 'symlinked pack was removed'
[[ -f "$TEST_DIR/fixtures/native/theme.conf" ]] || fail 'symlink target changed'

# A missing, malformed, or symlinked state file cannot authorize removal.
cp -- "$CURRENT_THEME_FILE" "$TEST_ROOT/saved-state"
rm -- "$CURRENT_THEME_FILE"
run_fail theme_remove remove nord
printf 'ghost-theme\n' > "$CURRENT_THEME_FILE"
run_fail theme_remove remove nord
contains 'missing or unsafe pack'
printf '../unknown\n' > "$CURRENT_THEME_FILE"
run_fail theme_remove remove nord
printf 'native-fixture\nother-theme\n' > "$CURRENT_THEME_FILE"
run_fail theme_remove remove nord
printf 'native-fixture\0\n' > "$CURRENT_THEME_FILE"
run_fail theme_remove remove nord
contains 'unexpected bytes'
printf '%0257d' 0 > "$CURRENT_THEME_FILE"
run_fail theme_remove remove nord
contains 'too large'
rm -- "$CURRENT_THEME_FILE"
ln -s "$TEST_ROOT/saved-state" "$CURRENT_THEME_FILE"
run_fail theme_remove remove nord
rm -- "$CURRENT_THEME_FILE"
cp -- "$TEST_ROOT/saved-state" "$CURRENT_THEME_FILE"
[[ -d "$THEMES_DIR/nord" ]] || fail 'state failure removed a pack'

# Simulate a filesystem refusal without changing the test directory's real
# permissions (tests may run as root on CI).
rm() {
    if [[ "$*" == *"$THEMES_DIR/nord"* ]]; then
        return 1
    fi
    command rm "$@"
}
run_fail theme_remove remove nord
unset -f rm
contains 'Unable to remove theme directory'
[[ -d "$THEMES_DIR/nord" ]] || fail 'failed deletion lost the pack'

# Removal may clear a malformed inactive pack, but never its neighbor or state.
printf 'outside library\n' > "$TEST_ROOT/neighbor-file"
ln -s "$TEST_ROOT/neighbor-file" "$THEMES_DIR/bad-metadata/outside-link"
theme_remove remove bad-metadata > "$TEST_ROOT/output"
[[ ! -e "$THEMES_DIR/bad-metadata" ]] || fail 'malformed inactive pack was not removed'
[[ "$(< "$TEST_ROOT/neighbor-file")" == 'outside library' ]] || fail 'removal followed a symlink'
theme_remove remove catppuccin-mocha > "$TEST_ROOT/output"
[[ ! -e "$THEMES_DIR/catppuccin-mocha" ]] || fail 'inactive pack was not removed'
[[ -d "$THEMES_DIR/rose-pine-moon" && -d "$THEMES_DIR/native-fixture" ]] || fail 'neighboring pack changed'
[[ "$(sha256sum "$CURRENT_THEME_FILE")" == "$before_state" ]] || fail 'removal changed active state'
[[ "$TEST_APPLY_CALLED" == 0 ]] || fail 'removal applied a theme'

# A configured library symlink cannot redirect validation or deletion.
real_themes_dir="$THEMES_DIR"
ln -s "$real_themes_dir" "$TEST_ROOT/linked-themes"
THEMES_DIR="$TEST_ROOT/linked-themes"
run_fail theme_validate validate --all
run_fail theme_remove remove nord
run_fail theme_install_native_pack "$TEST_DIR/fixtures/native"
[[ -d "$real_themes_dir/nord" ]] || fail 'library symlink escaped removal'
THEMES_DIR="$real_themes_dir"

printf 'Theme lifecycle tests passed.\n'
