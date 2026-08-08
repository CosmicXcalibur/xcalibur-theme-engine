#!/usr/bin/env bash

# ==========================================================
# Wofi Install
# ==========================================================

wofi_install() {

    install -m 644 \
        "$GENERATED_DIR/wofi.css" \
        "$HOME/.config/wofi/style.css"

}
