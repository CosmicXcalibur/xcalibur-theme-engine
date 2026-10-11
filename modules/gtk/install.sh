#!/usr/bin/env bash

# ==========================================================
# Xcalibur GTK Install
# ==========================================================

gtk_install() {

    local gtk3_dir="$HOME/.config/gtk-3.0"
    local gtk4_dir="$HOME/.config/gtk-4.0"

    fs_install_atomic \
        "$GENERATED_DIR/gtk-3.0.css" \
        "$gtk3_dir/gtk.css" || return 1

    fs_install_atomic \
        "$GENERATED_DIR/gtk-4.0.css" \
        "$gtk4_dir/gtk.css"
}
