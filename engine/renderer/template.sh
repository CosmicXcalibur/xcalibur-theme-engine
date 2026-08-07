#!/usr/bin/env bash

# ==========================================================
# Xcalibur Generic Template Renderer
# ==========================================================

render_template() {

    local template="$1"
    local output="$2"

    source "$GENERATED_DIR/colors.sh"

    cp "$template" "$output"

    while IFS='=' read -r key value; do

        [[ "$key" =~ ^#.*$ ]] && continue
        [[ -z "$key" ]] && continue

        value="${value%\"}"
        value="${value#\"}"

        sed -i "s|{{$key}}|$value|g" "$output"

    done < <(

        grep '=' "$GENERATED_DIR/colors.sh"

    )

}
