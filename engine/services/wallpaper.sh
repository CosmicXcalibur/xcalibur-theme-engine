#!/usr/bin/env bash

# ==========================================================
# Helper Functions
# ==========================================================

wallpaper_validate() {

    local wallpaper="$1"

    [[ -f "$WALLPAPER_DIR/$wallpaper" ]]
}

wallpaper_save_state() {

    local wallpaper="$1"

    echo "$wallpaper" > "$STATE_DIR/current_wallpaper"
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

    local wallpaper="$1"

    if [[ -z "$wallpaper" ]]; then
        log_error "Usage: theme wallpaper set <file>"
        return 1
    fi

    if ! wallpaper_validate "$wallpaper"; then
        log_error "Wallpaper not found: $wallpaper"
        return 1
    fi

    local fullpath="$WALLPAPER_DIR/$wallpaper"

    wallpaper_save_state "$fullpath"

    wallpaper_reload "$fullpath"

    theme_apply

    log_success "Wallpaper updated."

}



wallpaper_random() {


    local wallpaper

    wallpaper=$(basename "$(wallpaper_pick_random)")

    if [[ -z "$wallpaper" ]]; then
        log_error "No wallpapers found."
        return 1
    fi

    wallpaper_set "$wallpaper"
}
