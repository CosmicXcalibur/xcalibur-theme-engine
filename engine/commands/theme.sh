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
        *)
            echo "Usage:"
            echo "    theme list"
            echo "    theme current"
            return 1
            ;;
    esac
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

        unset THEME_ID THEME_NAME THEME_VERSION THEME_AUTHOR THEME_DESCRIPTION

        source "$manifest"

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

    local manifest="$THEMES_DIR/$theme_id/theme.conf"

    if [[ ! -f "$manifest" ]]; then
        log_warn "Current theme '$theme_id' is not installed."
        return 1
    fi

    unset THEME_ID THEME_NAME THEME_VERSION THEME_AUTHOR THEME_DESCRIPTION

    source "$manifest"

    echo "Current theme:"
    echo
    echo "  ID:      $THEME_ID"
    echo "  Name:    $THEME_NAME"
    echo "  Version: $THEME_VERSION"
    echo "  Author:  $THEME_AUTHOR"
}
