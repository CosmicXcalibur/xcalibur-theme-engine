#!/usr/bin/env bash

kitty_render() {

    render_template \
        "$MODULES_DIR/kitty/templates/kitty.conf.template" \
        "$GENERATED_DIR/kitty.conf"

}

kitty_apply() {

    kitty_render

    kitty_install

    if ! kitty_reload; then
        log_warn "Kitty configuration installed, but live color reload failed."
    fi

}
