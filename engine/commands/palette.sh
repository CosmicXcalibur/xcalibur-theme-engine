#!/usr/bin/env bash

command_palette() {

    case "${1:-help}" in

        generate)
            [[ "$#" -eq 1 ]] || { log_error "Usage: theme palette generate"; return 1; }
            color_generate
            ;;

        help)

            palette_help
            ;;

        *)
            log_error "Unknown palette command: ${1:-}"
            palette_help
            return 1
            ;;

    esac

}

palette_help() {

cat <<EOF

Palette Commands

Usage:
    theme palette <command>

Commands:
    generate      Generate palette from current wallpaper

Examples:
    theme palette generate

EOF

}
