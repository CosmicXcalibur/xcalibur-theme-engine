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

    wofi_reload

}
