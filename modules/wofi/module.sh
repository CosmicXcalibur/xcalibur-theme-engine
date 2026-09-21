#!/usr/bin/env bash

# ==========================================================
# Wofi Theme Module
# ==========================================================

wofi_render() {

    render_template \
        "$MODULES_DIR/wofi/templates/style.css.template" \
        "$GENERATED_DIR/wofi.css"

}

wofi_apply() {

    wofi_render

    wofi_install

    if ! wofi_reload; then
        log_warn "Wofi configuration installed, but live reload failed."
    fi

}
