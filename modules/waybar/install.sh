#!/usr/bin/env bash

waybar_install() {

    mkdir -p "$HOME/.config/waybar/styles/colors"

    cp \
        "$GENERATED_DIR/xcalibur.css" \
        "$HOME/.config/waybar/styles/colors/xcalibur.css"

}
