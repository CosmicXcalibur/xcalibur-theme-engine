#!/usr/bin/env bash

# ==========================================================
# Theme Apply Service
# ==========================================================

theme_apply_restore() {
    local backup_dir="$1"; shift
    local target index=0 failed=0
    for target in "$@"; do
        if [[ -f "$backup_dir/$index" ]]; then
            fs_install_atomic "$backup_dir/$index" "$target" "$(stat -c %a -- "$backup_dir/$index")" || failed=1
        elif [[ -e "$target" || -L "$target" ]]; then
            if [[ -L "$target" || ! -f "$target" ]] ||
               ! fs_directory_safe "$(dirname "$target")" false ||
               ! rm -f -- "$target"; then
                failed=1
            fi
        fi
        ((index+=1))
    done
    if ((failed)); then
        log_error "Rollback was incomplete; inspect application configuration before retrying."
        return 1
    fi
}

theme_apply_abort() {
    local original_generated="$1" render_stage="$2" backup_dir="$3"; shift 3
    GENERATED_DIR="$original_generated"
    if [[ -n "$backup_dir" ]]; then
        if theme_apply_restore "$backup_dir" "$@"; then
            rm -rf -- "$backup_dir" || log_error "Unable to remove rollback snapshots: $backup_dir"
        else
            log_error "Rollback snapshots were retained for manual recovery: $backup_dir"
        fi
    fi
    [[ -z "$render_stage" ]] || rm -rf -- "$render_stage" || true
}

theme_apply_restore_live() {
    local module fn failed=0
    for module in "$@"; do
        fn="${module}_reload"
        if ! declare -F "$fn" >/dev/null || ! "$fn"; then
            log_error "Unable to restore live application state for $module; restart it after reviewing its configuration."
            failed=1
        fi
    done
    ((failed == 0))
}

theme_apply() {
    log_info "Applying theme..."
    THEME_APPLY_PHASE=generate
    color_generate || return 1
    local module_dir module enabled_var phase fn target backup_dir="" index=0
    local original_generated="$GENERATED_DIR" render_stage="" generated_file
    local THEME_APPLY_PREVIOUS_GENERATED_DIR="$GENERATED_DIR"
    local -a enabled_modules=() targets=() generated_files=() reloaded_modules=()

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

    # Render into a private directory so a later failure cannot leave mixed
    # generated application files in the public runtime directory.
    THEME_APPLY_PHASE=render
    fs_directory_safe "$original_generated" true || return 1
    render_stage="$(mktemp -d "$original_generated/.render-stage.XXXXXX")" || return 1
    GENERATED_DIR="$render_stage"
    for module in "${enabled_modules[@]}"; do
        fn="${module}_render"
        if ! declare -F "$fn" >/dev/null || ! "$fn"; then
            log_error "Unable to render module: $module"
            theme_apply_abort "$original_generated" "$render_stage" ""
            return 1
        fi
    done

    # Snapshot every known destination before the first install. The module
    # installers still own their output paths and perform their own safe writes.
    for module in "${enabled_modules[@]}"; do
        case "$module" in
            kitty) targets+=("$HOME/.config/kitty/current-theme.conf"); generated_files+=(kitty.conf) ;;
            waybar) targets+=("$HOME/.config/waybar/styles/colors/xcalibur.css"); generated_files+=(xcalibur.css) ;;
            wofi) targets+=("$HOME/.config/wofi/style.css"); generated_files+=(wofi.css) ;;
            gtk) targets+=("$HOME/.config/gtk-3.0/gtk.css" "$HOME/.config/gtk-4.0/gtk.css"); generated_files+=(gtk.css gtk-3.0.css gtk-4.0.css) ;;
            hyprlock) targets+=("$HOME/.config/hypr/hyprlock.conf" "$HOME/.config/hypr/hyprlock.conf.xcalibur-backup"); generated_files+=(hyprlock.conf) ;;
            swaync) targets+=("$HOME/.config/swaync/style.css" "$HOME/.config/swaync/style.css.xcalibur-backup"); generated_files+=(swaync.css) ;;
        esac
    done
    for generated_file in "${generated_files[@]}"; do
        targets+=("$original_generated/$generated_file")
    done
    if ((${#targets[@]})); then
        if ! fs_directory_safe "${TMPDIR:-/tmp}" false; then
            log_error "Unsafe temporary directory: ${TMPDIR:-/tmp}"
            theme_apply_abort "$original_generated" "$render_stage" ""
            return 1
        fi
        backup_dir="$(mktemp -d "${TMPDIR:-/tmp}/xcalibur-rollback.XXXXXX")" || {
            theme_apply_abort "$original_generated" "$render_stage" ""
            return 1
        }
        for target in "${targets[@]}"; do
            if ! fs_directory_safe "$(dirname "$target")" true ||
               [[ -L "$target" || ( -e "$target" && ! -f "$target" ) ]]; then
                log_error "Unsafe application destination: $target"
                theme_apply_abort "$original_generated" "$render_stage" "$backup_dir"
                return 1
            fi
            if [[ -f "$target" ]] && ! cp -p -- "$target" "$backup_dir/$index"; then
                log_error "Unable to back up application destination: $target"
                theme_apply_abort "$original_generated" "$render_stage" "$backup_dir"
                return 1
            fi
            ((index+=1))
        done
    fi

    for phase in install reload; do
        THEME_APPLY_PHASE="$phase"
        for module in "${enabled_modules[@]}"; do
            fn="${module}_${phase}"
            [[ "$phase" != reload ]] || reloaded_modules+=("$module")
            if ! declare -F "$fn" >/dev/null || ! "$fn"; then
                log_error "Unable to $phase module: $module."
                theme_apply_abort "$original_generated" "$render_stage" "$backup_dir" "${targets[@]}"
                theme_apply_restore_live "${reloaded_modules[@]}" || true
                return 1
            fi
        done
    done

    THEME_APPLY_PHASE=generated
    for generated_file in "${generated_files[@]}"; do
        if ! fs_install_atomic "$render_stage/$generated_file" "$original_generated/$generated_file"; then
            log_error "Unable to publish generated module output: $generated_file"
            theme_apply_abort "$original_generated" "$render_stage" "$backup_dir" "${targets[@]}"
            theme_apply_restore_live "${reloaded_modules[@]}" || true
            return 1
        fi
    done

    if [[ -n "${THEME_APPLY_COMMIT:-}" ]]; then
        THEME_APPLY_PHASE=state
        if ! "$THEME_APPLY_COMMIT"; then
            log_error "Unable to commit theme state."
            theme_apply_abort "$original_generated" "$render_stage" "$backup_dir" "${targets[@]}"
            theme_apply_restore_live "${reloaded_modules[@]}" || true
            return 1
        fi
    fi

    GENERATED_DIR="$original_generated"
    rm -rf -- "$render_stage" || log_warn "Unable to remove render staging directory: $render_stage"
    [[ -z "$backup_dir" ]] || rm -rf -- "$backup_dir" || log_warn "Unable to remove rollback staging directory: $backup_dir"

    THEME_APPLY_PHASE=complete
    log_success "Theme applied to ${#enabled_modules[@]} modules."
}
