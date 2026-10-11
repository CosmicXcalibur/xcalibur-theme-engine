#!/usr/bin/env bash

# ==========================================================
# Xcalibur GTK Reload
# ==========================================================

gtk_reload() {
    # GTK loads this stylesheet when applications start; no global desktop
    # preference needs to be changed by the theme engine.
    return 0
}
