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

    wofi_render || return 1
    wofi_install || return 1
    wofi_reload

}
