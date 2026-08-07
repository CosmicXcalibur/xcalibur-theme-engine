#!/usr/bin/env bash

# ==========================================================
# Xcalibur Color Engine
# ==========================================================

color_generate() {

    log_info "Generating color palette..."

    local wallpaper

    wallpaper=$(cat "$STATE_DIR/current_wallpaper")

    if [[ ! -f "$wallpaper" ]]; then
        log_error "Current wallpaper not found."
        return 1
    fi

    cwal --img "$wallpaper"

    log_success "Palette generated."

}
