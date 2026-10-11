#!/usr/bin/env bash

kitty_reload() {
    if ! pgrep -x kitty >/dev/null 2>&1; then
        return 0
    fi
    command -v kitty >/dev/null 2>&1 || return 1
    kitty @ set-colors "$HOME/.config/kitty/current-theme.conf"

}
