#!/usr/bin/env bash

# ==========================================================
# Helper Functions
# ==========================================================

wallpaper_validate() {
    local wallpaper="$1"
    [[ -f "$wallpaper" && -r "$wallpaper" && ! "$wallpaper" =~ [[:cntrl:]] ]] &&
        [[ "${wallpaper,,}" =~ \.(png|jpg|jpeg|webp)$ ]]
}

wallpaper_save_state() {
    local wallpaper="$1"
    local state_file
    mkdir -p "$STATE_DIR" || return 1
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

    monitor=$(hyprctl monitors | awk '/Monitor/ {print $2; exit}')

    if [[ -z "$monitor" ]]; then
        log_error "Unable to detect monitor."
        return 1
    fi

    hyprctl hyprpaper wallpaper "$monitor,$wallpaper,cover"
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

    if [[ ! -f "$STATE_DIR/current_wallpaper" ]]; then
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
        return 1
    fi
    local wallpaper="$1" fullpath
    if [[ "$wallpaper" = /* ]]; then
        fullpath="$wallpaper"
    else
        fullpath="$WALLPAPER_DIR/$wallpaper"
    fi

    if ! wallpaper_validate "$fullpath"; then
        log_error "Wallpaper not found: $wallpaper"
        return 1
    fi

    if ! wallpaper_reload "$fullpath"; then
        log_error "Unable to set wallpaper."
        return 1
    fi
    if ! wallpaper_save_state "$fullpath"; then
        log_error "Wallpaper changed, but its state could not be recorded."
        return 1
    fi
    if ! theme_apply; then
        log_error "Wallpaper changed, but theme application failed."
        return 1
    fi

    log_success "Wallpaper updated."

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
