#!/usr/bin/env bash

# ==========================================================
# Xcalibur GTK Install
# ==========================================================

gtk_install() {

    local gtk3_dir="$HOME/.config/gtk-3.0"
    local gtk4_dir="$HOME/.config/gtk-4.0"

    mkdir -p "$gtk3_dir" "$gtk4_dir"

    install -m 644 \
        "$GENERATED_DIR/gtk-3.0.css" \
        "$gtk3_dir/gtk.css"

    install -m 644 \
        "$GENERATED_DIR/gtk-4.0.css" \
        "$gtk4_dir/gtk.css"
}
