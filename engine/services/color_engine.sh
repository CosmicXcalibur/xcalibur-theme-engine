#!/usr/bin/env bash

# ==========================================================
# Xcalibur Color Engine
# ==========================================================

CWAL_COLORS="$HOME/.cache/cwal/colors.sh"
RUNTIME_COLORS="$GENERATED_DIR/colors.sh"

# ----------------------------------------------------------
# Generate palette using cwal
# ----------------------------------------------------------

color_generate() {

    log_info "Generating color palette..."

    local wallpaper

    wallpaper=$(cat "$STATE_DIR/current_wallpaper")

    if [[ ! -f "$wallpaper" ]]; then
        log_error "Current wallpaper not found."
        return 1
    fi

    cwal --img "$wallpaper" --no-reload

    color_export

    log_success "Palette generated."

}

# ----------------------------------------------------------
# Export runtime palette
# ----------------------------------------------------------

color_export() {

    if [[ ! -f "$CWAL_COLORS" ]]; then
        log_error "cwal palette not found."
        return 1
    fi

    mkdir -p "$GENERATED_DIR"

    cp "$CWAL_COLORS" "$RUNTIME_COLORS"

    log_success "Runtime palette updated."

}
