#!/usr/bin/env bash

# ==========================================================
# Xcalibur Color Engine
# ==========================================================

CWAL_COLORS="$HOME/.cache/cwal/colors.sh"
RUNTIME_COLORS="$GENERATED_DIR/colors.sh"

# ----------------------------------------------------------
# Generate palette using cwal
# ----------------------------------------------------------

color_generate() {

    log_info "Generating color palette..."

    local wallpaper

    wallpaper=$(cat "$STATE_DIR/current_wallpaper")

    if [[ ! -f "$wallpaper" ]]; then
        log_error "Current wallpaper not found."
        return 1
    fi

    cwal --img "$wallpaper" --no-reload

    color_export

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

    mkdir -p "$GENERATED_DIR"

    # Source cwal palette safely
    set +u
    source "$CWAL_COLORS"
    set -u

    cat > "$RUNTIME_COLORS" <<EOF
#!/usr/bin/env bash

# ==========================================================
# Xcalibur Runtime Palette
# Auto-generated. Do not edit.
# ==========================================================

WALLPAPER="$wallpaper"

BACKGROUND="$background"
FOREGROUND="$foreground"
CURSOR="$cursor"

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

PRIMARY="$color4"
SECONDARY="$color5"
ACCENT="$color6"

SUCCESS="$color2"
WARNING="$color3"
ERROR="$color1"

EOF

    log_success "Runtime palette updated."

}
