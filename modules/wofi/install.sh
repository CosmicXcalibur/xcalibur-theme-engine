#!/usr/bin/env bash

# ==========================================================
# Wofi Install
# ==========================================================

wofi_install() {

    mkdir -p "$HOME/.config/wofi"

    install -m 644 \
        "$GENERATED_DIR/wofi.css" \
        "$HOME/.config/wofi/style.css"

}

wofi_transaction_plan() {
    theme_txn_plan "$GENERATED_DIR/wofi.css" "$HOME/.config/wofi/style.css"
}
