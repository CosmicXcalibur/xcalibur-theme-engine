#!/usr/bin/env bash

command_wallpaper() {

    case "${1:-help}" in

        help)
            wallpaper_help
            ;;

        current)
            [[ "$#" -eq 1 ]] || { log_error "Usage: theme wallpaper current"; return 1; }
            wallpaper_current
            ;;

        list)
            [[ "$#" -eq 1 ]] || { log_error "Usage: theme wallpaper list"; return 1; }
            wallpaper_list
            ;;

        random)
            [[ "$#" -eq 1 ]] || { log_error "Usage: theme wallpaper random"; return 1; }
            wallpaper_random
            ;;

        set)
            shift
            wallpaper_set "$@"
            ;;

        *)
            log_error "Unknown wallpaper command: ${1:-}"
            wallpaper_help
            return 1
            ;;
    esac

}

wallpaper_help() {

cat <<EOF

Wallpaper Commands

Usage:
    theme wallpaper <command>

Commands:
    list                List all wallpapers
    current             Show current wallpaper
    random              Set a random wallpaper
    set <file>          Set a wallpaper

Examples:
    theme wallpaper list
    theme wallpaper current
    theme wallpaper random
    theme wallpaper set wallpaper.jpg

EOF

}
