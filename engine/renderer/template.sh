#!/usr/bin/env bash

# ==========================================================
# Xcalibur Template Renderer
# ==========================================================

render_template() {

    local template="$1"
    local output="$2"

    source "$GENERATED_DIR/colors.sh"

    cp "$template" "$output"

    sed -i "s|{{BACKGROUND}}|$BACKGROUND|g" "$output"
    sed -i "s|{{FOREGROUND}}|$FOREGROUND|g" "$output"
    sed -i "s|{{CURSOR}}|$CURSOR|g" "$output"

    sed -i "s|{{PRIMARY}}|$PRIMARY|g" "$output"
    sed -i "s|{{SECONDARY}}|$SECONDARY|g" "$output"
    sed -i "s|{{ACCENT}}|$ACCENT|g" "$output"

    sed -i "s|{{SUCCESS}}|$SUCCESS|g" "$output"
    sed -i "s|{{WARNING}}|$WARNING|g" "$output"
    sed -i "s|{{ERROR}}|$ERROR|g" "$output"

    for i in {0..15}; do

        eval color="\$COLOR$i"

        sed -i "s|{{COLOR$i}}|$color|g" "$output"

    done

}	
