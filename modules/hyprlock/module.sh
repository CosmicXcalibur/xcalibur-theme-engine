#!/usr/bin/env bash

# ==========================================================
# Xcalibur Hyprlock Module
# ==========================================================

hyprlock_render() {

    render_template \
        "$MODULES_DIR/hyprlock/templates/hyprlock.conf.template" \
        "$GENERATED_DIR/hyprlock.conf"

    # Hyprlock expects RGB values without the leading '#'
    # while Xcalibur's runtime palette uses #RRGGBB.
    sed -i \
        -E 's/rgb\(#([0-9A-Fa-f]{6})\)/rgb(\1)/g' \
        "$GENERATED_DIR/hyprlock.conf"
}

hyprlock_apply() {

    log_info "Applying Hyprlock theme..."

    hyprlock_render

    if [[ ! -f "$GENERATED_DIR/hyprlock.conf" ]]; then
        log_error "Failed to generate Hyprlock configuration."
        return 1
    fi

    hyprlock_install

    log_success "Hyprlock theme installed."
}
