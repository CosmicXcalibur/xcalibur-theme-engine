#!/usr/bin/env bash

command_help() {

    show_banner

    cat <<EOF
Usage:
    theme <command>

Commands:
    help
    version
    status
    doctor
    list
    current
    info <theme-id>
    validate <theme-id>
    validate --all
    set <theme-id>
    remove <theme-id>
    recover [--list|transaction-id]
    install <owner/repo>
    install catppuccin/palette --format catppuccin --variant <latte|frappe|macchiato|mocha>
    install rose-pine/rose-pine-palette --format rose-pine --variant <main|moon|dawn>
    install nordtheme/nord --format nord

Examples:
    theme info catppuccin-mocha
    theme validate --all
    theme remove nord
    theme recover --list
    theme install catppuccin/palette --format catppuccin --variant mocha
    theme install rose-pine/rose-pine-palette --format rose-pine --variant moon
    theme install nordtheme/nord --format nord
EOF

}
