#!/usr/bin/env bash

kitty_render() {

    render_template \
        "$MODULES_DIR/kitty/templates/kitty.conf.template" \
        "$GENERATED_DIR/kitty.conf" || return 1

    if [[ -n "${THEME_TXN_STAGE_DIR:-}" ]]; then
        python3 "$MODULES_DIR/kitty/prepare_config.py" \
            "$HOME/.config/kitty/kitty.conf" "$THEME_TXN_STAGE_DIR/kitty-main.conf"
    fi

}

kitty_apply() {

    kitty_render

    kitty_install

    if ! kitty_reload; then
        log_warn "Kitty configuration installed, but live color reload failed."
    fi

}
