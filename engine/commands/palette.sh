#!/usr/bin/env bash

command_palette() {

    case "${1:-help}" in

        generate)

            color_generate
            ;;

        help)

            palette_help
            ;;

        *)

            palette_help
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
