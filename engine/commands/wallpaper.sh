#!/usr/bin/env bash

command_wallpaper() {

    case "${1:-help}" in

        help)
            [[ "$#" -le 1 ]] || { log_error "Usage: theme wallpaper help"; return 2; }
            wallpaper_help
            ;;

        current)
            [[ "$#" -eq 1 ]] || { log_error "Usage: theme wallpaper current"; return 2; }
            wallpaper_current
            ;;

        list)
            [[ "$#" -eq 1 ]] || { log_error "Usage: theme wallpaper list"; return 2; }
            wallpaper_list
            ;;

        random)
            [[ "$#" -eq 1 ]] || { log_error "Usage: theme wallpaper random"; return 2; }
            wallpaper_random
            ;;

        set)
            shift
            wallpaper_set "$@"
            ;;

        *)
            log_error "Unknown wallpaper command: ${1:-}"
            wallpaper_help
            return 2
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
