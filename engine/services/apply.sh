#!/usr/bin/env bash

# ==========================================================
# Theme Apply Service
# ==========================================================

theme_apply() {

    log_info "Applying theme..."

    # Generate runtime palette
    color_generate

    # Apply modules
    kitty_apply
    waybar_apply

    log_success "Theme applied."

}
