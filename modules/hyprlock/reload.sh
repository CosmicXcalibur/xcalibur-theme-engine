#!/usr/bin/env bash

# ==========================================================
# Xcalibur Hyprlock Reload
# ==========================================================

hyprlock_reload() {

    if pgrep -x hyprlock >/dev/null 2>&1; then
        pkill -x hyprlock
    fi
}
