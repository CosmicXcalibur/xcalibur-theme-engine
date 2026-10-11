#!/usr/bin/env bash

# ==========================================================
# Xcalibur SwayNC Reload
# ==========================================================

swaync_reload() {
    if ! pgrep -x swaync >/dev/null 2>&1; then
        return 0
    fi
    if ! command -v swaync-client >/dev/null 2>&1; then
        log_error "swaync-client is required to reload running SwayNC."
        return 1
    fi
    swaync-client -rs || {
        log_error "Unable to reload SwayNC CSS."
        return 1
    }
}
