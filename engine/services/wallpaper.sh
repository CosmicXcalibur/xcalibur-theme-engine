#!/usr/bin/env bash

wallpaper_list() {

    if [[ ! -d "$WALLPAPER_DIR" ]]; then
        log_error "Wallpaper directory not found:"
        echo "  $WALLPAPER_DIR"
        return 1
    fi

    echo
    log_info "Available Wallpapers"
    echo

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


wallpaper_random() {

    local wallpaper

    wallpaper=$(
        find "$WALLPAPER_DIR" \
            -maxdepth 1 \
            -type f \
            \( \
                -iname "*.png" \
                -o -iname "*.jpg" \
                -o -iname "*.jpeg" \
                -o -iname "*.webp" \
            \) \
            | shuf -n 1
    )

    if [[ -z "$wallpaper" ]]; then
        log_error "No wallpapers found."
        return 1
    fi

    wallpaper_set "$(basename "$wallpaper")"

}


wallpaper_set() {

    local wallpaper="$1"

    if [[ -z "$wallpaper" ]]; then
        log_error "No wallpaper specified."
        echo
        echo "Usage:"
        echo "    theme wallpaper set <wallpaper>"
        return 1
    fi

    local fullpath="$WALLPAPER_DIR/$wallpaper"

    if [[ ! -f "$fullpath" ]]; then
        log_error "Wallpaper not found:"
        echo "    $wallpaper"
        return 1
    fi

    echo "$fullpath" > "$STATE_DIR/current_wallpaper"

    wallpaper_reload "$fullpath"

    log_success "Wallpaper updated."

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
