#!/usr/bin/env bash

command_doctor() {
    show_banner
    local missing=0 cmd
    log_info "Required for wallpaper and palette workflow:"
    for cmd in cwal hyprctl timeout; do
        if cmd_exists "$cmd"; then
            log_success "$cmd"
        else
            log_error "$cmd is missing; install it before using wallpaper set."
            missing=1
        fi
    done
    echo
    log_info "Optional features and application reload tools:"
    for cmd in git python3 kitty waybar wofi swaync-client; do
        if cmd_exists "$cmd"; then
            log_success "$cmd"
        else
            log_warn "$cmd is unavailable; its related import or application feature will be limited."
        fi
    done
    if [[ "$missing" -ne 0 ]]; then
        log_error "Install the missing required programs and rerun theme doctor."
        return 1
    fi
    log_success "Required workflow commands are available."
}
