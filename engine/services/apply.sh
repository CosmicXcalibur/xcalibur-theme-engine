#!/usr/bin/env bash

# ==========================================================
# Theme Apply Service
# ==========================================================

theme_apply() {

    log_info "Applying theme..."

    # Generate runtime palette
    color_generate

    # Render Kitty configuration
    command_render kitty

    # Install generated configuration
    kitty_install

    # Reload Kitty with new colors
    kitty_reload

    log_success "Theme applied."

}
