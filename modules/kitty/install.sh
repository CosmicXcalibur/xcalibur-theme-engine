#!/usr/bin/env bash

kitty_install() {

    mkdir -p "$HOME/.config/kitty"

    cp \
        "$GENERATED_DIR/kitty.conf" \
        "$HOME/.config/kitty/current-theme.conf"

}
