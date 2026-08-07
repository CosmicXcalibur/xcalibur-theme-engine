#!/usr/bin/env bash

waybar_render() {

    render_template \
        "$MODULES_DIR/waybar/templates/xcalibur.css.template" \
        "$GENERATED_DIR/xcalibur.css"

}

waybar_apply() {

    waybar_render

    waybar_install

    waybar_reload

}
