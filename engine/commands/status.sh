#!/usr/bin/env bash

command_status() {
    local selected="none" wallpaper="none" module enabled_var enabled=""
    if [[ -f "$CURRENT_THEME_FILE" ]]; then
        selected="$(< "$CURRENT_THEME_FILE")"
        if ! theme_id_validate "$selected" || [[ ! -d "$THEMES_DIR/$selected" ]]; then
            selected="invalid or missing: $selected"
        fi
    fi
    if [[ -f "$STATE_DIR/current_wallpaper" ]]; then
        wallpaper="$(< "$STATE_DIR/current_wallpaper")"
        [[ -f "$wallpaper" ]] || wallpaper="missing: $wallpaper"
    fi
    for module in "$MODULES_DIR"/*; do
        [[ -d "$module" ]] || continue
        module="$(basename "$module")"
        enabled_var="${module^^}_ENABLED"
        [[ "${!enabled_var:-false}" == true ]] && enabled+="${enabled:+, }$module"
    done
    printf 'Engine: %s\nTheme: %s\nWallpaper: %s\nEnabled modules: %s\n' \
        "$THEME_ROOT" "$selected" "$wallpaper" "${enabled:-none}"
}
