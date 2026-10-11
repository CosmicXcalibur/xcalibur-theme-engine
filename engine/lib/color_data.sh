#!/usr/bin/env bash

# CWAL's colors.sh may contain shell commands for unrelated applications.
# Read only the expected color assignments as data.
declare -gA COLOR_DATA=()

color_data_read() {
    local file="$1" format="$2" line key value required
    local -A seen=()
    COLOR_DATA=()
    [[ -f "$file" && ! -L "$file" ]] || return 1
    [[ "$(stat -c %s -- "$file")" -le 1048576 ]] || return 1
    fs_directory_safe "$(dirname "$file")" false || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$format" == cwal ]]; then
            [[ "$line" =~ ^(color([0-9]|1[0-5])|background|foreground|cursor)= ]] || continue
            key="${BASH_REMATCH[1]}"
        else
            [[ -z "$line" || "$line" == \#* || "$line" == WALLPAPER=* ]] && continue
            [[ "$line" =~ ^([A-Z][A-Z0-9_]*)= ]] || return 1
            key="${BASH_REMATCH[1]}"
            [[ "$key" =~ ^COLOR([0-9]|1[0-5])$ || "$key" =~ ^(BACKGROUND|FOREGROUND|CURSOR|PRIMARY|SECONDARY|ACCENT|SUCCESS|WARNING|ERROR|MUTED|SURFACE|SURFACE_ALT|BORDER|SELECTION|HIGHLIGHT)$ ]] || return 1
        fi
        [[ ! -v "seen[$key]" ]] || return 1
        value="${line#*=}"
        if [[ "$value" == \'*\' || "$value" == \"*\" ]]; then
            value="${value:1:${#value}-2}"
        fi
        [[ "$value" =~ ^#[0-9A-Fa-f]{6}$ ]] || return 1
        COLOR_DATA["$key"]="$value"
        seen["$key"]=1
    done < "$file"

    if [[ "$format" == cwal ]]; then
        for required in background foreground cursor color{0..15}; do
            [[ -v "COLOR_DATA[$required]" ]] || return 1
        done
    else
        for required in BACKGROUND FOREGROUND CURSOR PRIMARY SECONDARY ACCENT SUCCESS WARNING ERROR MUTED SURFACE SURFACE_ALT BORDER SELECTION HIGHLIGHT COLOR{0..15}; do
            [[ -v "COLOR_DATA[$required]" ]] || return 1
        done
    fi
}
