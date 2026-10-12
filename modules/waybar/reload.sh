#!/usr/bin/env bash

waybar_reload() {

    if pgrep -x waybar >/dev/null 2>&1; then
        if ! pkill -x waybar; then
            log_warn "Unable to stop the running Waybar instance."
            return 1
        fi
    fi

    if ! command -v waybar >/dev/null 2>&1; then
        return 1
    fi

    ( if [[ -n "${THEME_TXN_LOCK_FD:-}" ]]; then exec {THEME_TXN_LOCK_FD}>&-; fi; waybar >/dev/null 2>&1 ) &

}
