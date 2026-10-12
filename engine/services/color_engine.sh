#!/usr/bin/env bash

# ==========================================================
# Xcalibur Color Engine
# ==========================================================

CWAL_COLORS="$HOME/.cache/cwal/colors.sh"
RUNTIME_COLORS="$GENERATED_DIR/colors.sh"

color_wallpaper_path_validate() {
    local wallpaper="$1"
    [[ "$wallpaper" == /* && -f "$wallpaper" && ! -L "$wallpaper" &&
       "$wallpaper" != *'"'* && "$wallpaper" != *'\'* &&
       "$wallpaper" != *'$'* && "$wallpaper" != *'`'* &&
       "$wallpaper" != *$'\n'* && "$wallpaper" != *$'\r'* ]]
}

color_resolve_theme_value() {

    local value="$1"

    case "$value" in
        COLOR0) printf '%s\n' "$color0" ;;
        COLOR1) printf '%s\n' "$color1" ;;
        COLOR2) printf '%s\n' "$color2" ;;
        COLOR3) printf '%s\n' "$color3" ;;
        COLOR4) printf '%s\n' "$color4" ;;
        COLOR5) printf '%s\n' "$color5" ;;
        COLOR6) printf '%s\n' "$color6" ;;
        COLOR7) printf '%s\n' "$color7" ;;
        COLOR8) printf '%s\n' "$color8" ;;
        COLOR9) printf '%s\n' "$color9" ;;
        COLOR10) printf '%s\n' "$color10" ;;
        COLOR11) printf '%s\n' "$color11" ;;
        COLOR12) printf '%s\n' "$color12" ;;
        COLOR13) printf '%s\n' "$color13" ;;
        COLOR14) printf '%s\n' "$color14" ;;
        COLOR15) printf '%s\n' "$color15" ;;
        *) printf '%s\n' "$value" ;;
    esac
}

color_apply_selected_theme_overlay() {
    local theme_id="${1-__current__}"
    local role
    local resolved

    if [[ "$theme_id" == __current__ ]]; then
        [[ -e "$CURRENT_THEME_FILE" || -L "$CURRENT_THEME_FILE" ]] || return 0
        if ! theme_active_id_read; then
            log_error "$(theme_display_value "$THEME_ACTIVE_ERROR")"
            return 1
        fi
        theme_id="$THEME_ACTIVE_ID"
    fi
    [[ -n "$theme_id" ]] || return 0

    if ! theme_pack_validate "$theme_id"; then
        log_error "Selected theme '$theme_id' is invalid: $(theme_display_value "$THEME_PACK_ERROR")"
        return 1
    fi

    log_info "Applying theme palette: $theme_id"

    for role in "${THEME_DEFINITION_ROLES[@]}"; do
        [[ -v "THEME_DEFINITION_VALUES[$role]" ]] || continue

        resolved="$(color_resolve_theme_value "${THEME_DEFINITION_VALUES[$role]}")"

        case "$role" in
            BACKGROUND) final_background="$resolved" ;;
            FOREGROUND) final_foreground="$resolved" ;;
            CURSOR) final_cursor="$resolved" ;;
            PRIMARY) final_primary="$resolved" ;;
            SECONDARY) final_secondary="$resolved" ;;
            ACCENT) final_accent="$resolved" ;;
            SUCCESS) final_success="$resolved" ;;
            WARNING) final_warning="$resolved" ;;
            ERROR) final_error="$resolved" ;;
            MUTED) final_muted="$resolved" ;;
            SURFACE) final_surface="$resolved" ;;
            SURFACE_ALT) final_surface_alt="$resolved" ;;
            BORDER) final_border="$resolved" ;;
            SELECTION) final_selection="$resolved" ;;
            HIGHLIGHT) final_highlight="$resolved" ;;
        esac
    done
}

# ----------------------------------------------------------
# Generate palette using cwal
# ----------------------------------------------------------

color_generate() {

    log_info "Generating color palette..."

    local wallpaper="${1:-}"
    local selected_theme="${2-__current__}"
    local cwal_output_dir="${3:-}"
    local cwal_file="$CWAL_COLORS"

    if [[ -z "$wallpaper" ]]; then
        if [[ -L "$STATE_DIR/current_wallpaper" || ! -f "$STATE_DIR/current_wallpaper" ]]; then
            log_error "No valid current wallpaper state."
            return 1
        fi
        wallpaper="$(< "$STATE_DIR/current_wallpaper")"
    fi

    if ! color_wallpaper_path_validate "$wallpaper"; then
        log_error "Wallpaper path is missing or cannot be represented safely in the palette."
        return 1
    fi

    local -a cwal_command=(cwal --img "$wallpaper" --no-reload)
    if [[ -n "$cwal_output_dir" ]]; then
        mkdir -p -- "$cwal_output_dir" || return 1
        cwal_command+=(--out-dir "$cwal_output_dir")
        cwal_file="$cwal_output_dir/colors.sh"
    fi
    if ! "${cwal_command[@]}"; then
        log_error "Unable to generate cwal palette."
        return 1
    fi

    if ! color_export "$cwal_file" "$wallpaper" "$selected_theme"; then
        return 1
    fi

    log_success "Palette generated."
}

# ----------------------------------------------------------
# Export runtime palette
# ----------------------------------------------------------

color_export() {
    local cwal_file="${1:-$CWAL_COLORS}"
    local wallpaper="${2:-}"
    local selected_theme="${3-__current__}"
    local line key value required
    local background foreground cursor
    local color0 color1 color2 color3 color4 color5 color6 color7
    local color8 color9 color10 color11 color12 color13 color14 color15
    local -A seen=()

    if [[ ! -f "$cwal_file" || -L "$cwal_file" ]]; then
        log_error "cwal palette not found."
        return 1
    fi
    if [[ -z "$wallpaper" ]]; then
        if [[ -L "$STATE_DIR/current_wallpaper" || ! -f "$STATE_DIR/current_wallpaper" ]]; then
            log_error "No valid current wallpaper state."
            return 1
        fi
        wallpaper="$(< "$STATE_DIR/current_wallpaper")"
    fi

    if ! mkdir -p -- "$GENERATED_DIR"; then
        log_error "Unable to create generated palette directory: $GENERATED_DIR"
        return 1
    fi

    # cwal's colors.sh also contains shell exports. Read only the required
    # literal color assignments; no generated shell file is executed.
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^([a-z][a-z0-9]*)= ]]; then
            key="${BASH_REMATCH[1]}"
            case "$key" in
                background|foreground|cursor|color[0-9]|color1[0-5])
                    if [[ ! "$line" =~ ^[a-z][a-z0-9]*=\'(#[0-9A-Fa-f]{6})\'$ || -v "seen[$key]" ]]; then
                        log_error "Invalid or duplicate cwal color: $key"
                        return 1
                    fi
                    value="${BASH_REMATCH[1]}"
                    printf -v "$key" '%s' "$value"
                    seen["$key"]=1
                    ;;
            esac
        fi
    done < "$cwal_file"
    for required in background foreground cursor color{0..15}; do
        if [[ ! -v "seen[$required]" ]]; then
            log_error "Missing cwal color: $required"
            return 1
        fi
    done

    # Preserve the existing CWAL semantic defaults unless a selected pack
    # declares a validated override for a specific semantic role.
    local final_background="$background"
    local final_foreground="$foreground"
    local final_cursor="$cursor"
    local final_primary="$color4"
    local final_secondary="$color5"
    local final_accent="$color6"
    local final_success="$color2"
    local final_warning="$color3"
    local final_error="$color1"
    local final_muted="$color7"
    local final_surface="$color2"
    local final_surface_alt="$color3"
    local final_border="$color4"
    local final_selection="$color5"
    local final_highlight="$color6"

    if ! color_apply_selected_theme_overlay "$selected_theme"; then
        return 1
    fi

    if ! cat > "$RUNTIME_COLORS" <<EOF
#!/usr/bin/env bash

# ==========================================================
# Xcalibur Runtime Palette
# Auto-generated. Do not edit.
# ==========================================================

WALLPAPER="$wallpaper"

# ----------------------------------------------------------
# Base colors
# ----------------------------------------------------------

BACKGROUND="$final_background"
FOREGROUND="$final_foreground"
CURSOR="$final_cursor"

# ----------------------------------------------------------
# Raw CWAL ANSI palette
# ----------------------------------------------------------

COLOR0="$color0"
COLOR1="$color1"
COLOR2="$color2"
COLOR3="$color3"
COLOR4="$color4"
COLOR5="$color5"
COLOR6="$color6"
COLOR7="$color7"
COLOR8="$color8"
COLOR9="$color9"
COLOR10="$color10"
COLOR11="$color11"
COLOR12="$color12"
COLOR13="$color13"
COLOR14="$color14"
COLOR15="$color15"

# ----------------------------------------------------------
# Semantic theme palette
#
# Application modules should use these semantic roles
# instead of depending directly on COLOR0-COLOR15.
# ----------------------------------------------------------

PRIMARY="$final_primary"
SECONDARY="$final_secondary"
ACCENT="$final_accent"

SUCCESS="$final_success"
WARNING="$final_warning"
ERROR="$final_error"

MUTED="$final_muted"
SURFACE="$final_surface"
SURFACE_ALT="$final_surface_alt"
BORDER="$final_border"
SELECTION="$final_selection"
HIGHLIGHT="$final_highlight"

EOF
    then
        log_error "Unable to write runtime palette: $RUNTIME_COLORS"
        return 1
    fi

    log_success "Runtime palette updated."
}
