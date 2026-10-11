#!/usr/bin/env bash

# ==========================================================
# Wofi Install
# ==========================================================

wofi_install() {

    fs_install_atomic \
        "$GENERATED_DIR/wofi.css" \
        "$HOME/.config/wofi/style.css"

}
