#!/usr/bin/env bash

# ==========================================================
# Helper Functions
# ==========================================================

wallpaper_validate() {
    local wallpaper="$1"
    [[ -f "$wallpaper" && -r "$wallpaper" && ! -L "$wallpaper" &&
       ! "$wallpaper" =~ [[:cntrl:]] ]] &&
        fs_directory_safe "$(dirname "$wallpaper")" false &&
        [[ "${wallpaper,,}" =~ \.(png|jpg|jpeg|webp)$ ]]
}

wallpaper_save_state() {
    local wallpaper="$1"
    local state_file
    fs_directory_safe "$STATE_DIR" true || return 1
    [[ ! -L "$STATE_DIR/current_wallpaper" ]] || return 1
    state_file="$(mktemp "$STATE_DIR/.current_wallpaper.XXXXXX")" || return 1
    if ! printf '%s\n' "$wallpaper" > "$state_file" ||
       ! mv -f -- "$state_file" "$STATE_DIR/current_wallpaper"; then
        rm -f -- "$state_file"
        return 1
    fi
}

wallpaper_reload() {
    local wallpaper="$1"
    local monitor
    if [[ "${WALLPAPER_BACKEND:-hyprpaper}" != hyprpaper ]]; then
        log_error "Unsupported wallpaper backend: ${WALLPAPER_BACKEND:-}"
        return 1
    fi
    if ! cmd_exists hyprctl || ! cmd_exists timeout; then
        log_error "Hyprpaper backend requires hyprctl and timeout."
        return 1
    fi
    monitor="$(timeout 10s hyprctl monitors | awk '/^Monitor / {print $2; exit}')" || return 1

    if [[ -z "$monitor" ]]; then
        log_error "Unable to detect monitor."
        return 1
    fi

    timeout 10s hyprctl hyprpaper preload "$wallpaper" || return 1
    timeout 10s hyprctl hyprpaper wallpaper "$monitor,$wallpaper,cover"
}

wallpaper_find_all() {

    find "$WALLPAPER_DIR" \
        -maxdepth 1 \
        -type f \
        \( \
            -iname "*.png" \
            -o -iname "*.jpg" \
            -o -iname "*.jpeg" \
            -o -iname "*.webp" \
        \) | sort
}

wallpaper_pick_random() {

    wallpaper_find_all | shuf -n 1
}

# ==========================================================
# Public API
# ==========================================================

wallpaper_list() {

    if [[ ! -d "$WALLPAPER_DIR" ]]; then
        log_error "Wallpaper directory not found."
        return 1
    fi

    echo
    log_info "Available Wallpapers"
    echo

    wallpaper_find_all
}

wallpaper_current() {

    if [[ ! -f "$STATE_DIR/current_wallpaper" || -L "$STATE_DIR/current_wallpaper" ]]; then
        log_warn "No wallpaper selected."
        return 1
    fi

    echo
    log_info "Current Wallpaper"
    echo

    cat "$STATE_DIR/current_wallpaper"
}

wallpaper_set() {
    if [[ "$#" -ne 1 || -z "$1" ]]; then
        log_error "Usage: theme wallpaper set <file>"
        return 2
    fi
    local wallpaper="$1" fullpath previous="" previous_colors="" rollback_failed=0
    if [[ "$wallpaper" = /* ]]; then
        fullpath="$wallpaper"
    else
        fullpath="$WALLPAPER_DIR/$wallpaper"
    fi

    if ! wallpaper_validate "$fullpath"; then
        log_error "Wallpaper not found: $wallpaper"
        return 1
    fi

    if ! fs_directory_safe "$STATE_DIR" true || [[ -L "$STATE_DIR/current_wallpaper" ]]; then
        log_error "Unsafe wallpaper state destination."
        return 1
    fi
    if [[ -f "$STATE_DIR/current_wallpaper" ]]; then
        previous="$(< "$STATE_DIR/current_wallpaper")"
    fi
    if [[ -f "$RUNTIME_COLORS" ]]; then
        previous_colors="$(mktemp "$STATE_DIR/.colors.previous.XXXXXX")" || return 1
        cp -- "$RUNTIME_COLORS" "$previous_colors" || {
            rm -f -- "$previous_colors"
            return 1
        }
    fi

    if ! wallpaper_reload "$fullpath"; then
        [[ -z "$previous_colors" ]] || rm -f -- "$previous_colors"
        if [[ -n "$previous" && -f "$previous" ]]; then
            wallpaper_reload "$previous" || log_error "Unable to restore the previous wallpaper after backend failure."
        fi
        log_error "Unable to set wallpaper; recorded state was not changed."
        return 1
    fi
    WALLPAPER_CANDIDATE="$fullpath"
    THEME_APPLY_COMMIT=wallpaper_commit_state
    if ! theme_apply; then
        unset WALLPAPER_CANDIDATE THEME_APPLY_COMMIT
        if [[ -n "$previous_colors" ]]; then
            mv -f -- "$previous_colors" "$RUNTIME_COLORS" || rollback_failed=1
        else
            rm -f -- "$RUNTIME_COLORS" || rollback_failed=1
        fi
        if [[ -n "$previous" && -f "$previous" ]]; then
            wallpaper_reload "$previous" || rollback_failed=1
        else
            log_warn "No recorded previous wallpaper can be restored automatically."
        fi
        ((rollback_failed == 0)) || log_error "Wallpaper or palette rollback was incomplete; palette backup: ${previous_colors:-none}."
        log_error "Theme application failed; wallpaper state was not changed."
        return 1
    fi

    unset WALLPAPER_CANDIDATE THEME_APPLY_COMMIT
    [[ -z "$previous_colors" ]] || rm -f -- "$previous_colors"

    log_success "Wallpaper updated."

}

wallpaper_commit_state() {
    wallpaper_save_state "$WALLPAPER_CANDIDATE"
}



wallpaper_random() {


    local wallpaper

    wallpaper="$(wallpaper_pick_random)"

    if [[ -z "$wallpaper" ]]; then
        log_error "No wallpapers found."
        return 1
    fi

    wallpaper_set "$wallpaper"
}
