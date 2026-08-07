#!/usr/bin/env bash

command_status() {

    show_banner

    log_info "Configuration"
    echo "  $HOME/.config/theme"

    echo

    log_info "Current Time"
    echo "  $(util_timestamp)"
}
