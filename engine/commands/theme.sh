#!/usr/bin/env bash

# ==========================================================
# Theme Pack Commands
# ==========================================================

command_theme() {
    local subcommand="${1:-}"

    case "$subcommand" in
        list)
            theme_list
            ;;
        current)
            theme_current
            ;;
        set)
            theme_set "$@"
            ;;
        *)
            echo "Usage:"
            echo "    theme list"
            echo "    theme current"
            echo "    theme set <theme-id>"
            return 1
            ;;
    esac
}

theme_set() {
    if [[ "$#" -ne 2 ]]; then
        log_error "Usage: theme set <theme-id>"
        return 1
    fi

    local theme_id="$2"
    local theme_dir="$THEMES_DIR/$theme_id"
    local previous_theme_file=""
    local had_previous_theme=false

    if ! theme_id_validate "$theme_id"; then
        log_error "Invalid theme ID: $theme_id"
        return 1
    fi

    if [[ ! -d "$theme_dir" ]]; then
        log_error "Theme '$theme_id' is not installed."
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

    if ! mkdir -p "$STATE_DIR"; then
        log_error "Unable to create state directory: $STATE_DIR"
        return 1
    fi

    if [[ -f "$CURRENT_THEME_FILE" ]]; then
        if ! previous_theme_file="$(mktemp "$STATE_DIR/.current_theme.previous.XXXXXX")"; then
            log_error "Unable to create current theme backup."
            return 1
        fi

        if ! cp -- "$CURRENT_THEME_FILE" "$previous_theme_file"; then
            rm -f -- "$previous_theme_file"
            log_error "Unable to back up current theme state."
            return 1
        fi

        had_previous_theme=true
    fi

    if ! theme_write_current_state "$theme_id"; then
        [[ -z "$previous_theme_file" ]] || rm -f -- "$previous_theme_file"
        log_error "Unable to write current theme state."
        return 1
    fi

    log_success "Theme selected: $theme_id"

    if ! theme_apply; then
        if [[ "$had_previous_theme" == true ]]; then
            if ! mv -f -- "$previous_theme_file" "$CURRENT_THEME_FILE"; then
                log_error "Unable to restore previous theme state."
                return 1
            fi
        elif ! rm -f "$CURRENT_THEME_FILE"; then
            log_error "Unable to remove current theme state."
            return 1
        fi

        log_error "Unable to apply theme '$theme_id'."
        return 1
    fi

    [[ -z "$previous_theme_file" ]] || rm -f -- "$previous_theme_file"
}

theme_write_current_state() {
    local theme_id="$1"
    local state_file

    if ! state_file="$(mktemp "$STATE_DIR/.current_theme.XXXXXX")"; then
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

    echo "Installed themes:"
    echo

    for theme_dir in "$THEMES_DIR"/*; do
        [[ -d "$theme_dir" ]] || continue

        local manifest="$theme_dir/theme.conf"

        if [[ ! -f "$manifest" ]]; then
            log_warn "Skipping $(basename "$theme_dir"): missing theme.conf"
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

    if [[ ! -f "$manifest" ]]; then
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
