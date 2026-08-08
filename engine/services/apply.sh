#!/usr/bin/env bash

# ==========================================================
# Theme Apply Service
# ==========================================================

theme_apply() {

    log_info "Applying theme..."

    # Generate runtime palette
    color_generate

    # Apply all discovered modules dynamically
    for module_dir in "$MODULES_DIR"/*; do

        [[ -d "$module_dir" ]] || continue

        local module
        module="$(basename "$module_dir")"

        local fn="${module}_apply"

        if declare -F "$fn" >/dev/null; then

            log_info "Applying module: $module"

            "$fn"

        else

            log_info "Skipping module: $module (no ${fn} function)"

        fi

    done

    log_success "Theme applied."

}
