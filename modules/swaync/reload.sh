#!/usr/bin/env bash

# ==========================================================
# Xcalibur SwayNC Reload
# ==========================================================

swaync_reload() {

    if pgrep -x swaync >/dev/null 2>&1; then
        if ! pkill -x swaync; then
            log_warn "Unable to stop the running SwayNC instance; continuing with reload."
        fi
        sleep 0.5
    fi

    if ! command -v swaync >/dev/null 2>&1; then
        return 1
    fi

    swaync >/dev/null 2>&1 &

}
