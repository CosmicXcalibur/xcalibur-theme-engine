#!/usr/bin/env bash

command_status() {
    local selected="none" wallpaper="none" module enabled_var enabled="" bad=0
    if [[ -L "$CURRENT_THEME_FILE" ]]; then
        selected="invalid: symlinked state file"
        bad=1
    elif [[ -f "$CURRENT_THEME_FILE" ]]; then
        selected="$(< "$CURRENT_THEME_FILE")"
        if ! theme_id_validate "$selected" ||
           ! fs_directory_safe "$THEMES_DIR" false ||
           [[ ! -d "$THEMES_DIR/$selected" || -L "$THEMES_DIR/$selected" ]] ||
           ! theme_install_root_file_validate "$THEMES_DIR/$selected/theme.conf" ||
           ! theme_install_root_file_validate "$THEMES_DIR/$selected/palette.conf" ||
           ! theme_manifest_load "$THEMES_DIR/$selected/theme.conf" "$selected" ||
           ! theme_definition_load "$THEMES_DIR/$selected/palette.conf" "$selected"; then
            selected="invalid or missing: $selected"
            bad=1
        fi
    fi
    if [[ -L "$STATE_DIR/current_wallpaper" ]]; then
        wallpaper="invalid: symlinked state file"
        bad=1
    elif [[ -f "$STATE_DIR/current_wallpaper" ]]; then
        wallpaper="$(< "$STATE_DIR/current_wallpaper")"
        if ! wallpaper_validate "$wallpaper"; then
            wallpaper="invalid or missing: $wallpaper"
            bad=1
        fi
    fi
    for module in "$MODULES_DIR"/*; do
        [[ -d "$module" ]] || continue
        module="$(basename "$module")"
        enabled_var="${module^^}_ENABLED"
        [[ "${!enabled_var:-false}" == true ]] && enabled+="${enabled:+, }$module"
    done
    printf 'Engine: %s\nTheme: %s\nWallpaper: %s\nEnabled modules: %s\n' \
        "$THEME_ROOT" "$selected" "$wallpaper" "${enabled:-none}"
    ((bad == 0))
}
