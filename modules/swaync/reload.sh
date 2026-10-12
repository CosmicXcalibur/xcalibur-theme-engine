#!/usr/bin/env bash

# ==========================================================
# Xcalibur SwayNC Reload
# ==========================================================

swaync_reload() {

    if pgrep -x swaync >/dev/null 2>&1; then
        if ! pkill -x swaync; then
            log_warn "Unable to stop the running SwayNC instance."
            return 1
        fi
        sleep 0.5
    fi

    if ! command -v swaync >/dev/null 2>&1; then
        return 1
    fi

    ( if [[ -n "${THEME_TXN_LOCK_FD:-}" ]]; then exec {THEME_TXN_LOCK_FD}>&-; fi; swaync >/dev/null 2>&1 ) &

}
