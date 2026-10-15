#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/xcalibur-integration.XXXXXX")"
trap 'rm -rf -- "$CASE_DIR"' EXIT
mkdir -p "$CASE_DIR/checkout" "$CASE_DIR/home" "$CASE_DIR/wallpapers with spaces" \
    "$CASE_DIR/mock-bin" "$CASE_DIR/tmp"
cp -a -- "$ROOT/engine" "$ROOT/modules" "$ROOT/config" "$ROOT/themes" "$CASE_DIR/checkout/"

HOME="$CASE_DIR/home"
TMPDIR="$CASE_DIR/tmp"
HYPRCTL_LOG="$CASE_DIR/hyprctl.log"
export HOME TMPDIR HYPRCTL_LOG
wallpaper_setting="WALLPAPER_DIR=\"$CASE_DIR/wallpapers with spaces\""
awk -v replacement="$wallpaper_setting" '/^WALLPAPER_DIR=/ {print replacement; next} {print}' \
    "$CASE_DIR/checkout/config/paths.conf" > "$CASE_DIR/new-paths.conf"
mv -- "$CASE_DIR/new-paths.conf" "$CASE_DIR/checkout/config/paths.conf"
cat > "$CASE_DIR/checkout/config/applications.conf" <<'MODULES'
KITTY_ENABLED=true
WAYBAR_ENABLED=false
WOFI_ENABLED=false
GTK_ENABLED=false
HYPRLOCK_ENABLED=false
SWAYNC_ENABLED=false
QT_ENABLED=false
MODULES

cat > "$CASE_DIR/mock-bin/hyprctl" <<'MOCK_HYPRCTL'
#!/usr/bin/env bash
if [[ "${1:-}" == monitors ]]; then
    printf 'Monitor TEST\n'
else
    printf '%s\n' "$*" >> "$HYPRCTL_LOG"
fi
MOCK_HYPRCTL
cat > "$CASE_DIR/mock-bin/cwal" <<'MOCK_CWAL'
#!/usr/bin/env bash
[[ "${CWAL_TEST_MODE:-ok}" != fail ]] || exit 7
out="${@: -1}"
{
    printf "background='#010203'\nforeground='#eeeeee'\ncursor='#ffffff'\n"
    for n in {0..15}; do
        if [[ "${CWAL_VARIANT:-}" == changed && "$n" -eq 4 ]]; then
            printf "color4='#ff0000'\n"
        else
            printf "color%d='#%06x'\n" "$n" "$n"
        fi
    done
} > "$out/colors.sh"
MOCK_CWAL
cat > "$CASE_DIR/mock-bin/pgrep" <<'MOCK_PGREP'
#!/usr/bin/env bash
[[ "${RELOAD_FAIL:-}" == 1 && "${2:-}" == swaync ]] && exit 0
exit 1
MOCK_PGREP
cat > "$CASE_DIR/mock-bin/swaync-client" <<'MOCK_SWAYNC'
#!/usr/bin/env bash
exit 7
MOCK_SWAYNC
chmod +x "$CASE_DIR/mock-bin/"*
PATH="$CASE_DIR/mock-bin:$PATH"
export PATH

first="$CASE_DIR/wallpapers with spaces/first image.png"
second="$CASE_DIR/wallpapers with spaces/second image.png"
touch "$first" "$second"
cli="$CASE_DIR/checkout/engine/bin/theme"
"$cli" doctor > "$CASE_DIR/doctor.log"
source "$ROOT/engine/lib/common.sh"
source "$ROOT/engine/commands/doctor.sh"
show_banner() { :; }
cmd_exists() { [[ "$1" != cwal ]] && command -v "$1" >/dev/null 2>&1; }
if command_doctor > "$CASE_DIR/doctor-missing.log" 2>&1; then
    printf 'Doctor missed a required dependency\n' >&2
    exit 1
fi
"$cli" wallpaper set "$first" > "$CASE_DIR/first.log"
[[ "$(< "$CASE_DIR/checkout/runtime/state/current_wallpaper")" == "$first" ]]
[[ -f "$HOME/.config/kitty/current-theme.conf" ]]
grep -q '^color4 #000004$' "$HOME/.config/kitty/current-theme.conf"
"$cli" set xcalibur-test > "$CASE_DIR/set.log"
[[ "$(< "$CASE_DIR/checkout/runtime/state/current_theme")" == xcalibur-test ]]
"$cli" status > "$CASE_DIR/status.log"
grep -q 'Theme: xcalibur-test' "$CASE_DIR/status.log"

cp -- "$HOME/.config/kitty/current-theme.conf" "$CASE_DIR/kitty-before-failure"
CWAL_TEST_MODE=fail
export CWAL_TEST_MODE
if "$cli" wallpaper set "$second" > "$CASE_DIR/failure.log" 2>&1; then
    printf 'Wallpaper failure unexpectedly succeeded\n' >&2
    exit 1
fi
cmp -s "$HOME/.config/kitty/current-theme.conf" "$CASE_DIR/kitty-before-failure"
[[ "$(< "$CASE_DIR/checkout/runtime/state/current_wallpaper")" == "$first" ]]
[[ "$(tail -1 "$HYPRCTL_LOG")" == "hyprpaper wallpaper TEST,$first,cover" ]]

cat > "$CASE_DIR/checkout/config/applications.conf" <<'ALL_MODULES'
KITTY_ENABLED=true
WAYBAR_ENABLED=true
WOFI_ENABLED=true
GTK_ENABLED=true
HYPRLOCK_ENABLED=true
SWAYNC_ENABLED=true
QT_ENABLED=false
ALL_MODULES
CWAL_TEST_MODE=ok
export CWAL_TEST_MODE
"$cli" set xcalibur-test > "$CASE_DIR/all-modules.log"
targets=(
    "$HOME/.config/kitty/current-theme.conf"
    "$HOME/.config/waybar/styles/colors/xcalibur.css"
    "$HOME/.config/wofi/style.css"
    "$HOME/.config/gtk-3.0/gtk.css"
    "$HOME/.config/gtk-4.0/gtk.css"
    "$HOME/.config/hypr/hyprlock.conf"
    "$HOME/.config/swaync/style.css"
)
for target in "${targets[@]}"; do
    [[ -s "$target" ]]
    ! grep -q '{{' "$target"
done
sha256sum -- "${targets[@]}" > "$CASE_DIR/application-checksums"
sha256sum -- "$CASE_DIR/checkout/runtime/generated/"* > "$CASE_DIR/generated-checksums"
cp -- "$CASE_DIR/checkout/runtime/generated/colors.sh" "$CASE_DIR/palette-before-reload-failure"
RELOAD_FAIL=1
CWAL_VARIANT=changed
export RELOAD_FAIL CWAL_VARIANT
if "$cli" set xcalibur-test > "$CASE_DIR/reload-failure.log" 2>&1; then
    printf 'Reload failure unexpectedly succeeded\n' >&2
    exit 1
fi
sha256sum -c "$CASE_DIR/application-checksums" > /dev/null
sha256sum -c "$CASE_DIR/generated-checksums" > /dev/null
cmp -s "$CASE_DIR/checkout/runtime/generated/colors.sh" "$CASE_DIR/palette-before-reload-failure"
[[ -z "$(find "$CASE_DIR/checkout/runtime/generated" -maxdepth 1 -name '.render-stage.*' -print -quit)" ]]
[[ ! -e "$HOME/.config/hypr/hyprlock.conf.xcalibur-backup" ]]
[[ ! -e "$HOME/.config/swaync/style.css.xcalibur-backup" ]]
RELOAD_FAIL=0
export RELOAD_FAIL
"$cli" set xcalibur-test > "$CASE_DIR/recovery.log"
grep -q '^color4 #ff0000$' "$HOME/.config/kitty/current-theme.conf"
grep -q '^PRIMARY="#ff0000"$' "$CASE_DIR/checkout/runtime/generated/colors.sh"
[[ "$(< "$CASE_DIR/checkout/runtime/state/current_theme")" == xcalibur-test ]]
sha256sum -- "${targets[@]}" > "$CASE_DIR/recovered-application-checksums"
"$cli" set xcalibur-test > "$CASE_DIR/repeat.log"
sha256sum -c "$CASE_DIR/recovered-application-checksums" > /dev/null
[[ ! -e "$HOME/.config/hypr/hyprlock.conf.xcalibur-backup" ]]
[[ ! -e "$HOME/.config/swaync/style.css.xcalibur-backup" ]]
printf 'user notification edit\n' > "$HOME/.config/swaync/style.css"
"$cli" set xcalibur-test > "$CASE_DIR/user-edit-recovery.log"
[[ "$(< "$HOME/.config/swaync/style.css.xcalibur-backup")" == 'user notification edit' ]]
[[ ! -e "$HOME/.config/hypr/hyprlock.conf.xcalibur-backup" ]]
printf 'End-to-end isolated CLI workflow passed.\n'
