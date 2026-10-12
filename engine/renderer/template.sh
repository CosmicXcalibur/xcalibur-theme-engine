#!/usr/bin/env bash

# ==========================================================
# Xcalibur Generic Template Renderer
# ==========================================================

render_template() {
    local template="$1"
    local output="$2"
    python3 "$ENGINE_DIR/renderer/render_template.py" \
        "$template" "$GENERATED_DIR/colors.sh" "$output"
}
