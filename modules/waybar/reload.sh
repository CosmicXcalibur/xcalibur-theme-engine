#!/usr/bin/env bash

waybar_reload() {

    if pgrep -x waybar >/dev/null 2>&1; then
        if ! pkill -x waybar; then
            log_warn "Unable to stop the running Waybar instance; continuing with reload."
        fi
    fi

    if ! command -v waybar >/dev/null 2>&1; then
        return 1
    fi

    waybar >/dev/null 2>&1 &

}
