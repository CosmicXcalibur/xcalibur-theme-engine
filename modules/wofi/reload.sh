#!/usr/bin/env bash

# ==========================================================
# Wofi Reload
# ==========================================================

wofi_reload() {

    if pgrep -x wofi >/dev/null 2>&1; then
        pkill -x wofi
    fi

}
