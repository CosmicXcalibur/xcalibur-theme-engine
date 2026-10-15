#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE_DIR="$ROOT/engine"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/xcalibur-tests.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP"' EXIT
EXPECTED_FAILURE_LOG="$TEST_TMP/expected-failures.log"
expect_failure() {
    local label="$1"
    shift
    if "$@" >> "$EXPECTED_FAILURE_LOG" 2>&1; then
        printf 'Unexpected success: %s\n' "$label" >&2
        return 1
    fi
    printf '[expected failure] %s\n' "$label"
}

source "$ROOT/engine/lib/common.sh"
source "$ROOT/engine/lib/theme_manifest.sh"
source "$ROOT/engine/lib/theme_definition.sh"
source "$ROOT/engine/lib/color_data.sh"
source "$ROOT/engine/lib/theme_install.sh"
source "$ROOT/engine/lib/filesystem.sh"
source "$ROOT/engine/lib/modules.sh"

GENERATED_DIR="$TEST_TMP/generated"
STATE_DIR="$TEST_TMP/state"
THEMES_DIR="$TEST_TMP/themes"
MODULES_DIR="$TEST_TMP/modules"
CURRENT_THEME_FILE="$STATE_DIR/current_theme"
CWAL_COLORS="$TEST_TMP/cwal.sh"
RUNTIME_COLORS="$GENERATED_DIR/colors.sh"
mkdir -p "$GENERATED_DIR" "$STATE_DIR" "$THEMES_DIR" "$MODULES_DIR"
ln -s "$ROOT/engine/bin/theme" "$TEST_TMP/theme"
[[ "$("$TEST_TMP/theme" status)" == *"Engine: $ROOT"* ]]
source "$ROOT/engine/services/color_engine.sh"
source "$ROOT/engine/renderer/template.sh"
source "$ROOT/engine/services/apply.sh"
source "$ROOT/engine/services/wallpaper.sh"
source "$ROOT/engine/commands/theme.sh"
source "$ROOT/engine/commands/status.sh"
source "$ROOT/modules/kitty/reload.sh"
source "$ROOT/modules/waybar/reload.sh"
source "$ROOT/modules/swaync/reload.sh"
source "$ROOT/modules/hyprlock/reload.sh"
source "$ROOT/modules/wofi/reload.sh"
source "$ROOT/modules/gtk/reload.sh"
CWAL_COLORS="$TEST_TMP/cwal.sh"
RUNTIME_COLORS="$GENERATED_DIR/colors.sh"
WALLPAPER_BACKEND=unsupported
expect_failure 'unsupported wallpaper backend' wallpaper_reload "$TEST_TMP/unused.png"
unset WALLPAPER_BACKEND

mkdir -p "$TEST_TMP/validate/xcalibur-test"
cp -- "$ROOT/themes/xcalibur-test/theme.conf" "$ROOT/themes/xcalibur-test/palette.conf" \
    "$TEST_TMP/validate/xcalibur-test/"
theme_manifest_load "$TEST_TMP/validate/xcalibur-test/theme.conf" xcalibur-test
theme_definition_load "$TEST_TMP/validate/xcalibur-test/palette.conf" xcalibur-test
sed -i 's/THEME_VERSION=1.0.0/THEME_VERSION=invalid/' "$TEST_TMP/validate/xcalibur-test/theme.conf"
expect_failure 'invalid theme version' theme_manifest_load "$TEST_TMP/validate/xcalibur-test/theme.conf" xcalibur-test
cp -- "$ROOT/themes/xcalibur-test/theme.conf" "$TEST_TMP/validate/xcalibur-test/theme.conf"
printf 'ACCENT=#123456\n' >> "$TEST_TMP/validate/xcalibur-test/palette.conf"
expect_failure 'duplicate palette role' theme_definition_load "$TEST_TMP/validate/xcalibur-test/palette.conf" xcalibur-test
cp -- "$ROOT/themes/xcalibur-test/palette.conf" "$TEST_TMP/validate/xcalibur-test/palette.conf"
sed -i 's/ACCENT=COLOR6/ACCENT=not-a-color/' "$TEST_TMP/validate/xcalibur-test/palette.conf"
expect_failure 'invalid palette color' theme_definition_load "$TEST_TMP/validate/xcalibur-test/palette.conf" xcalibur-test
head -c 262145 /dev/zero > "$TEST_TMP/validate/xcalibur-test/palette.conf"
expect_failure 'oversized native palette' theme_definition_load "$TEST_TMP/validate/xcalibur-test/palette.conf" xcalibur-test
printf 'invalid id\n' > "$CURRENT_THEME_FILE"
THEME_ROOT="$ROOT"
expect_failure 'malformed status state' command_status
rm -f -- "$CURRENT_THEME_FILE"
saved_themes_dir="$THEMES_DIR"
THEMES_DIR="$TEST_TMP/missing-themes"
expect_failure 'missing themes directory' theme_list
THEMES_DIR="$saved_themes_dir"
mkdir -p "$THEMES_DIR/broken"
printf 'bad data\n' > "$THEMES_DIR/broken/theme.conf"
printf 'XCALIBUR_DEFINITION_VERSION=1\n' > "$THEMES_DIR/broken/palette.conf"
[[ "$(theme_list 2>&1)" == *'Skipping broken'* ]]
rm -rf -- "$THEMES_DIR/broken"

{
    printf "background='#010203'\nforeground='#eeeeee'\ncursor='#ffffff'\n"
    for n in {0..15}; do printf "color%d='#%06x'\n" "$n" "$n"; done
    printf 'touch "%s"\n' "$TEST_TMP/executed"
} > "$CWAL_COLORS"

wallpaper="$TEST_TMP/wallpaper with spaces.png"
touch "$wallpaper"
printf '%s\n' "$wallpaper" > "$STATE_DIR/current_wallpaper"
saved_state_dir="$STATE_DIR"
saved_current_theme_file="$CURRENT_THEME_FILE"
STATE_DIR="$TEST_TMP/state-directory-targets"
CURRENT_THEME_FILE="$STATE_DIR/current_theme"
mkdir -p "$STATE_DIR/current_wallpaper" "$CURRENT_THEME_FILE"
expect_failure 'wallpaper state destination is a directory' wallpaper_save_state "$wallpaper"
expect_failure 'theme state destination is a directory' theme_write_current_state xcalibur-test
[[ -z "$(find "$STATE_DIR" -type f -print -quit)" ]]
STATE_DIR="$saved_state_dir"
CURRENT_THEME_FILE="$saved_current_theme_file"
color_export
saved_runtime_colors="$RUNTIME_COLORS"
mkdir "$TEST_TMP/palette-directory"
RUNTIME_COLORS="$TEST_TMP/palette-directory"
expect_failure 'palette destination is a directory' color_export
[[ -z "$(find "$RUNTIME_COLORS" -mindepth 1 -print -quit)" ]]
ln -s "$saved_runtime_colors" "$TEST_TMP/palette-link"
RUNTIME_COLORS="$TEST_TMP/palette-link"
expect_failure 'palette destination is a symlink' color_export
[[ -L "$RUNTIME_COLORS" ]]
RUNTIME_COLORS="$saved_runtime_colors"
printf 'old\n' > "$TEST_TMP/live.conf"
printf 'new\n' > "$TEST_TMP/generated.conf"
fs_install_atomic "$TEST_TMP/generated.conf" "$TEST_TMP/live.conf"
[[ "$(cat "$TEST_TMP/live.conf")" == new ]]
expect_failure 'missing generated source preserves target' fs_install_atomic \
    "$TEST_TMP/missing" "$TEST_TMP/live.conf"
[[ "$(cat "$TEST_TMP/live.conf")" == new ]]
mv() { return 99; }
expect_failure 'failed atomic replacement preserves target' fs_install_atomic \
    "$TEST_TMP/generated.conf" "$TEST_TMP/live.conf"
unset -f mv
[[ "$(cat "$TEST_TMP/live.conf")" == new ]]
[[ -z "$(find "$TEST_TMP" -maxdepth 1 -name '.xcalibur.*' -print -quit)" ]]
ln -s "$TEST_TMP/live.conf" "$TEST_TMP/live-link.conf"
expect_failure 'symlinked application target' fs_install_atomic \
    "$TEST_TMP/generated.conf" "$TEST_TMP/live-link.conf"
[[ -L "$TEST_TMP/live-link.conf" ]]
mkdir -p "$TEST_TMP/real-config"
printf 'untouched\n' > "$TEST_TMP/real-config/theme.conf"
ln -s "$TEST_TMP/real-config" "$TEST_TMP/config-link"
expect_failure 'symlinked application parent' fs_install_atomic \
    "$TEST_TMP/generated.conf" "$TEST_TMP/config-link/theme.conf"
[[ "$(cat "$TEST_TMP/real-config/theme.conf")" == untouched ]]
[[ -z "$(find "$TEST_TMP/real-config" -name '.xcalibur.*' -print -quit)" ]]
mkdir -p "$TEST_TMP/target-directory"
expect_failure 'directory as target' fs_install_atomic \
    "$TEST_TMP/generated.conf" "$TEST_TMP/target-directory"
mkdir -p "$TEST_TMP/app-home/.config" "$TEST_TMP/actual-hypr" "$TEST_TMP/actual-swaync"
ln -s "$TEST_TMP/actual-hypr" "$TEST_TMP/app-home/.config/hypr"
ln -s "$TEST_TMP/actual-swaync" "$TEST_TMP/app-home/.config/swaync"
printf 'old lock\n' > "$TEST_TMP/actual-hypr/hyprlock.conf"
printf 'old notifications\n' > "$TEST_TMP/actual-swaync/style.css"
printf 'new lock\n' > "$GENERATED_DIR/hyprlock.conf"
printf 'new notifications\n' > "$GENERATED_DIR/swaync.css"
hyprlock_install_fixture() (
    HOME="$TEST_TMP/app-home"
    source "$ROOT/modules/hyprlock/install.sh"
    hyprlock_install
)
swaync_install_fixture() (
    HOME="$TEST_TMP/app-home"
    source "$ROOT/modules/swaync/install.sh"
    swaync_install
)
expect_failure 'Hyprlock symlinked parent before backup' hyprlock_install_fixture
expect_failure 'SwayNC symlinked parent before backup' swaync_install_fixture
[[ "$(cat "$TEST_TMP/actual-hypr/hyprlock.conf")" == 'old lock' ]]
[[ "$(cat "$TEST_TMP/actual-swaync/style.css")" == 'old notifications' ]]
[[ ! -e "$TEST_TMP/actual-hypr/hyprlock.conf.xcalibur-backup" ]]
[[ ! -e "$TEST_TMP/actual-swaync/style.css.xcalibur-backup" ]]
mkdir -p "$TEST_TMP/safe-home/.config/hypr"
printf 'old lock\n' > "$TEST_TMP/safe-home/.config/hypr/hyprlock.conf"
printf 'outside\n' > "$TEST_TMP/backup-outside"
ln -s "$TEST_TMP/backup-outside" "$TEST_TMP/safe-home/.config/hypr/hyprlock.conf.xcalibur-backup"
hyprlock_backup_fixture() (
    HOME="$TEST_TMP/safe-home"
    source "$ROOT/modules/hyprlock/install.sh"
    hyprlock_install
)
expect_failure 'Hyprlock symlinked backup' hyprlock_backup_fixture
[[ "$(cat "$TEST_TMP/backup-outside")" == outside ]]
[[ "$(cat "$TEST_TMP/safe-home/.config/hypr/hyprlock.conf")" == 'old lock' ]]
mkdir -p "$TEST_TMP/normal-home/.config/hypr" "$TEST_TMP/normal-home/.config/kitty"
printf 'old lock\n' > "$TEST_TMP/normal-home/.config/hypr/hyprlock.conf"
printf 'new kitty\n' > "$GENERATED_DIR/kitty.conf"
normal_install_fixture() (
    HOME="$TEST_TMP/normal-home"
    source "$ROOT/modules/hyprlock/install.sh"
    source "$ROOT/modules/kitty/install.sh"
    hyprlock_install
    kitty_install
)
normal_install_fixture
[[ "$(cat "$TEST_TMP/normal-home/.config/hypr/hyprlock.conf")" == 'new lock' ]]
[[ "$(cat "$TEST_TMP/normal-home/.config/hypr/hyprlock.conf.xcalibur-backup")" == 'old lock' ]]
[[ "$(cat "$TEST_TMP/normal-home/.config/kitty/current-theme.conf")" == 'new kitty' ]]

mkdir -p "$TEST_TMP/config-root/config"
printf 'touch "%s"\n' "$TEST_TMP/config-executed" > "$TEST_TMP/untrusted-config"
ln -s "$TEST_TMP/untrusted-config" "$TEST_TMP/config-root/config/theme.conf"
config_load_fixture() (
    THEME_ROOT="$TEST_TMP/config-root"
    source "$ROOT/engine/lib/config.sh"
    load_config
)
expect_failure 'symlinked trusted configuration' config_load_fixture
[[ ! -e "$TEST_TMP/config-executed" ]]
rm -f -- "$TEST_TMP/config-root/config/theme.conf"
cp -- "$ROOT/config/"* "$TEST_TMP/config-root/config/"
printf 'touch "%s"\n' "$TEST_TMP/config-executed" >> "$TEST_TMP/config-root/config/theme.conf"
expect_failure 'configuration code is not executed' config_load_fixture
[[ ! -e "$TEST_TMP/config-executed" ]]
mkdir -p "$TEST_TMP/untrusted-modules/module"
printf 'touch "%s"\n' "$TEST_TMP/module-executed" > "$TEST_TMP/untrusted-modules/module/module.sh"
module_load_fixture() (
    THEME_ROOT="$TEST_TMP/config-root"
    MODULES_DIR="$TEST_TMP/untrusted-modules"
    load_modules
)
expect_failure 'module code outside engine root' module_load_fixture
[[ ! -e "$TEST_TMP/module-executed" ]]
pgrep() { return 1; }
kitty_reload
waybar_reload
swaync_reload
hyprlock_reload
pgrep() { return 0; }
reload_log="$TEST_TMP/reload.log"
pkill() { printf 'pkill %s\n' "$*" >> "$reload_log"; }
swaync-client() { printf 'swaync-client %s\n' "$*" >> "$reload_log"; }
waybar_reload
swaync_reload
wofi_reload
gtk_reload
[[ "$(cat "$reload_log")" == $'pkill -USR2 -x waybar\nswaync-client -rs' ]]
pkill() { return 1; }
expect_failure 'Waybar signal failure' waybar_reload
unset -f pkill swaync-client
pgrep() { return 1; }
[[ ! -e "$TEST_TMP/executed" ]]
color_data_read "$RUNTIME_COLORS" runtime
[[ "${COLOR_DATA[COLOR15]}" == '#00000f' ]]
for template in "$ROOT"/modules/*/templates/*.template; do
    module="$(basename "$(dirname "$(dirname "$template")")")"
    render_template "$template" "$TEST_TMP/rendered/$module/$(basename "$template")"
done

printf 'before {{BACKGROUND}} after {{COLOR4}}\n' > "$TEST_TMP/template"
render_template "$TEST_TMP/template" "$TEST_TMP/output"
[[ "$(cat "$TEST_TMP/output")" == 'before #010203 after #000004' ]]
mkdir "$TEST_TMP/render-directory"
expect_failure 'renderer destination is a directory' render_template "$TEST_TMP/template" "$TEST_TMP/render-directory"
[[ -z "$(find "$TEST_TMP/render-directory" -mindepth 1 -print -quit)" ]]
ln -s "$TEST_TMP/output" "$TEST_TMP/render-link"
expect_failure 'renderer destination is a symlink' render_template "$TEST_TMP/template" "$TEST_TMP/render-link"
[[ -L "$TEST_TMP/render-link" ]]
printf '{{BACKGROUND}}/{{COLOR4}}/{{FOREGROUND}}/{{BACKGROUND}}\n' > "$TEST_TMP/template"
render_template "$TEST_TMP/template" "$TEST_TMP/output"
[[ "$(cat "$TEST_TMP/output")" == '#010203/#000004/#eeeeee/#010203' ]]
mkdir -p "$TEST_TMP/real-generated"
printf 'previous generated output\n' > "$TEST_TMP/real-generated/output"
ln -s "$TEST_TMP/real-generated" "$TEST_TMP/generated-link"
printf 'valid {{BACKGROUND}}\n' > "$TEST_TMP/template"
expect_failure 'renderer symlinked output parent' render_template \
    "$TEST_TMP/template" "$TEST_TMP/generated-link/output"
[[ "$(cat "$TEST_TMP/real-generated/output")" == 'previous generated output' ]]
color_symlink_fixture() (
    GENERATED_DIR="$TEST_TMP/generated-link"
    RUNTIME_COLORS="$GENERATED_DIR/colors.sh"
    color_export
)
expect_failure 'palette symlinked output parent' color_symlink_fixture
[[ ! -e "$TEST_TMP/real-generated/colors.sh" ]]
printf 'invalid {{MISSING}}\n' > "$TEST_TMP/template"
expect_failure 'unknown template variable' render_template "$TEST_TMP/template" "$TEST_TMP/output"
[[ "$(cat "$TEST_TMP/output")" == '#010203/#000004/#eeeeee/#010203' ]]
printf 'valid first {{BACKGROUND}}\ninvalid second {{BACKGROUND}\n' > "$TEST_TMP/template"
expect_failure 'malformed template variable' render_template "$TEST_TMP/template" "$TEST_TMP/output"
[[ "$(cat "$TEST_TMP/output")" == '#010203/#000004/#eeeeee/#010203' ]]

python3 - "$CWAL_COLORS" "$TEST_TMP/executed" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
path.write_text(path.read_text().replace("color0='#000000'", f"color0=$(touch {sys.argv[2]})"))
PY
expect_failure 'invalid CWAL data' color_export
[[ ! -e "$TEST_TMP/executed" ]]

mkdir -p "$TEST_TMP/cwal-bin"
cat > "$TEST_TMP/cwal-bin/cwal" <<'MOCK_CWAL'
#!/usr/bin/env bash
[[ "$*" == *'--no-reload --out-dir '* ]] || exit 88
[[ "$XDG_CONFIG_HOME" == */config ]] || exit 89
[[ "$CWAL_TEST_MODE" != fail ]] || exit 7
out="${@: -1}"
{
    printf "background='#010203'\nforeground='#eeeeee'\ncursor='#ffffff'\n"
    for n in {0..15}; do printf "color%d='#%06x'\n" "$n" "$n"; done
} > "$out/colors.sh"
MOCK_CWAL
chmod +x "$TEST_TMP/cwal-bin/cwal"
PATH="$TEST_TMP/cwal-bin:$PATH"
export PATH
CACHE_DIR="$TEST_TMP/cache"
COLOR_ENGINE=unsupported
expect_failure 'unsupported color engine' color_generate
unset COLOR_ENGINE
CWAL_TEST_MODE=ok
export CWAL_TEST_MODE
color_generate
[[ "${COLOR_DATA[COLOR15]}" == '#00000f' ]]
cp -- "$RUNTIME_COLORS" "$TEST_TMP/palette-before-cwal-failure"
CWAL_TEST_MODE=fail
expect_failure 'CWAL failure preserves runtime palette' color_generate
cmp -s "$RUNTIME_COLORS" "$TEST_TMP/palette-before-cwal-failure"
[[ -z "$(find "$CACHE_DIR" -mindepth 1 -print -quit)" ]]

mkdir -p "$MODULES_DIR/alpha" "$MODULES_DIR/beta"
ALPHA_ENABLED=true BETA_ENABLED=true
phase_log="$TEST_TMP/phases"
color_generate() { :; }
alpha_render() { printf 'alpha render\n' >> "$phase_log"; }
beta_render() { printf 'beta render\n' >> "$phase_log"; return 1; }
alpha_install() { printf 'alpha install\n' >> "$phase_log"; }
beta_install() { printf 'beta install\n' >> "$phase_log"; }
alpha_reload() { :; }
beta_reload() { :; }
expect_failure 'module render failure' theme_apply
[[ "$THEME_APPLY_PHASE" == render ]]
[[ "$(cat "$phase_log")" == $'alpha render\nbeta render' ]]
beta_render() { printf 'beta render\n' >> "$phase_log"; }
alpha_install() { printf 'alpha install\n' >> "$phase_log"; return 1; }
expect_failure 'module install failure' theme_apply
[[ "$THEME_APPLY_PHASE" == install ]]

mkdir -p "$MODULES_DIR/kitty" "$TEST_TMP/transaction-home/.config/kitty"
printf 'original\n' > "$TEST_TMP/transaction-home/.config/kitty/current-theme.conf"
chmod 600 "$TEST_TMP/transaction-home/.config/kitty/current-theme.conf"
original_home="$HOME"
HOME="$TEST_TMP/transaction-home"
ALPHA_ENABLED=false BETA_ENABLED=false KITTY_ENABLED=true
kitty_render() { printf 'rendered kitty\n' > "$GENERATED_DIR/kitty.conf"; }
kitty_install() { printf 'replacement\n' > "$HOME/.config/kitty/current-theme.conf"; }
kitty_reload() { return 1; }
expect_failure 'reload failure restores installed file' theme_apply
[[ "$(cat "$HOME/.config/kitty/current-theme.conf")" == original ]]
[[ "$(stat -c %a "$HOME/.config/kitty/current-theme.conf")" == 600 ]]
kitty_reload() { :; }
fail_state_commit() { return 1; }
THEME_APPLY_COMMIT=fail_state_commit
expect_failure 'state commit failure restores installed file' theme_apply
[[ "$(cat "$HOME/.config/kitty/current-theme.conf")" == original ]]
[[ "$THEME_APPLY_PHASE" == state ]]
unset THEME_APPLY_COMMIT
TMPDIR="$TEST_TMP"
export TMPDIR
kitty_reload() { return 1; }
install() { return 1; }
expect_failure 'incomplete rollback retains recovery snapshots' theme_apply
[[ "$(cat "$EXPECTED_FAILURE_LOG")" == *'Rollback snapshots were retained for manual recovery:'* ]]
recovery_dir="$(find "$TEST_TMP" -maxdepth 1 -type d -name 'xcalibur-rollback.*' -print -quit)"
[[ -n "$recovery_dir" && -f "$recovery_dir/0" ]]
unset -f install
rm -rf -- "$recovery_dir"
HOME="$original_home"
KITTY_ENABLED=false

WALLPAPER_DIR="$TEST_TMP/wallpapers"
mkdir -p "$WALLPAPER_DIR"
touch "$WALLPAPER_DIR/a space.png"
rm -f -- "$STATE_DIR/current_wallpaper"
wallpaper_reload() { return 1; }
expect_failure 'wallpaper reload failure' wallpaper_set "$WALLPAPER_DIR/a space.png"
[[ ! -e "$STATE_DIR/current_wallpaper" ]]
wallpaper_reload() { :; }
theme_apply() { return 1; }
expect_failure 'wallpaper apply failure' wallpaper_set "$WALLPAPER_DIR/a space.png"
[[ ! -e "$STATE_DIR/current_wallpaper" ]]

mkdir -p "$THEMES_DIR/xcalibur-test"
cp "$ROOT/themes/xcalibur-test/"* "$THEMES_DIR/xcalibur-test/"
mkdir -p "$THEMES_DIR/prior"
sed 's/THEME_ID=xcalibur-test/THEME_ID=prior/' "$ROOT/themes/xcalibur-test/theme.conf" > "$THEMES_DIR/prior/theme.conf"
cp -- "$ROOT/themes/xcalibur-test/palette.conf" "$THEMES_DIR/prior/palette.conf"
printf 'prior\n' > "$CURRENT_THEME_FILE"
cp "$RUNTIME_COLORS" "$TEST_TMP/previous-colors"
theme_apply() {
    THEME_APPLY_PHASE=render
    printf 'incomplete\n' > "$RUNTIME_COLORS"
    return 1
}
expect_failure 'theme selection rollback' theme_set set xcalibur-test
cmp -s "$RUNTIME_COLORS" "$TEST_TMP/previous-colors"
[[ "$(cat "$CURRENT_THEME_FILE")" == prior ]]

mkdir -p "$TEST_TMP/native-fixture"
cp "$ROOT/themes/xcalibur-test/theme.conf" "$ROOT/themes/xcalibur-test/palette.conf" "$TEST_TMP/native-fixture/"
mkdir -p "$TEST_TMP/native-stage"
TMPDIR="$TEST_TMP/native-stage"
export TMPDIR
THEME_ROOT="$TEST_TMP/native-root"
THEMES_DIR="$THEME_ROOT/themes"
mkdir -p "$THEME_ROOT"
python3() {
    if [[ "$1" == */importer/retrieve.py ]]; then
        mkdir -p "$3"
        command cp "$TEST_TMP/native-fixture/"* "$3/"
        printf '%040d\n' 0
        return
    fi
    command python3 "$@"
}
timeout() { local duration="$1"; shift; "$@"; }
theme_install install owner/repo
[[ -f "$THEMES_DIR/xcalibur-test/theme.conf" ]]
expect_failure 'existing native theme' theme_install install owner/repo
[[ -f "$THEMES_DIR/xcalibur-test/palette.conf" ]]
cmp -s "$THEMES_DIR/xcalibur-test/palette.conf" "$TEST_TMP/native-fixture/palette.conf"
mkdir -p "$TEST_TMP/outside-themes" "$TEST_TMP/native-link-root"
ln -s "$TEST_TMP/outside-themes" "$TEST_TMP/native-link-root/themes"
THEME_ROOT="$TEST_TMP/native-link-root"
THEMES_DIR="$THEME_ROOT/themes"
expect_failure 'symlinked themes directory' theme_install install owner/repo
[[ -z "$(find "$TEST_TMP/outside-themes" -mindepth 1 -print -quit)" ]]
ln -s "$TEST_TMP/outside-themes" "$TEST_TMP/native-parent-link"
THEME_ROOT="$TEST_TMP/native-parent-link"
THEMES_DIR="$THEME_ROOT/themes"
expect_failure 'symlinked parent of themes directory' theme_install install owner/repo
[[ -z "$(find "$TEST_TMP/outside-themes" -mindepth 1 -print -quit)" ]]
THEME_ROOT="$TEST_TMP/native-root"
THEMES_DIR="$TEST_TMP/outside-themes"
expect_failure 'themes directory outside engine root' theme_install install owner/repo
THEME_ROOT="$TEST_TMP/native-failure-root"
THEMES_DIR="$THEME_ROOT/themes"
mkdir -p "$THEME_ROOT"
python3() {
    if [[ "$1" == */importer/retrieve.py ]]; then
        mkdir -p "$3"
        command cp "$TEST_TMP/native-fixture/"* "$3/"
        return
    fi
    if [[ "${2:-}" == install-pack ]]; then return 91; fi
    command python3 "$@"
}
expect_failure 'native publication failure leaves no pack' theme_install install owner/repo
[[ ! -e "$THEMES_DIR/xcalibur-test" ]]
[[ -z "$(find "$TMPDIR" -mindepth 1 -print -quit)" ]]
unset -f python3
unset -f timeout

mkdir -p "$TEST_TMP/repo/dotfiles/kitty" "$TEST_TMP/repo/waybar"
printf 'background #112233\nforeground #eeeeee\ncolor4 #778899\n' > "$TEST_TMP/repo/dotfiles/kitty/colors.conf"
printf ':root { --background: #112233; --accent: #abcdef; }\n' > "$TEST_TMP/repo/waybar/style.css"
ln -s /etc/passwd "$TEST_TMP/repo/waybar/linked.css"
ln -s /etc "$TEST_TMP/repo/external-dir"
python3 "$ROOT/engine/importer/analyze.py" "$TEST_TMP/repo" owner/repo deadbeef > "$TEST_TMP/report.json"
python3 - "$TEST_TMP/report.json" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
assert len(report['inventory']) == 2
assert report['semantic_roles']['BACKGROUND']['value'] == '#112233'
assert report['semantic_roles']['ACCENT']['value'] == '#ABCDEF'
assert report['theme_pack_generated'] is False
assert all(item['path'] != 'waybar/linked.css' for item in report['inventory'])
assert any(item['reason'] == 'not_regular_file' for item in report['skipped'])
assert any(item['reason'] == 'symlink_directory' for item in report['skipped'])
PY
printf ':root { --background: #445566; }\n' > "$TEST_TMP/repo/waybar/alternate.css"
python3 "$ROOT/engine/importer/analyze.py" "$TEST_TMP/repo" owner/repo deadbeef > "$TEST_TMP/conflict.json"
python3 - "$TEST_TMP/conflict.json" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
assert 'BACKGROUND' not in report['semantic_roles']
assert any(item['role'] == 'BACKGROUND' for item in report['conflicts'])
PY

unset -f python3
source "$ROOT/engine/commands/import.sh"
ENGINE_DIR="$ROOT/engine"
mkdir -p "$TEST_TMP/mock-bin" "$TEST_TMP/import-stage"
IMPORT_REAL_PYTHON="$(command -v python3)"
cat > "$TEST_TMP/mock-bin/python3" <<'MOCK_PYTHON'
#!/usr/bin/env bash
if [[ "$1" != */engine/importer/retrieve.py ]]; then
    exec "$IMPORT_REAL_PYTHON" "$@"
fi
printf '%s\n' "$*" >> "$IMPORT_RETRIEVE_LOG"
[[ "$IMPORT_RETRIEVE_MODE" != retrieve-fail ]] || exit 11
repository="${2%@*}" destination="$3" info="$4"
mkdir -p -- "$destination"
if [[ "$IMPORT_RETRIEVE_MODE" == fixture ]]; then
    cp -a -- "$IMPORT_FIXTURE/." "$destination/"
fi
revision="$(printf '%040d' 0)"
cat > "$info" <<JSON
{"method":"github_api_commit_archive","revision":"$revision","archive_url":"https://codeload.github.com/$repository/tar.gz/$revision","archive_sha256":"$(printf '%064d' 1)","download_bytes":100}
JSON
if [[ "$IMPORT_RETRIEVE_MODE" == invalid-revision ]]; then
    printf 'invalid\n'
else
    printf '%s\n' "$revision"
fi
MOCK_PYTHON
chmod +x "$TEST_TMP/mock-bin/python3"
PATH="$TEST_TMP/mock-bin:$PATH"
TMPDIR="$TEST_TMP/import-stage"
IMPORT_RETRIEVE_LOG="$TEST_TMP/import-retrieve.log"
export PATH TMPDIR IMPORT_RETRIEVE_LOG IMPORT_REAL_PYTHON
expect_failure 'invalid GitHub URL' command_import analyze https://example.invalid/owner/repo
expect_failure 'unsafe GitHub revision' command_import analyze https://github.com/owner/repo?ref=main
[[ ! -s "$IMPORT_RETRIEVE_LOG" ]]
import_staging_empty() {
    [[ -z "$(find "$TMPDIR" -mindepth 1 -print -quit)" ]]
}
IMPORT_RETRIEVE_MODE=retrieve-fail
export IMPORT_RETRIEVE_MODE
expect_failure 'failed retrieval cleans staging' command_import analyze owner/repo
import_staging_empty
timeout() {
    [[ "$IMPORT_RETRIEVE_MODE" != timeout ]] || return 124
    command timeout "$@"
}
IMPORT_RETRIEVE_MODE=timeout
expect_failure 'retrieval timeout cleans staging' command_import analyze owner/repo
import_staging_empty
unset -f timeout
[[ "$(cat "$EXPECTED_FAILURE_LOG")" == *'Unable to retrieve bounded GitHub source: owner/repo'* ]]
IMPORT_RETRIEVE_MODE=invalid-revision
expect_failure 'invalid retrieval revision cleans staging' command_import analyze owner/repo
import_staging_empty
[[ "$(cat "$EXPECTED_FAILURE_LOG")" == *'Retrieval returned invalid commit information: owner/repo'* ]]
IMPORT_RETRIEVE_MODE=ok
python3() { exit 77; }
expect_failure 'shell exit during analysis cleans staging' command_import analyze owner/repo
import_staging_empty
python3() { kill -TERM "$BASHPID"; }
expect_failure 'signal during analysis cleans staging' command_import analyze owner/repo
import_staging_empty
unset -f python3
command_import analyze owner/repo > "$TEST_TMP/import-report.json"
import_staging_empty
python3 - "$TEST_TMP/import-report.json" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
assert report['mode'] == 'analysis_only'
assert report['installed'] is False and report['applied'] is False
assert report['revision'] == '0' * 40
PY
[[ "$(wc -l < "$IMPORT_RETRIEVE_LOG")" -ge 5 ]]
rm() {
    if [[ "$*" == *xcalibur-import.* ]]; then return 99; fi
    command rm "$@"
}
expect_failure 'cleanup error returns failure' command_import analyze owner/repo
[[ "$(cat "$EXPECTED_FAILURE_LOG")" == *'Unable to remove import staging directory:'* ]]
unset -f rm
rm -rf -- "$TEST_TMP/import-stage"
mkdir -p "$TEST_TMP/import-stage"

mkdir -p "$TEST_TMP/convert-fixture"
printf 'background #112233\nforeground #eeeeee\n' > "$TEST_TMP/convert-fixture/kitty.conf"
IMPORT_FIXTURE="$TEST_TMP/convert-fixture"
IMPORT_RETRIEVE_MODE=fixture
export IMPORT_FIXTURE IMPORT_RETRIEVE_MODE
command_import preview owner/repo > "$TEST_TMP/preview.txt"
[[ "$(cat "$TEST_TMP/preview.txt")" == *'Planned theme ID: owner-repo'* ]]
pin="$(printf '%040d' 0)"
command_import preview "owner/repo@$pin" > "$TEST_TMP/pinned-preview.txt"
[[ "$(cat "$TEST_TMP/pinned-preview.txt")" == *"Pinned source for next command: owner/repo@$pin"* ]]
[[ "$(cat "$IMPORT_RETRIEVE_LOG")" == *"owner/repo@$pin"* ]]
[[ ! -e "$TEST_TMP/converted pack" ]]
command_import convert owner/repo "$TEST_TMP/converted pack" > "$TEST_TMP/convert-output.txt"
[[ -f "$TEST_TMP/converted pack/theme.conf" ]]
[[ -f "$TEST_TMP/converted pack/palette.conf" ]]
expect_failure 'conversion collision' command_import convert owner/repo "$TEST_TMP/converted pack"
THEME_ROOT="$TEST_TMP/converted-install-root"
THEMES_DIR="$THEME_ROOT/themes"
mkdir -p "$THEME_ROOT"
command_import install "$TEST_TMP/converted pack"
[[ -f "$THEMES_DIR/owner-repo/palette.conf" ]]
expect_failure 'import install collision' command_import install "$TEST_TMP/converted pack"
[[ -z "$(find "$TMPDIR" -mindepth 1 -print -quit)" ]]

# Exercise every public import stage against a committed local repository.
PATH="${PATH#"$TEST_TMP/mock-bin:"}"
export PATH
local_repo="$TEST_TMP/local source"
mkdir -p "$local_repo"
printf 'background #102030\nforeground #E0E0E0\ncolor4 #445566\n' > "$local_repo/kitty.conf"
printf 'All rights reserved. No redistribution.\n' > "$local_repo/LICENSE"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$local_repo" init -q
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$local_repo" add kitty.conf LICENSE
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$local_repo" \
    -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false \
    commit -q -m 'Fixture colors'
command_import analyze "$local_repo" > "$TEST_TMP/local-report.json"
ln -s "$local_repo" "$TEST_TMP/local-source-link"
expect_failure 'symlinked local source rejected' command_import analyze "$TEST_TMP/local-source-link"
printf 'not an archive\n' > "$TEST_TMP/local-archive.tar"
expect_failure 'archive is not a source directory' command_import analyze "$TEST_TMP/local-archive.tar"
python3 - "$TEST_TMP/local-report.json" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
assert report['source_kind'] == 'local' and report['source_url'] is None
assert report['license_status'] == 'restrictive_terms_found'
assert len(report['revision']) == 40
assert report['semantic_roles']['BACKGROUND']['value'] == '#102030'
PY
mkdir "$TEST_TMP/plain local source"
printf 'background #102030\nforeground #E0E0E0\n' > "$TEST_TMP/plain local source/kitty.conf"
command_import analyze "$TEST_TMP/plain local source" > "$TEST_TMP/plain-local-report.json"
python3 - "$TEST_TMP/plain-local-report.json" <<'PY'
import json, sys
assert json.load(open(sys.argv[1]))['revision'] == 'unversioned'
PY
command_import preview "$local_repo" > "$TEST_TMP/local-preview.txt"
[[ "$(cat "$TEST_TMP/local-preview.txt")" == *'Installation conflict: none detected'* ]]
[[ "$(cat "$TEST_TMP/local-preview.txt")" == *'License status: restrictive_terms_found'* ]]
[[ ! -e "$THEMES_DIR/local-local-source" ]]
command_import convert "$local_repo" "$TEST_TMP/local converted" > "$TEST_TMP/local-convert.txt"
theme_manifest_load "$TEST_TMP/local converted/theme.conf" ""
theme_definition_load "$TEST_TMP/local converted/palette.conf" ""
python3 "$ROOT/engine/importer/convert.py" validate-metadata \
    "$TEST_TMP/local converted/source.json" local-local-source
command_import convert "$local_repo" "$TEST_TMP/local converted again" > /dev/null
cmp "$TEST_TMP/local converted/source.json" "$TEST_TMP/local converted again/source.json"
cmp "$TEST_TMP/local converted/palette.conf" "$TEST_TMP/local converted again/palette.conf"
expect_failure 'local conversion output collision' command_import convert "$local_repo" "$TEST_TMP/local converted"
command_import install "$TEST_TMP/local converted"
[[ -f "$THEMES_DIR/local-local-source/source.json" ]]
cmp "$TEST_TMP/local converted/source.json" "$THEMES_DIR/local-local-source/source.json"
command_import preview "$local_repo" > "$TEST_TMP/local-preview-conflict.txt"
[[ "$(cat "$TEST_TMP/local-preview-conflict.txt")" == *'Installation conflict: yes; theme ID already exists'* ]]
expect_failure 'local import installation collision' command_import install "$TEST_TMP/local converted again"
printf 'user data\n' > "$THEMES_DIR/local-local-source/user-file"
[[ "$(cat "$THEMES_DIR/local-local-source/user-file")" == 'user data' ]]
cp -- "$TEST_TMP/local converted/source.json" "$TEST_TMP/source-valid.json"
printf 'invalid\n' > "$TEST_TMP/local converted/source.json"
expect_failure 'tampered import metadata rejected' command_import install "$TEST_TMP/local converted"
[[ "$(cat "$THEMES_DIR/local-local-source/user-file")" == 'user data' ]]
THEME_ROOT="$TEST_TMP/metadata-failure-root"
THEMES_DIR="$THEME_ROOT/themes"
mkdir -p "$THEME_ROOT"
python3() {
    if [[ "${2:-}" == install-pack ]]; then return 91; fi
    command python3 "$@"
}
expect_failure 'metadata publication failure leaves no theme directory' \
    command_import install "$TEST_TMP/local converted again"
unset -f python3
[[ ! -e "$THEMES_DIR/local-local-source" ]]
rm -- "$TEST_TMP/local converted/source.json"
ln -s "$TEST_TMP/source-valid.json" "$TEST_TMP/local converted/source.json"
expect_failure 'symlinked import metadata rejected' command_import install "$TEST_TMP/local converted"
[[ ! -e "$THEMES_DIR/local-local-source" ]]
[[ -z "$(find "$TMPDIR" -mindepth 1 -print -quit)" ]]

echo 'All isolated tests passed.'
