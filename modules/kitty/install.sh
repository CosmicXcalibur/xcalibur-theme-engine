#!/usr/bin/env bash

kitty_install() {

    fs_install_atomic \
        "$GENERATED_DIR/kitty.conf" \
        "$HOME/.config/kitty/current-theme.conf"

}
