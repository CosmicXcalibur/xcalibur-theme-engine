#!/usr/bin/env bash

# ==========================================================
# Xcalibur GTK Module
# ==========================================================

gtk_render() {

    render_template \
        "$MODULES_DIR/gtk/templates/gtk.css.template" \
        "$GENERATED_DIR/gtk.css"

    cp \
        "$GENERATED_DIR/gtk.css" \
        "$GENERATED_DIR/gtk-3.0.css"

    cp \
        "$GENERATED_DIR/gtk.css" \
        "$GENERATED_DIR/gtk-4.0.css"
}

gtk_apply() {

    log_info "Applying GTK theme..."

    gtk_render

    gtk_install

    gtk_reload
}
