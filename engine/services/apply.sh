#!/usr/bin/env bash

# ==========================================================
# Theme Apply Service
# ==========================================================

theme_apply() {
    log_info "Applying theme..."
    THEME_APPLY_PHASE=generate
    color_generate || return 1
    local module_dir module enabled_var phase fn
    local -a enabled_modules=()

    for module_dir in "$MODULES_DIR"/*; do
        [[ -d "$module_dir" ]] || continue
        module="$(basename "$module_dir")"
        enabled_var="${module^^}_ENABLED"
        if [[ "${!enabled_var:-false}" == true ]]; then
            enabled_modules+=("$module")
        else
            log_info "Skipping disabled module: $module"
        fi
    done

    # Validate all generated files before changing any live application file.
    THEME_APPLY_PHASE=render
    for module in "${enabled_modules[@]}"; do
        fn="${module}_render"
        if ! declare -F "$fn" >/dev/null || ! "$fn"; then
            log_error "Unable to render module: $module"
            return 1
        fi
    done

    for phase in install reload; do
        THEME_APPLY_PHASE="$phase"
        for module in "${enabled_modules[@]}"; do
            fn="${module}_${phase}"
            if ! declare -F "$fn" >/dev/null || ! "$fn"; then
                log_error "Unable to $phase module: $module; earlier installs may remain applied."
                return 1
            fi
        done
    done

    THEME_APPLY_PHASE=complete
    log_success "Theme applied to ${#enabled_modules[@]} modules."
}
