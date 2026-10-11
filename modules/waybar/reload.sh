#!/usr/bin/env bash

waybar_reload() {
    if ! pgrep -x waybar >/dev/null 2>&1; then
        return 0
    fi
    pkill -USR2 -x waybar || {
        log_error "Unable to signal Waybar to reload."
        return 1
    }
}
