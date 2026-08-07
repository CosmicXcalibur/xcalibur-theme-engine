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

    log_warn "Not implemented yet."

}

wallpaper_set() {

    log_warn "Not implemented yet."

}
