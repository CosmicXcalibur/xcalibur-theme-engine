#!/usr/bin/env bash

# ==========================================================
# Xcalibur SwayNC Module
# ==========================================================

swaync_render() {

    render_template \
        "$MODULES_DIR/swaync/templates/style.css.template" \
        "$GENERATED_DIR/swaync.css"

}

swaync_apply() {

    log_info "Applying SwayNC theme..."

    swaync_render || return 1
    swaync_install || return 1
    swaync_reload

}
