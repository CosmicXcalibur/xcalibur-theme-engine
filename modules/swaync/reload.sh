#!/usr/bin/env bash

# ==========================================================
# Xcalibur SwayNC Reload
# ==========================================================

swaync_reload() {

    if pgrep -x swaync >/dev/null 2>&1; then
        pkill -x swaync
        sleep 0.5
    fi

    swaync >/dev/null 2>&1 &

}
