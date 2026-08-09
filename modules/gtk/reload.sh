#!/usr/bin/env bash

# ==========================================================
# Xcalibur GTK Reload
# ==========================================================

gtk_reload() {

    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' \
        >/dev/null 2>&1 || true
}
