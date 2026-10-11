#!/usr/bin/env bash

# ==========================================================
# Xcalibur Color Engine
# ==========================================================

CWAL_COLORS="$HOME/.cache/cwal/colors.sh"
RUNTIME_COLORS="$GENERATED_DIR/colors.sh"

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

    [[ -f "$CURRENT_THEME_FILE" ]] || return 0

    local theme_id
    local theme_dir
    local role
    local resolved

    theme_id="$(< "$CURRENT_THEME_FILE")"

    [[ -n "$theme_id" ]] || return 0

    if ! theme_id_validate "$theme_id"; then
        log_error "Selected theme ID is invalid."
        return 1
    fi

    theme_dir="$THEMES_DIR/$theme_id"

    if [[ -L "$theme_dir" ]] ||
       ! theme_install_root_file_validate "$theme_dir/theme.conf" ||
       ! theme_install_root_file_validate "$theme_dir/palette.conf"; then
        log_error "Selected theme '$theme_id' has unsafe or missing files."
        return 1
    fi

    if ! theme_manifest_load "$theme_dir/theme.conf" "$theme_id"; then
        log_error "Selected theme '$theme_id' is invalid: $THEME_MANIFEST_ERROR"
        return 1
    fi

    if ! theme_definition_load "$theme_dir/palette.conf" "$theme_id"; then
        log_error "Selected theme '$theme_id' is invalid: $THEME_DEFINITION_ERROR"
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

    local wallpaper

    if [[ ! -f "$STATE_DIR/current_wallpaper" ]]; then
        log_error "No current wallpaper selected."
        return 1
    fi

    wallpaper="$(< "$STATE_DIR/current_wallpaper")"

    if [[ ! -f "$wallpaper" || ! -r "$wallpaper" || "$wallpaper" =~ [[:cntrl:]] ]]; then
        log_error "Current wallpaper not found."
        return 1
    fi

    if ! cwal --img "$wallpaper" --no-reload; then
        log_error "Unable to generate cwal palette."
        return 1
    fi

    if ! color_export; then
        return 1
    fi

    log_success "Palette generated."
}

# ----------------------------------------------------------
# Export runtime palette
# ----------------------------------------------------------

color_export() {

    if [[ ! -f "$CWAL_COLORS" ]]; then
        log_error "cwal palette not found."
        return 1
    fi

    if ! color_data_read "$CWAL_COLORS" cwal; then
        log_error "CWAL palette is missing required colors or contains invalid colors."
        return 1
    fi

    local background="${COLOR_DATA[background]}"
    local foreground="${COLOR_DATA[foreground]}"
    local cursor="${COLOR_DATA[cursor]}"
    local color0="${COLOR_DATA[color0]}" color1="${COLOR_DATA[color1]}"
    local color2="${COLOR_DATA[color2]}" color3="${COLOR_DATA[color3]}"
    local color4="${COLOR_DATA[color4]}" color5="${COLOR_DATA[color5]}"
    local color6="${COLOR_DATA[color6]}" color7="${COLOR_DATA[color7]}"
    local color8="${COLOR_DATA[color8]}" color9="${COLOR_DATA[color9]}"
    local color10="${COLOR_DATA[color10]}" color11="${COLOR_DATA[color11]}"
    local color12="${COLOR_DATA[color12]}" color13="${COLOR_DATA[color13]}"
    local color14="${COLOR_DATA[color14]}" color15="${COLOR_DATA[color15]}"

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

    if ! color_apply_selected_theme_overlay; then
        return 1
    fi

    fs_directory_safe "$GENERATED_DIR" true || return 1
    local runtime_tmp
    runtime_tmp="$(mktemp "$GENERATED_DIR/.colors.XXXXXX")" || return 1

    cat > "$runtime_tmp" <<EOF
#!/usr/bin/env bash

# ==========================================================
# Xcalibur Runtime Palette
# Auto-generated. Do not edit.
# ==========================================================

WALLPAPER=$(printf '%q' "$wallpaper")

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

    if ! color_data_read "$runtime_tmp" runtime || ! mv -f -- "$runtime_tmp" "$RUNTIME_COLORS"; then
        rm -f -- "$runtime_tmp"
        log_error "Unable to install validated runtime palette."
        return 1
    fi

    log_success "Runtime palette updated."
}
