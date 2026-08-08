#!/usr/bin/env bash

# ==========================================================
# Theme Render Command
# ==========================================================

command_render() {

    local module="$1"

    if [[ -z "$module" ]]; then
        echo "Usage:"
        echo "    theme render <module>"
        return 1
    fi

    local fn="${module}_render"

    if declare -F "$fn" >/dev/null; then
        "$fn"
    else
        log_error "Unknown module: $module"
        echo
        echo "No render function found:"
        echo "    $fn"
        return 1
    fi

}
