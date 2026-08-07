#!/usr/bin/env bash

command_doctor() {

    show_banner

    log_info "Checking required programs..."

    local missing=0

    for cmd in \
        cwal \
        hyprctl \
        hyprpaper \
        kitty \
        waybar \
        wofi \
        swaync
    do
        if cmd_exists "$cmd"; then
            log_success "$cmd"
        else
            log_error "$cmd"
            missing=1
        fi
    done

    echo

    if [[ "$missing" -eq 0 ]]; then
        log_success "System looks good."
    else
        log_warn "Some dependencies are missing."
    fi
}
