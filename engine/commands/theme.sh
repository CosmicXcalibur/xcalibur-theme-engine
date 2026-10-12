#!/usr/bin/env bash

# ==========================================================
# Theme Pack Commands
# ==========================================================

command_theme() {
    local subcommand="${1:-}"

    case "$subcommand" in
        list)
            [[ "$#" -eq 1 ]] || { log_error "Usage: theme list"; return 1; }
            theme_list
            ;;
        current)
            [[ "$#" -eq 1 ]] || { log_error "Usage: theme current"; return 1; }
            theme_current
            ;;
        info)
            theme_info "$@"
            ;;
        validate)
            theme_validate "$@"
            ;;
        remove)
            theme_remove "$@"
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
            echo "    theme info <theme-id>"
            echo "    theme validate <theme-id>|--all"
            echo "    theme set <theme-id>"
            echo "    theme remove <theme-id>"
            echo "    theme install <owner/repo>"
            echo "    theme install catppuccin/palette --format catppuccin --variant <latte|frappe|macchiato|mocha>"
            echo "    theme install rose-pine/rose-pine-palette --format rose-pine --variant <main|moon|dawn>"
            echo "    theme install nordtheme/nord --format nord"
            echo
            echo "Examples:"
            echo "    theme install catppuccin/palette --format catppuccin --variant mocha"
            echo "    theme install rose-pine/rose-pine-palette --format rose-pine --variant moon"
            echo "    theme install nordtheme/nord --format nord"
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
    local previous_theme_file=""
    local had_previous_theme=false

    if ! theme_id_validate "$theme_id"; then
        log_error "Invalid theme ID: $(theme_display_value "$theme_id")"
        return 1
    fi

    if ! theme_pack_validate "$theme_id"; then
        log_error "Theme '$theme_id' is invalid: $(theme_display_value "$THEME_PACK_ERROR")"
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
    local theme_dir theme_id active_id="" active_status="?"
    local display_name display_version validation_status

    if ! theme_library_check; then
        log_error "$(theme_display_value "$THEME_PACK_ERROR")"
        return 1
    fi
    if theme_active_id_read; then
        if [[ -d "$THEMES_DIR/$THEME_ACTIVE_ID" && ! -L "$THEMES_DIR/$THEME_ACTIVE_ID" ]]; then
            active_id="$THEME_ACTIVE_ID"
            active_status=""
        fi
    fi

    echo "Installed themes:"
    echo
    printf "  %-22s %-28s %-12s %-8s %s\n" "ID" "Name" "Version" "Active" "Validation"

    for theme_dir in "$THEMES_DIR"/* "$THEMES_DIR"/.[!.]* "$THEMES_DIR"/..?*; do
        [[ -e "$theme_dir" || -L "$theme_dir" ]] || continue
        theme_id="${theme_dir##*/}"
        display_name="-"
        display_version="-"
        if theme_pack_validate "$theme_id"; then
            display_name="$(theme_display_value "$THEME_NAME")"
            display_version="$(theme_display_value "$THEME_VERSION")"
            validation_status="valid"
        else
            validation_status="invalid: $(theme_display_value "$THEME_PACK_ERROR")"
        fi
        local is_active="$active_status"
        if [[ -z "$active_status" ]]; then
            is_active="no"
            [[ "$theme_id" == "$active_id" ]] && is_active="yes"
        fi
        printf "  %-22s %-28s %-12s %-8s %s\n" \
            "$(theme_display_value "$theme_id")" "$display_name" "$display_version" "$is_active" "$validation_status"
        found=true
    done

    if [[ "$found" == false ]]; then
        echo "  No themes installed."
    fi
}

theme_current() {
    if [[ ! -e "$CURRENT_THEME_FILE" && ! -L "$CURRENT_THEME_FILE" ]]; then
        echo "No theme is currently selected."
        return 0
    fi

    if ! theme_active_id_read; then
        log_warn "$(theme_display_value "$THEME_ACTIVE_ERROR")"
        return 1
    fi
    local theme_id="$THEME_ACTIVE_ID"

    if ! theme_pack_validate "$theme_id"; then
        log_warn "Current theme '$theme_id' is invalid: $(theme_display_value "$THEME_PACK_ERROR")"
        return 1
    fi

    echo "Current theme:"
    echo
    echo "  ID:      $THEME_ID"
    echo "  Name:    $(theme_display_value "$THEME_NAME")"
    echo "  Version: $(theme_display_value "$THEME_VERSION")"
    echo "  Author:  $(theme_display_value "$THEME_AUTHOR")"
}

theme_info() {
    if [[ "$#" -ne 2 || "$2" == --* ]]; then
        log_error "Usage: theme info <theme-id>"
        return 1
    fi
    local theme_id="$2" role
    if ! theme_id_validate "$theme_id"; then
        log_error "Invalid theme ID: $(theme_display_value "$theme_id")"
        return 1
    fi
    if ! theme_pack_validate "$theme_id"; then
        printf 'Theme ID: %s\nLocation: %s\nValidation: invalid\n' "$theme_id" "$THEMES_DIR/$theme_id"
        log_error "$(theme_display_value "$THEME_PACK_ERROR")"
        return 1
    fi

    printf 'Theme ID: %s\nName: %s\nVersion: %s\nAuthor: %s\nDescription: %s\nLocation: %s\nDefinition version: 1\nValidation: valid\n' \
        "$THEME_ID" "$(theme_display_value "$THEME_NAME")" \
        "$(theme_display_value "$THEME_VERSION")" "$(theme_display_value "$THEME_AUTHOR")" \
        "$(theme_display_value "$THEME_DESCRIPTION")" "$THEMES_DIR/$theme_id"
    echo "Semantic roles:"
    for role in "${THEME_DEFINITION_ROLES[@]}"; do
        [[ -v "THEME_DEFINITION_VALUES[$role]" ]] || continue
        printf '  %s=%s\n' "$role" "${THEME_DEFINITION_VALUES[$role]}"
    done
}

theme_validate() {
    if [[ "$#" -ne 2 ]]; then
        log_error "Usage: theme validate <theme-id>|--all"
        return 1
    fi
    if [[ "$2" != --all ]]; then
        if ! theme_id_validate "$2"; then
            log_error "Invalid theme ID: $(theme_display_value "$2")"
            return 1
        fi
        if theme_pack_validate "$2"; then
            printf 'valid: %s\n' "$2"
        else
            log_error "invalid: $2: $(theme_display_value "$THEME_PACK_ERROR")"
            return 1
        fi
        return 0
    fi

    if ! theme_library_check; then
        log_error "$(theme_display_value "$THEME_PACK_ERROR")"
        return 1
    fi
    local theme_dir theme_id checked=0 valid=0 invalid=0
    for theme_dir in "$THEMES_DIR"/* "$THEMES_DIR"/.[!.]* "$THEMES_DIR"/..?*; do
        [[ -e "$theme_dir" || -L "$theme_dir" ]] || continue
        theme_id="${theme_dir##*/}"
        ((checked+=1))
        if theme_pack_validate "$theme_id"; then
            printf 'valid: %s\n' "$(theme_display_value "$theme_id")"
            ((valid+=1))
        else
            printf 'invalid: %s: %s\n' "$(theme_display_value "$theme_id")" \
                "$(theme_display_value "$THEME_PACK_ERROR")"
            ((invalid+=1))
        fi
    done
    printf 'Checked: %d; valid: %d; invalid: %d\n' "$checked" "$valid" "$invalid"
    [[ "$invalid" -eq 0 ]]
}

theme_remove() {
    if [[ "$#" -ne 2 || "$2" == --* ]]; then
        log_error "Usage: theme remove <theme-id>"
        return 1
    fi
    local theme_id="$2" theme_dir
    if ! theme_id_validate "$theme_id"; then
        log_error "Invalid theme ID: $(theme_display_value "$theme_id")"
        return 1
    fi
    if ! theme_library_check; then
        log_error "$(theme_display_value "$THEME_PACK_ERROR")"
        return 1
    fi
    theme_dir="$THEMES_DIR/$theme_id"
    if [[ -L "$theme_dir" ]]; then
        log_error "Refusing to remove symlinked theme path: $theme_dir"
        return 1
    fi
    if [[ ! -e "$theme_dir" ]]; then
        log_error "Theme '$theme_id' is not installed."
        return 1
    fi
    if [[ ! -d "$theme_dir" ]]; then
        log_error "Theme path is not a directory: $theme_dir"
        return 1
    fi
    if ! theme_active_id_read; then
        log_error "Cannot remove a theme: $(theme_display_value "$THEME_ACTIVE_ERROR")"
        return 1
    fi
    if [[ -L "$THEMES_DIR/$THEME_ACTIVE_ID" || ! -d "$THEMES_DIR/$THEME_ACTIVE_ID" ]]; then
        log_error "Cannot remove a theme: current theme state points to a missing or unsafe pack."
        return 1
    fi
    if [[ "$theme_id" == "$THEME_ACTIVE_ID" ]]; then
        log_error "Cannot remove active theme '$theme_id'; switch to another valid theme first."
        return 1
    fi
    if ! rm -rf -- "$theme_dir"; then
        log_error "Unable to remove theme directory: $theme_dir"
        return 1
    fi
    log_success "Theme removed: $theme_id"
}
