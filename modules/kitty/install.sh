#!/usr/bin/env bash

kitty_install() {

    mkdir -p "$HOME/.config/kitty"

    cp \
        "$GENERATED_DIR/kitty.conf" \
        "$HOME/.config/kitty/current-theme.conf"

}

kitty_transaction_plan() {
    theme_txn_plan "$GENERATED_DIR/kitty.conf" "$HOME/.config/kitty/current-theme.conf" || return 1
    theme_txn_plan "$THEME_TXN_STAGE_DIR/kitty-main.conf" "$HOME/.config/kitty/kitty.conf"
}
