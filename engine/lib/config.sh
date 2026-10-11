#!/usr/bin/env bash

# ==========================================================
# Theme Engine Configuration Loader
# ==========================================================

CONFIG_DIR="$THEME_ROOT/config"

load_config() {

    local file
    fs_directory_safe "$CONFIG_DIR" false || die "Unsafe configuration directory: $CONFIG_DIR"

    for file in \
        "$CONFIG_DIR/theme.conf" \
        "$CONFIG_DIR/paths.conf" \
        "$CONFIG_DIR/applications.conf"
    do

        if [[ ! -f "$file" || -L "$file" ]]; then
            die "Missing or unsafe configuration file: $file"
        fi

        source "$file"

    done
}
