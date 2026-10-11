#!/usr/bin/env bash

# ==========================================================
# Xcalibur SwayNC Install
# ==========================================================

swaync_install() {

    local target="$HOME/.config/swaync/style.css"
    local backup="$HOME/.config/swaync/style.css.xcalibur-backup"

    [[ ! -L "$target" && ! -L "$backup" ]] || return 1
    fs_directory_safe "$HOME/.config/swaync" true || return 1

    if [[ -f "$target" && ! -f "$backup" ]]; then
        [[ ! -e "$backup" ]] || return 1
        fs_install_atomic "$target" "$backup" || return 1
    fi

    fs_install_atomic \
        "$GENERATED_DIR/swaync.css" \
        "$target"

}
