#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(dirname "$TEST_DIR")"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/xcalibur-transaction-test.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

HOME="$TEST_ROOT/home with spaces"
THEMES_DIR="$TEST_ROOT/themes"
RUNTIME_DIR="$TEST_ROOT/runtime"
STATE_DIR="$RUNTIME_DIR/state"
CURRENT_THEME_FILE="$STATE_DIR/current_theme"
GENERATED_DIR="$RUNTIME_DIR/generated"
MODULES_DIR="$REPOSITORY_ROOT/modules"
ENGINE_DIR="$REPOSITORY_ROOT/engine"
CWAL_COLORS="$HOME/.cache/cwal/colors.sh"
RUNTIME_COLORS="$GENERATED_DIR/colors.sh"
WALLPAPER_DIR="$TEST_ROOT/wallpapers"
mkdir -p "$HOME/.config/kitty" "$THEMES_DIR" "$STATE_DIR" "$GENERATED_DIR" "$WALLPAPER_DIR"
printf 'old wallpaper\n' > "$WALLPAPER_DIR/old image.png"
printf 'new wallpaper\n' > "$WALLPAPER_DIR/new image.png"
printf '%s\n' "$WALLPAPER_DIR/old image.png" > "$STATE_DIR/current_wallpaper"
printf 'old-theme\n' > "$CURRENT_THEME_FILE"

source "$ENGINE_DIR/lib/common.sh"
source "$ENGINE_DIR/lib/theme_manifest.sh"
source "$ENGINE_DIR/lib/theme_definition.sh"
source "$ENGINE_DIR/lib/theme_pack.sh"
source "$ENGINE_DIR/services/color_engine.sh"
source "$ENGINE_DIR/renderer/template.sh"
source "$ENGINE_DIR/services/wallpaper.sh"
source "$ENGINE_DIR/lib/modules.sh"
load_modules
source "$ENGINE_DIR/services/apply.sh"
source "$ENGINE_DIR/commands/theme.sh"

make_pack() {
    local id="$1"
    mkdir "$THEMES_DIR/$id"
    cp "$TEST_DIR/fixtures/native/theme.conf" "$THEMES_DIR/$id/theme.conf"
    cp "$TEST_DIR/fixtures/native/palette.conf" "$THEMES_DIR/$id/palette.conf"
    sed -i "s/THEME_ID=native-fixture/THEME_ID=$id/" "$THEMES_DIR/$id/theme.conf"
}
make_pack old-theme
make_pack native-fixture
sed -i 's/BACKGROUND=#101010/BACKGROUND=#303030/' "$THEMES_DIR/old-theme/palette.conf"

cwal() {
    local output=""
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --out-dir) output="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    [[ -n "$output" ]] || return 1
    if [[ "${TEST_FAIL_CWAL:-0}" == 1 ]]; then return 1; fi
    mkdir -m 700 -- "$output/schemes"
    printf '%s\n' "${TEST_CWAL_SCHEME_VALUE:-generated scheme}" > "$output/schemes/shared.cwal"
    if [[ "${TEST_CWAL_NEW_SCHEME:-0}" == 1 ]]; then
        printf 'new scheme\n' > "$output/schemes/rollback-new.cwal"
    fi
    if [[ "${TEST_CWAL_EXTRA_DIR:-0}" == 1 ]]; then
        mkdir "$output/unexpected-directory"
    fi
    cat > "$output/colors.sh" <<'EOF'
background='#101010'
foreground='#f0f0f0'
cursor='#f0f0f0'
color0='#101010'
color1='#a10000'
color2='#00a100'
color3='#a1a100'
color4='#0000a1'
color5='#a100a1'
color6='#00a1a1'
color7='#a1a1a1'
color8='#202020'
color9='#b10000'
color10='#00b100'
color11='#b1b100'
color12='#0000b1'
color13='#b100b1'
color14='#00b1b1'
color15='#f0f0f0'
EOF
}

TEST_RELOADS=""
gtk_reload() { TEST_RELOADS+=" gtk"; [[ "${TEST_FAIL_RELOAD:-}" != gtk ]]; }
kitty() {
    printf '%s\n' "$@" > "$TEST_ROOT/kitty-call"
    [[ "${TEST_FAIL_RELOAD:-}" != kitty ]]
}
swaync_reload() { TEST_RELOADS+=" swaync"; [[ "${TEST_FAIL_RELOAD:-}" != swaync ]]; }
waybar_reload() { TEST_RELOADS+=" waybar"; [[ "${TEST_FAIL_RELOAD:-}" != waybar ]]; }
wofi_reload() { TEST_RELOADS+=" wofi"; [[ "${TEST_FAIL_RELOAD:-}" != wofi ]]; }
wallpaper_reload() {
    TEST_RELOADS+=" wallpaper"
    printf '%s\n' "$1" >> "$TEST_ROOT/wallpaper-reloads"
    [[ "${TEST_FAIL_RELOAD:-}" != wallpaper ]]
}

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
run_fail() {
    if "$@" > "$TEST_ROOT/output" 2>&1; then
        fail "unexpected success: $*"
    fi
}
contains() { rg -F -- "$1" "$TEST_ROOT/output" > /dev/null || fail "missing output: $1"; }
assert_no_transactions() {
    local transactions=("$RUNTIME_DIR"/transactions/txn.*)
    local path
    for path in "${transactions[@]}"; do
        [[ -e "$path" ]] && fail "transaction artifact remains: $path"
    done
    return 0
}

# Existing and absent destinations are both part of a successful apply.
printf 'previous kitty\n' > "$HOME/.config/kitty/current-theme.conf"
chmod 600 "$HOME/.config/kitty/current-theme.conf"
printf 'allow_remote_control yes\nfont_size 12\n' > "$HOME/.config/kitty/kitty.conf"
chmod 600 "$HOME/.config/kitty/kitty.conf"
mkdir -m 700 -p "$HOME/.cache/cwal/schemes"
printf 'unrelated scheme\n' > "$HOME/.cache/cwal/schemes/keep.cwal"
printf 'previous scheme\n' > "$HOME/.cache/cwal/schemes/shared.cwal"
TEST_FAIL_RELOAD=kitty
run_fail theme_set set native-fixture
unset TEST_FAIL_RELOAD
contains "Required reload failed for module 'kitty'"
[[ "$(< "$HOME/.config/kitty/kitty.conf")" == $'allow_remote_control yes\nfont_size 12' ]] ||
    fail 'failed reload changed the original Kitty main config'
[[ "$(< "$HOME/.config/kitty/current-theme.conf")" == 'previous kitty' ]] ||
    fail 'failed reload changed the original Kitty theme file'
[[ "$(< "$CURRENT_THEME_FILE")" == old-theme ]] || fail 'failed reload changed active state'
assert_no_transactions
theme_set set native-fixture > "$TEST_ROOT/output"
[[ "$(< "$CURRENT_THEME_FILE")" == native-fixture ]] || fail 'active state was not committed'
rg -F 'background #101010' "$HOME/.config/kitty/current-theme.conf" > /dev/null || fail 'Kitty output was not installed'
rg -F 'allow_remote_control yes' "$HOME/.config/kitty/kitty.conf" > /dev/null || fail 'Kitty remote control setting changed'
rg -F 'font_size 12' "$HOME/.config/kitty/kitty.conf" > /dev/null || fail 'unrelated Kitty setting changed'
[[ "$(rg -c '^include current-theme\.conf$' "$HOME/.config/kitty/kitty.conf")" == 1 ]] ||
    fail 'Kitty theme include missing or duplicated'
[[ "$(stat -c %a "$HOME/.config/kitty/kitty.conf")" == 600 ]] || fail 'Kitty main config mode changed'
mapfile -t kitty_args < "$TEST_ROOT/kitty-call"
[[ "${#kitty_args[@]}" -eq 5 && "${kitty_args[0]}" == @ && "${kitty_args[1]}" == set-colors &&
   "${kitty_args[2]}" == --all && "${kitty_args[3]}" == --configured &&
   "${kitty_args[4]}" == "$HOME/.config/kitty/current-theme.conf" ]] ||
    fail 'Kitty reload did not target all windows and configured colors'
theme_set set native-fixture > "$TEST_ROOT/output"
[[ "$(rg -c '^include current-theme\.conf$' "$HOME/.config/kitty/kitty.conf")" == 1 ]] ||
    fail 'repeated theme application duplicated Kitty include'
[[ -f "$HOME/.config/waybar/styles/colors/xcalibur.css" ]] || fail 'new Waybar output was not installed'
[[ -f "$HOME/.config/gtk-3.0/gtk.css" && -f "$HOME/.config/gtk-4.0/gtk.css" ]] || fail 'GTK outputs missing'
[[ -f "$HOME/.config/hypr/hyprlock.conf" && -f "$HOME/.config/swaync/style.css" ]] || fail 'other module outputs missing'
[[ -f "$GENERATED_DIR/colors.sh" && -f "$HOME/.cache/cwal/colors.sh" ]] || fail 'generated palettes missing'
[[ "$(< "$HOME/.cache/cwal/schemes/shared.cwal")" == 'generated scheme' ]] || fail 'CWAL scheme was not installed'
[[ "$(< "$HOME/.cache/cwal/schemes/keep.cwal")" == 'unrelated scheme' ]] || fail 'unrelated CWAL scheme changed'
[[ "$(stat -c %a "$HOME/.cache/cwal/schemes")" == 700 ]] || fail 'CWAL schemes directory mode changed'
assert_no_transactions

# Existing legacy backup files remain outside subsequent replacement plans.
cp "$HOME/.config/hypr/hyprlock.conf" "$HOME/.config/hypr/hyprlock.conf.xcalibur-backup"
cp "$HOME/.config/swaync/style.css" "$HOME/.config/swaync/style.css.xcalibur-backup"

fingerprint() {
    find "$HOME/.config" "$HOME/.cache" "$GENERATED_DIR" "$STATE_DIR" -type f -print0 |
        sort -z | xargs -0 -r sha256sum
}
baseline="$(fingerprint)"
baseline_kitty_mode="$(stat -c %a "$HOME/.config/kitty/current-theme.conf")"
baseline_kitty_main_mode="$(stat -c %a "$HOME/.config/kitty/kitty.conf")"
assert_baseline() {
    [[ "$(fingerprint)" == "$baseline" ]] || fail 'failure did not restore all owned files and state'
    [[ "$(stat -c %a "$HOME/.config/kitty/current-theme.conf")" == "$baseline_kitty_mode" ]] ||
        fail 'rollback did not restore Kitty permissions'
    [[ "$(stat -c %a "$HOME/.config/kitty/kitty.conf")" == "$baseline_kitty_main_mode" ]] ||
        fail 'rollback did not restore Kitty main config permissions'
    assert_no_transactions
}

# A missing main config is created only on commit; failure removes it again.
mv "$HOME/.config/kitty/kitty.conf" "$TEST_ROOT/kitty-main.saved"
TEST_FAIL_RELOAD=kitty
run_fail theme_set set old-theme
unset TEST_FAIL_RELOAD
[[ ! -e "$HOME/.config/kitty/kitty.conf" ]] || fail 'rollback left a new Kitty main config'
mv "$TEST_ROOT/kitty-main.saved" "$HOME/.config/kitty/kitty.conf"
assert_baseline

# Config input and destination checks reject symlinks and unexpected objects.
printf 'outside Kitty settings\n' > "$TEST_ROOT/kitty-outside.conf"
mv "$HOME/.config/kitty/kitty.conf" "$TEST_ROOT/kitty-main.saved"
ln -s "$TEST_ROOT/kitty-outside.conf" "$HOME/.config/kitty/kitty.conf"
run_fail theme_set set old-theme
contains 'unsafe or oversized Kitty config'
[[ "$(< "$TEST_ROOT/kitty-outside.conf")" == 'outside Kitty settings' ]] || fail 'Kitty symlink target changed'
rm -- "$HOME/.config/kitty/kitty.conf"
mv "$TEST_ROOT/kitty-main.saved" "$HOME/.config/kitty/kitty.conf"
assert_baseline

mv "$HOME/.config/kitty/current-theme.conf" "$TEST_ROOT/kitty-theme.saved"
ln -s "$TEST_ROOT/kitty-outside.conf" "$HOME/.config/kitty/current-theme.conf"
run_fail theme_set set old-theme
contains 'unsafe filesystem object'
[[ "$(< "$TEST_ROOT/kitty-outside.conf")" == 'outside Kitty settings' ]] || fail 'Kitty theme symlink target changed'
rm -- "$HOME/.config/kitty/current-theme.conf"
mv "$TEST_ROOT/kitty-theme.saved" "$HOME/.config/kitty/current-theme.conf"
assert_baseline
mv "$HOME/.config/kitty/kitty.conf" "$TEST_ROOT/kitty-main.saved"
mkdir "$HOME/.config/kitty/kitty.conf"
run_fail theme_set set old-theme
contains 'unsafe or oversized Kitty config'
rmdir "$HOME/.config/kitty/kitty.conf"
mv "$TEST_ROOT/kitty-main.saved" "$HOME/.config/kitty/kitty.conf"
assert_baseline

# A repeated include is reported rather than silently changing user settings.
cp "$HOME/.config/kitty/kitty.conf" "$TEST_ROOT/kitty-main.saved"
printf 'include current-theme.conf\n' >> "$HOME/.config/kitty/kitty.conf"
run_fail theme_set set old-theme
contains 'duplicate Kitty theme includes'
cp "$TEST_ROOT/kitty-main.saved" "$HOME/.config/kitty/kitty.conf"
assert_baseline

# CWAL's real output layout includes schemes/. A changed scheme and a newly
# created scheme must both roll back without disturbing another cache entry.
TEST_CWAL_SCHEME_VALUE='attempted scheme'
TEST_CWAL_NEW_SCHEME=1
TEST_FAIL_RELOAD=kitty
run_fail theme_set set old-theme
unset TEST_CWAL_SCHEME_VALUE TEST_CWAL_NEW_SCHEME TEST_FAIL_RELOAD
[[ ! -e "$HOME/.cache/cwal/schemes/rollback-new.cwal" ]] || fail 'new CWAL scheme survived rollback'
[[ "$(< "$HOME/.cache/cwal/schemes/shared.cwal")" == 'generated scheme' ]] || fail 'existing CWAL scheme was not restored'
assert_baseline

TEST_CWAL_EXTRA_DIR=1
run_fail theme_set set old-theme
unset TEST_CWAL_EXTRA_DIR
contains 'Unexpected cwal output directory'
assert_baseline

# The schemes directory must remain a real directory; unsafe replacements
# are rejected before any live destination changes.
mv "$HOME/.cache/cwal/schemes" "$TEST_ROOT/schemes.saved"
ln -s "$TEST_ROOT/schemes.saved" "$HOME/.cache/cwal/schemes"
run_fail theme_set set old-theme
contains 'unsafe directory component'
rm -- "$HOME/.cache/cwal/schemes"
mv "$TEST_ROOT/schemes.saved" "$HOME/.cache/cwal/schemes"
assert_baseline
mv "$HOME/.cache/cwal/schemes" "$TEST_ROOT/schemes.saved"
printf 'unexpected file\n' > "$HOME/.cache/cwal/schemes"
run_fail theme_set set old-theme
contains 'unsafe directory component'
rm -- "$HOME/.cache/cwal/schemes"
mv "$TEST_ROOT/schemes.saved" "$HOME/.cache/cwal/schemes"
assert_baseline
mv "$HOME/.cache/cwal/schemes" "$TEST_ROOT/schemes.saved"
TEST_FAIL_RELOAD=kitty
run_fail theme_set set old-theme
unset TEST_FAIL_RELOAD
[[ ! -e "$HOME/.cache/cwal/schemes" ]] || fail 'rollback left a newly created CWAL schemes directory'
mv "$TEST_ROOT/schemes.saved" "$HOME/.cache/cwal/schemes"
assert_baseline
mv "$HOME/.cache/cwal/schemes/shared.cwal" "$TEST_ROOT/shared.saved"
mkfifo "$HOME/.cache/cwal/schemes/shared.cwal"
run_fail theme_set set old-theme
contains 'unsafe filesystem object'
rm -- "$HOME/.cache/cwal/schemes/shared.cwal"
mv "$TEST_ROOT/shared.saved" "$HOME/.cache/cwal/schemes/shared.cwal"
assert_baseline

transaction_call_real() { python3 "$THEME_TRANSACTION_HELPER" "$@"; }
theme_txn_call() {
    local action="$1"
    case "${TEST_INJECT:-}:$action" in
        install_first:install|install_second:install|mkdir:install|rollback_failure:install|copy:install|rename:install|\
        commit_before:commit|commit_after:commit|state_rollback_failure:commit|\
        rollback_failure:rollback|state_rollback_failure:rollback|\
        cleanup:finish|partial_cleanup:finish|rollback_cleanup:rollback)
            python3 "$TEST_DIR/transaction_inject.py" "$action" "$TEST_INJECT" "$2"
            ;;
        *) transaction_call_real "$@" ;;
    esac
}

# Preparation failures do not touch a live destination.
printf 'UNKNOWN_FIELD=x\n' >> "$THEMES_DIR/old-theme/theme.conf"
run_fail theme_set set old-theme
contains 'invalid'
sed -i '$d' "$THEMES_DIR/old-theme/theme.conf"
assert_baseline
printf 'ACCENT=#oops00\n' >> "$THEMES_DIR/old-theme/palette.conf"
run_fail theme_set set old-theme
contains 'invalid'
sed -i '$d' "$THEMES_DIR/old-theme/palette.conf"
assert_baseline
TEST_FAIL_CWAL=1
run_fail theme_set set old-theme
unset TEST_FAIL_CWAL
contains 'Palette preparation failed'
assert_baseline
kitty_render() { return 1; }
run_fail theme_set set old-theme
source "$MODULES_DIR/kitty/module.sh"
contains 'Rendering failed'
assert_baseline
kitty_render() {
    render_template "$MODULES_DIR/kitty/templates/kitty.conf.template" "$GENERATED_DIR/kitty.conf" || return 1
    printf '{{BROKEN}}\n' >> "$GENERATED_DIR/kitty.conf"
}
run_fail theme_set set old-theme
source "$MODULES_DIR/kitty/module.sh"
contains 'Prepared output validation failed'
assert_baseline

# Snapshot validation rejects paths and objects that cannot be restored safely.
printf 'unrelated\n' > "$TEST_ROOT/outside.conf"
kitty_transaction_plan() { theme_txn_plan "$GENERATED_DIR/kitty.conf" "$TEST_ROOT/outside.conf"; }
run_fail theme_set set old-theme
source "$MODULES_DIR/kitty/install.sh"
contains 'unapproved destination'
[[ "$(< "$TEST_ROOT/outside.conf")" == unrelated ]] || fail 'outside file changed'
assert_baseline
mv "$HOME/.config/wofi/style.css" "$TEST_ROOT/wofi.saved"
ln -s "$TEST_ROOT/outside.conf" "$HOME/.config/wofi/style.css"
run_fail theme_set set old-theme
contains 'unsafe filesystem object'
[[ "$(< "$TEST_ROOT/outside.conf")" == unrelated ]] || fail 'symlink target changed'
rm -- "$HOME/.config/wofi/style.css"
mv "$TEST_ROOT/wofi.saved" "$HOME/.config/wofi/style.css"
assert_baseline
mv "$HOME/.config/wofi/style.css" "$TEST_ROOT/wofi.saved"
mkdir "$HOME/.config/wofi/style.css"
run_fail theme_set set old-theme
contains 'unsafe filesystem object'
rmdir "$HOME/.config/wofi/style.css"
mv "$TEST_ROOT/wofi.saved" "$HOME/.config/wofi/style.css"
assert_baseline
printf '../bad\n' > "$CURRENT_THEME_FILE"
run_fail theme_set set old-theme
contains 'invalid theme ID'
printf 'native-fixture\n' > "$CURRENT_THEME_FILE"
assert_baseline
cp "$STATE_DIR/current_wallpaper" "$TEST_ROOT/wallpaper.saved"
printf '../bad-wallpaper\n' > "$STATE_DIR/current_wallpaper"
run_fail theme_set set old-theme
contains 'unsafe or missing file'
cp "$TEST_ROOT/wallpaper.saved" "$STATE_DIR/current_wallpaper"
assert_baseline

# Files and legacy backups created during an unsuccessful transaction vanish.
mv "$HOME/.config/wofi/style.css" "$TEST_ROOT/wofi.saved"
mv "$HOME/.config/hypr/hyprlock.conf.xcalibur-backup" "$TEST_ROOT/hyprlock-backup.saved"
mv "$HOME/.config/swaync/style.css.xcalibur-backup" "$TEST_ROOT/swaync-backup.saved"
TEST_FAIL_RELOAD=kitty
run_fail theme_set set old-theme
unset TEST_FAIL_RELOAD
[[ ! -e "$HOME/.config/wofi/style.css" ]] || fail 'rollback left a newly created Wofi file'
[[ ! -e "$HOME/.config/hypr/hyprlock.conf.xcalibur-backup" ]] || fail 'rollback left a new Hyprlock backup'
[[ ! -e "$HOME/.config/swaync/style.css.xcalibur-backup" ]] || fail 'rollback left a new SwayNC backup'
mv "$TEST_ROOT/wofi.saved" "$HOME/.config/wofi/style.css"
mv "$TEST_ROOT/hyprlock-backup.saved" "$HOME/.config/hypr/hyprlock.conf.xcalibur-backup"
mv "$TEST_ROOT/swaync-backup.saved" "$HOME/.config/swaync/style.css.xcalibur-backup"
assert_baseline

# A state file absent before commit remains absent after a failed commit.
mv "$CURRENT_THEME_FILE" "$TEST_ROOT/theme-state.saved"
TEST_INJECT=commit_after
run_fail theme_set set old-theme
unset TEST_INJECT
[[ ! -e "$CURRENT_THEME_FILE" ]] || fail 'rollback left a newly created active state file'
mv "$TEST_ROOT/theme-state.saved" "$CURRENT_THEME_FILE"
assert_baseline

# Install, directory, and state failures restore every owned file.
chmod 600 "$HOME/.config/kitty/current-theme.conf"
baseline_kitty_mode=600
for injection in install_first install_second copy rename mkdir commit_before commit_after; do
    TEST_INJECT="$injection"
    run_fail theme_set set old-theme
    unset TEST_INJECT
    assert_baseline
done
TEST_FAIL_RELOAD=kitty
run_fail theme_set set old-theme
unset TEST_FAIL_RELOAD
contains "Required reload failed for module 'kitty'"
assert_baseline

# A rollback write failure retains its authenticated journal for explicit
# recovery. The next application refuses to proceed until recovery succeeds.
TEST_INJECT=rollback_failure
run_fail theme_set set old-theme
unset TEST_INJECT
contains 'Rollback failed'
run_fail theme_set set old-theme
contains 'incomplete transaction'
theme_transaction_recover > "$TEST_ROOT/output"
assert_baseline

TEST_INJECT=state_rollback_failure
run_fail theme_set set old-theme
unset TEST_INJECT
contains 'Rollback failed'
[[ "$(< "$CURRENT_THEME_FILE")" == old-theme ]] || fail 'state failure injection did not reach the state write'
theme_transaction_recover > "$TEST_ROOT/output"
assert_baseline

# Rollback cleanup and committed cleanup failures retain an explicit artifact.
TEST_INJECT=rollback_cleanup
TEST_FAIL_RELOAD=kitty
run_fail theme_set set old-theme
unset TEST_INJECT TEST_FAIL_RELOAD
contains 'Rollback failed'
theme_transaction_recover > "$TEST_ROOT/output"
assert_baseline

TEST_INJECT=cleanup
run_fail theme_set set old-theme
unset TEST_INJECT
contains 'committed, but cleanup failed'
[[ "$(< "$CURRENT_THEME_FILE")" == old-theme ]] || fail 'cleanup failure rolled back committed state'
theme_transaction_recover > "$TEST_ROOT/output"
assert_no_transactions
theme_set set native-fixture > "$TEST_ROOT/output"
chmod 600 "$HOME/.config/kitty/current-theme.conf"
assert_baseline

TEST_INJECT=partial_cleanup
run_fail theme_set set old-theme
unset TEST_INJECT
contains 'committed, but cleanup failed'
theme_transaction_recover > "$TEST_ROOT/output"
assert_no_transactions
theme_set set native-fixture > "$TEST_ROOT/output"
chmod 600 "$HOME/.config/kitty/current-theme.conf"
assert_baseline

# Interrupted preparation is detected. A changed journal is never replayed.
interrupted="$(transaction_call_real create "$RUNTIME_DIR/transactions" "$HOME" "$GENERATED_DIR" \
    "${CWAL_COLORS%/*}" "$CURRENT_THEME_FILE" "$STATE_DIR/current_wallpaper")"
run_fail theme_set set old-theme
contains 'incomplete transaction'
cp "$interrupted/journal.json" "$TEST_ROOT/journal.saved"
printf 'tamper\n' >> "$interrupted/journal.json"
run_fail theme_transaction_recover
contains 'tampered journal'
cp "$TEST_ROOT/journal.saved" "$interrupted/journal.json"
theme_transaction_recover > "$TEST_ROOT/output"
assert_baseline

# Wallpaper state joins the transaction; a later reload failure restores it.
wallpaper_set 'new image.png' > "$TEST_ROOT/output"
[[ "$(< "$STATE_DIR/current_wallpaper")" == "$WALLPAPER_DIR/new image.png" ]] || fail 'wallpaper state was not committed'
wallpaper_baseline="$(fingerprint)"
TEST_FAIL_RELOAD=kitty
run_fail wallpaper_set 'old image.png'
unset TEST_FAIL_RELOAD
[[ "$(fingerprint)" == "$wallpaper_baseline" ]] || fail 'wallpaper failure changed files or state'
[[ "$(tail -n 1 "$TEST_ROOT/wallpaper-reloads")" == "$WALLPAPER_DIR/new image.png" ]] ||
    fail 'previous live wallpaper was not requested after rollback'
assert_no_transactions

# Required reload functions report a failed stop operation without touching
# the live desktop. These command mocks take precedence over the real tools.
pgrep() { return 0; }
pkill() { return 1; }
source "$MODULES_DIR/waybar/reload.sh"
run_fail waybar_reload
contains 'Unable to stop the running Waybar instance'
source "$MODULES_DIR/swaync/reload.sh"
run_fail swaync_reload
contains 'Unable to stop the running SwayNC instance'

printf 'Theme transaction tests passed.\n'
