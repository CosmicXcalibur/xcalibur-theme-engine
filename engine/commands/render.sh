#!/usr/bin/env bash

command_render() {

    case "${1:-help}" in

        kitty)

            render_template \
                "$MODULES_DIR/kitty/templates/kitty.conf.template" \
                "$GENERATED_DIR/kitty.conf"
            ;;

        *)

            echo "Usage:"
            echo "    theme render kitty"
            ;;
    esac

}
