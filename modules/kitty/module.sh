#!/usr/bin/env bash

kitty_render() {

    render_template \
        "$MODULES_DIR/kitty/templates/kitty.conf.template" \
        "$GENERATED_DIR/kitty.conf"

}

kitty_apply() {

    kitty_render

    kitty_install

    kitty_reload

}
