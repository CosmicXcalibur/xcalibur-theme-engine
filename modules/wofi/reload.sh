#!/usr/bin/env bash

# ==========================================================
# Wofi Reload
# ==========================================================

wofi_reload() {

    if pgrep -x wofi >/dev/null 2>&1; then
        if ! pkill -x wofi; then
            log_warn "Unable to stop the running Wofi instance."
            return 1
        fi
    fi

}
