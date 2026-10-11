#!/usr/bin/env bash

# ==========================================================
# Xcalibur SwayNC Reload
# ==========================================================

swaync_reload() {
    if ! pgrep -x swaync >/dev/null 2>&1; then
        return 0
    fi
    if ! pkill -x swaync; then
        log_error "Unable to stop the running SwayNC instance."
        return 1
    fi
    sleep 0.5

    if ! command -v swaync >/dev/null 2>&1; then
        return 1
    fi

    swaync >/dev/null 2>&1 &

}
