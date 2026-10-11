#!/usr/bin/env bash

# ==========================================================
# Theme Pack Commands
# ==========================================================

command_theme() {
    local subcommand="${1:-}"

    case "$subcommand" in
        list)
            [[ "$#" -eq 1 ]] || { log_error "Usage: theme list"; return 2; }
            theme_list
            ;;
        current)
            [[ "$#" -eq 1 ]] || { log_error "Usage: theme current"; return 2; }
            theme_current
            ;;
        set)
            theme_set "$@"
            ;;
        install)
            theme_install "$@"
            ;;
        *)
            echo "Usage:"
            echo "    theme list"
            echo "    theme current"
            echo "    theme set <theme-id>"
            echo "    theme install <owner/repo>"
            return 2
            ;;
    esac
}

theme_set() {
    if [[ "$#" -ne 2 ]]; then
        log_error "Usage: theme set <theme-id>"
        return 2
    fi

    local theme_id="$2"
    local theme_dir="$THEMES_DIR/$theme_id"
    local previous_colors_file=""
    local had_previous_colors=false

    if ! theme_id_validate "$theme_id"; then
        log_error "Invalid theme ID: $theme_id"
        return 2
    fi

    if ! fs_directory_safe "$THEMES_DIR" false; then
        log_error "Unsafe themes directory: $THEMES_DIR"
        return 1
    fi

    if [[ ! -d "$theme_dir" || -L "$theme_dir" ]]; then
        log_error "Theme '$theme_id' is not installed."
        return 1
    fi

    if ! theme_install_root_file_validate "$theme_dir/theme.conf" ||
       ! theme_install_root_file_validate "$theme_dir/palette.conf"; then
        log_error "Theme '$theme_id' must contain regular manifest and palette files."
        return 1
    fi

    if ! theme_manifest_load "$theme_dir/theme.conf" "$theme_id"; then
        log_error "Theme '$theme_id' is invalid: $THEME_MANIFEST_ERROR"
        return 1
    fi

    if ! theme_definition_load "$theme_dir/palette.conf" "$theme_id"; then
        log_error "Theme '$theme_id' is invalid: $THEME_DEFINITION_ERROR"
        return 1
    fi

    if ! fs_directory_safe "$STATE_DIR" true || [[ -L "$CURRENT_THEME_FILE" ]]; then
        log_error "Unable to create state directory: $STATE_DIR"
        return 1
    fi

    if [[ -f "$RUNTIME_COLORS" ]]; then
        if ! previous_colors_file="$(mktemp "$STATE_DIR/.colors.previous.XXXXXX")" ||
           ! cp -- "$RUNTIME_COLORS" "$previous_colors_file"; then
            [[ -z "$previous_colors_file" ]] || rm -f -- "$previous_colors_file"
            log_error "Unable to back up runtime palette."
            return 1
        fi
        had_previous_colors=true
    fi

    THEME_CANDIDATE_ID="$theme_id"
    THEME_APPLY_COMMIT=theme_set_commit_state
    if ! theme_apply; then
        unset THEME_CANDIDATE_ID THEME_APPLY_COMMIT
        if [[ "$had_previous_colors" == true ]]; then
            if ! mv -f -- "$previous_colors_file" "$RUNTIME_COLORS"; then
                log_error "Unable to restore previous runtime palette; backup remains at $previous_colors_file"
                return 1
            fi
        else
            rm -f -- "$RUNTIME_COLORS" || return 1
        fi

        log_error "Unable to apply theme '$theme_id'."
        [[ -z "$previous_colors_file" ]] || rm -f -- "$previous_colors_file"
        return 1
    fi

    unset THEME_CANDIDATE_ID THEME_APPLY_COMMIT
    log_success "Theme selected: $theme_id"

    [[ -z "$previous_colors_file" ]] || rm -f -- "$previous_colors_file"
}

theme_set_commit_state() {
    theme_write_current_state "$THEME_CANDIDATE_ID"
}

theme_write_current_state() {
    local theme_id="$1"
    local state_file

    if ! fs_directory_safe "$STATE_DIR" true || [[ -L "$CURRENT_THEME_FILE" ]] ||
       ! state_file="$(mktemp "$STATE_DIR/.current_theme.XXXXXX")"; then
        return 1
    fi

    if ! printf '%s\n' "$theme_id" > "$state_file"; then
        rm -f -- "$state_file"
        return 1
    fi

    if ! mv -f -- "$state_file" "$CURRENT_THEME_FILE"; then
        rm -f -- "$state_file"
        return 1
    fi
}

theme_list() {
    local found=false

    if [[ ! -d "$THEMES_DIR" ]]; then
        log_warn "Themes directory is missing: $THEMES_DIR"
        return 1
    fi
    fs_directory_safe "$THEMES_DIR" false || { log_error "Unsafe themes directory: $THEMES_DIR"; return 1; }

    echo "Installed themes:"
    echo

    for theme_dir in "$THEMES_DIR"/*; do
        [[ -d "$theme_dir" && ! -L "$theme_dir" ]] || continue

        local manifest="$theme_dir/theme.conf"

        if ! theme_install_root_file_validate "$manifest" ||
           ! theme_install_root_file_validate "$theme_dir/palette.conf"; then
            log_warn "Skipping $(basename "$theme_dir"): missing or unsafe theme files"
            continue
        fi

        if ! theme_manifest_load "$manifest" "$(basename "$theme_dir")"; then
            log_warn "Skipping $(basename "$theme_dir"): $THEME_MANIFEST_ERROR"
            continue
        fi

        if ! theme_definition_load "$theme_dir/palette.conf" "$THEME_ID"; then
            log_warn "Skipping $(basename "$theme_dir"): $THEME_DEFINITION_ERROR"
            continue
        fi

        printf "  %-20s %-25s %s\n" \
            "$THEME_ID" \
            "$THEME_NAME" \
            "$THEME_VERSION"

        found=true
    done

    if [[ "$found" == false ]]; then
        echo "  No themes installed."
    fi
}

theme_current() {
    if [[ -L "$CURRENT_THEME_FILE" ]]; then
        log_warn "Current theme state is a symlink."
        return 1
    fi

    if [[ ! -f "$CURRENT_THEME_FILE" ]]; then
        echo "No theme is currently selected."
        return 0
    fi

    local theme_id
    theme_id="$(cat "$CURRENT_THEME_FILE")"

    if [[ -z "$theme_id" ]]; then
        echo "No theme is currently selected."
        return 0
    fi

    if ! theme_id_validate "$theme_id"; then
        log_warn "Current theme ID is invalid."
        return 1
    fi

    local manifest="$THEMES_DIR/$theme_id/theme.conf"

    fs_directory_safe "$THEMES_DIR" false || { log_error "Unsafe themes directory: $THEMES_DIR"; return 1; }

    if [[ -L "$THEMES_DIR/$theme_id" ]] ||
       ! theme_install_root_file_validate "$manifest" ||
       ! theme_install_root_file_validate "$THEMES_DIR/$theme_id/palette.conf"; then
        log_warn "Current theme '$theme_id' is not installed."
        return 1
    fi

    if ! theme_manifest_load "$manifest" "$theme_id"; then
        log_warn "Current theme '$theme_id' is invalid: $THEME_MANIFEST_ERROR"
        return 1
    fi

    if ! theme_definition_load "$THEMES_DIR/$theme_id/palette.conf" "$theme_id"; then
        log_warn "Current theme '$theme_id' is invalid: $THEME_DEFINITION_ERROR"
        return 1
    fi

    echo "Current theme:"
    echo
    echo "  ID:      $THEME_ID"
    echo "  Name:    $THEME_NAME"
    echo "  Version: $THEME_VERSION"
    echo "  Author:  $THEME_AUTHOR"
}
