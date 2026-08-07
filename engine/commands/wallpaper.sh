#!/usr/bin/env bash

command_wallpaper() {

    case "${1:-help}" in

        help)
            wallpaper_help
            ;;

        current)
            wallpaper_current
            ;;

        list)
            wallpaper_list
            ;;

        random)
            wallpaper_random
            ;;

        set)
            shift
            wallpaper_set "$@"
            ;;

        *)
            wallpaper_help
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
