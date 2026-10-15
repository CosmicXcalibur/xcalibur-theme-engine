#!/usr/bin/env bash

# ==========================================================
# Xcalibur Hyprlock Install
# ==========================================================

hyprlock_install() {

    local target="$HOME/.config/hypr/hyprlock.conf"
    local backup="$HOME/.config/hypr/hyprlock.conf.xcalibur-backup"

    [[ ! -L "$target" && ! -L "$backup" ]] || return 1
    fs_directory_safe "$HOME/.config/hypr" true || return 1

    if [[ -f "$target" && ! -f "$backup" ]]; then
        [[ ! -e "$backup" ]] || return 1
        if ! fs_matches_previous_generated "$target" hyprlock.conf; then
            fs_install_atomic "$target" "$backup" || return 1
        fi
    fi

    fs_install_atomic \
        "$GENERATED_DIR/hyprlock.conf" \
        "$target"
}
