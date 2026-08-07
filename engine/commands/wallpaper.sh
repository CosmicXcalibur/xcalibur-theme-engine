#!/usr/bin/env bash

command_wallpaper() {

    case "${1:-help}" in

        help)
            wallpaper_help
            ;;

        current)
            service_wallpaper_current
            ;;

        list)
            service_wallpaper_list
            ;;

        random)
            service_wallpaper_random
            ;;

        set)
            shift
            service_wallpaper_set "$@"
            ;;

        *)
            wallpaper_help
            ;;
    esac
}

wallpaper_help() {

cat <<EOF

Wallpaper Commands

theme wallpaper current
theme wallpaper list
theme wallpaper random
theme wallpaper set <file>

EOF

}
