#!/usr/bin/env bash

# ==========================================================
# Xcalibur Generic Template Renderer
# ==========================================================

# Render engine-owned templates in one pass. Palette and template content are
# treated as data; replacement values are never interpreted as shell or sed.
render_template() {
    local template="$1" output="$2" line remaining rendered key tmp

    [[ -f "$template" && ! -L "$template" ]] || return 1
    fs_directory_safe "$(dirname "$template")" false || return 1
    color_data_read "$RUNTIME_COLORS" runtime || {
        log_error "Runtime palette is invalid."
        return 1
    }
    if [[ -n "${WALLPAPER_CANDIDATE:-}" || -f "$STATE_DIR/current_wallpaper" ]]; then
        local wallpaper_path
        wallpaper_path="${WALLPAPER_CANDIDATE:-}"
        [[ -n "$wallpaper_path" ]] || wallpaper_path="$(< "$STATE_DIR/current_wallpaper")"
        if [[ -f "$wallpaper_path" && -r "$wallpaper_path" && ! "$wallpaper_path" =~ [[:cntrl:]] ]]; then
            COLOR_DATA[WALLPAPER]="$wallpaper_path"
        fi
    fi
    fs_directory_safe "$(dirname "$output")" true || return 1
    tmp="$(mktemp "$(dirname "$output")/.render.XXXXXX")" || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        remaining="$line"
        rendered=""
        while [[ "$remaining" =~ ^(.*)\{\{([A-Z][A-Z0-9_]*)\}\}(.*)$ ]]; do
            key="${BASH_REMATCH[2]}"
            if [[ ! -v "COLOR_DATA[$key]" ]]; then
                log_error "Unknown template variable: $key"
                rm -f -- "$tmp"
                return 1
            fi
            rendered="${COLOR_DATA[$key]}${BASH_REMATCH[3]}$rendered"
            remaining="${BASH_REMATCH[1]}"
        done
        if [[ "$remaining" == *'{{'* || "$remaining" == *'}}'* ]]; then
            log_error "Malformed template placeholder in $template"
            rm -f -- "$tmp"
            return 1
        fi
        printf '%s\n' "$remaining$rendered" >> "$tmp" || {
            rm -f -- "$tmp"
            return 1
        }
    done < "$template"

    if ! mv -f -- "$tmp" "$output"; then
        rm -f -- "$tmp"
        return 1
    fi
}
