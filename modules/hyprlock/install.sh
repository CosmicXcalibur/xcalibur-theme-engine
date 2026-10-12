#!/usr/bin/env bash

# ==========================================================
# Xcalibur Hyprlock Install
# ==========================================================

hyprlock_install() {

    local target="$HOME/.config/hypr/hyprlock.conf"
    local backup="$HOME/.config/hypr/hyprlock.conf.xcalibur-backup"

    mkdir -p "$HOME/.config/hypr"

    if [[ -f "$target" && ! -f "$backup" ]]; then
        cp "$target" "$backup"
    fi

    install -m 644 \
        "$GENERATED_DIR/hyprlock.conf" \
        "$target"
}

hyprlock_transaction_plan() {
    local target="$HOME/.config/hypr/hyprlock.conf"
    local backup="$target.xcalibur-backup"
    if [[ -f "$target" && ! -e "$backup" && ! -L "$backup" ]]; then
        theme_txn_plan "$target" "$backup" || return 1
    fi
    theme_txn_plan "$GENERATED_DIR/hyprlock.conf" "$target"
}
