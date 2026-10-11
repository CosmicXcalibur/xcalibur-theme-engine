#!/usr/bin/env bash

waybar_reload() {
    if ! pgrep -x waybar >/dev/null 2>&1; then
        return 0
    fi
    if ! pkill -x waybar; then
        log_error "Unable to stop the running Waybar instance."
        return 1
    fi

    if ! command -v waybar >/dev/null 2>&1; then
        return 1
    fi

    waybar >/dev/null 2>&1 &

}
