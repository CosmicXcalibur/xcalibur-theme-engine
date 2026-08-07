#!/usr/bin/env bash

service_wallpaper_current() {

    cat "$STATE_DIR/current_wallpaper"

}

service_wallpaper_list() {

    find "$wallpaper_dir" \
        -maxdepth 1 \
        -type f

}

service_wallpaper_random() {

    log_warn "Not implemented yet."

}

service_wallpaper_set() {

    log_warn "Not implemented yet."

}
