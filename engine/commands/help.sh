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
    set <theme-id>
    install <owner/repo>
    install catppuccin/palette --format catppuccin --variant <latte|frappe|macchiato|mocha>
    install rose-pine/rose-pine-palette --format rose-pine --variant <main|moon|dawn>
    install nordtheme/nord --format nord

Examples:
    theme install catppuccin/palette --format catppuccin --variant mocha
    theme install rose-pine/rose-pine-palette --format rose-pine --variant moon
    theme install nordtheme/nord --format nord
EOF

}
