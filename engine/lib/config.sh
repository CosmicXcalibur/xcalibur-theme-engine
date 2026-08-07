#!/usr/bin/env bash

# ==========================================================
# Theme Engine Configuration Loader
# ==========================================================

CONFIG_DIR="$HOME/.config/theme/config"

load_config() {

    local file

    for file in \
        "$CONFIG_DIR/theme.conf" \
        "$CONFIG_DIR/paths.conf" \
        "$CONFIG_DIR/applications.conf"
    do

        if [[ ! -f "$file" ]]; then
            die "Missing configuration file: $file"
        fi

        source "$file"

    done
}
