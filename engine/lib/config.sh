#!/usr/bin/env bash

# ==========================================================
# Theme Engine Configuration Loader
# ==========================================================

CONFIG_DIR="$THEME_ROOT/config"

load_config() {
    local file line key value
    local -A seen=()
    fs_directory_safe "$CONFIG_DIR" false || die "Unsafe configuration directory: $CONFIG_DIR"

    for file in \
        "$CONFIG_DIR/theme.conf" \
        "$CONFIG_DIR/paths.conf" \
        "$CONFIG_DIR/applications.conf"
    do

        if [[ ! -f "$file" || -L "$file" ]]; then
            die "Missing or unsafe configuration file: $file"
        fi

        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -z "$line" || "$line" == \#* ]] && continue
            [[ "$line" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]] || die "Invalid configuration line in $file"
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            [[ ! -v "seen[$key]" ]] || die "Duplicate configuration key: $key"
            seen["$key"]=1
            if [[ "$value" == \"*\" ]]; then
                value="${value:1:${#value}-2}"
            elif [[ "$value" == *'"'* ]]; then
                die "Malformed quoted configuration value: $key"
            fi
            [[ ! "$value" =~ [[:cntrl:]] && "$value" != *'`'* ]] || die "Invalid configuration value: $key"
            case "$key" in
                THEME_VERSION|THEME_NAME)
                    [[ -n "$value" && "$value" != *'$'* ]] || die "Invalid setting: $key"
                    ;;
                COLOR_ENGINE)
                    [[ "$value" == cwal ]] || die "Unsupported color engine: $value"
                    ;;
                WALLPAPER_BACKEND)
                    [[ "$value" == hyprpaper ]] || die "Unsupported wallpaper backend: $value"
                    ;;
                DEBUG|VERBOSE|KITTY_ENABLED|WAYBAR_ENABLED|WOFI_ENABLED|SWAYNC_ENABLED|HYPRLOCK_ENABLED|GTK_ENABLED|QT_ENABLED)
                    [[ "$value" == true || "$value" == false ]] || die "Invalid boolean setting: $key"
                    ;;
                ENGINE_DIR|MODULES_DIR|RUNTIME_DIR|CONFIG_DIR|ASSETS_DIR|WALLPAPER_DIR|GENERATED_DIR|CACHE_DIR|STATE_DIR|LOG_DIR|THEMES_DIR|CURRENT_THEME_FILE)
                    value="${value//\$THEME_ROOT/$THEME_ROOT}"
                    value="${value//\$HOME/$HOME}"
                    value="${value//\$RUNTIME_DIR/${RUNTIME_DIR:-}}"
                    value="${value//\$STATE_DIR/${STATE_DIR:-}}"
                    [[ "$value" == /* && "$value" != *'$'* ]] || die "Invalid path setting: $key"
                    ;;
                *) die "Unknown configuration key: $key" ;;
            esac
            printf -v "$key" '%s' "$value"
        done < "$file"

    done

    [[ "$ENGINE_DIR" == "$THEME_ROOT/engine" &&
       "$MODULES_DIR" == "$THEME_ROOT/modules" &&
       "$CONFIG_DIR" == "$THEME_ROOT/config" &&
       "$THEMES_DIR" == "$THEME_ROOT/themes" ]] || die "Core engine paths cannot leave the checkout."
}
