#!/usr/bin/env bash

command_render() {

    local module="$1"

    if [[ -z "$module" ]]; then
        echo "Usage:"
        echo "    theme render <module>"
        return 1
    fi

    case "$module" in

        kitty)

            kitty_render
            ;;

        waybar)

            waybar_render
            ;;

        *)

            log_error "Unknown module: $module"
            echo
            echo "Available modules:"
            echo "    kitty"
            echo "    waybar"
            return 1
            ;;

    esac

}
