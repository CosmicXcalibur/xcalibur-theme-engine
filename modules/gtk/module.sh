#!/usr/bin/env bash

# ==========================================================
# Xcalibur GTK Module
# ==========================================================

gtk_render() {

    render_template \
        "$MODULES_DIR/gtk/templates/gtk.css.template" \
        "$GENERATED_DIR/gtk.css" || return 1

    cp \
        "$GENERATED_DIR/gtk.css" \
        "$GENERATED_DIR/gtk-3.0.css" || return 1

    cp \
        "$GENERATED_DIR/gtk.css" \
        "$GENERATED_DIR/gtk-4.0.css" || return 1
}

gtk_apply() {

    log_info "Applying GTK theme..."

    gtk_render || return 1
    gtk_install || return 1
    gtk_reload
}
