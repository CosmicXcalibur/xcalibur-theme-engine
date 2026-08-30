#!/usr/bin/env bash

# ==========================================================
# Xcalibur SwayNC Install
# ==========================================================

swaync_install() {

    local target="$HOME/.config/swaync/style.css"
    local backup="$HOME/.config/swaync/style.css.xcalibur-backup"

    mkdir -p "$HOME/.config/swaync"

    if [[ -f "$target" && ! -f "$backup" ]]; then
        cp "$target" "$backup"
    fi

    install -m 644 \
        "$GENERATED_DIR/swaync.css" \
        "$target"

}
