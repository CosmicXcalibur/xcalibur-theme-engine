#!/usr/bin/env bash

# Installed packs have one directory and exactly the two native data files.
# Keep this check shared by management commands and post-install verification.
THEME_PACK_ERROR=""
THEME_ACTIVE_ERROR=""
THEME_ACTIVE_ID=""

theme_pack_fail() {
    THEME_PACK_ERROR="$1"
    return 1
}

theme_library_check() {
    if [[ ! -d "$THEMES_DIR" || -L "$THEMES_DIR" ]]; then
        theme_pack_fail "theme library is missing or is not a real directory: $THEMES_DIR"
        return 1
    fi
}

theme_pack_validate() {
    local theme_id="$1"
    local theme_dir="$THEMES_DIR/$theme_id"
    local entry name

    THEME_PACK_ERROR=""
    if ! theme_id_validate "$theme_id"; then
        theme_pack_fail "invalid theme ID"
        return 1
    fi
    theme_library_check || return 1
    if [[ -L "$theme_dir" ]]; then
        theme_pack_fail "theme directory is a symlink: $theme_dir"
        return 1
    fi
    if [[ ! -e "$theme_dir" ]]; then
        theme_pack_fail "theme '$theme_id' is not installed"
        return 1
    fi
    if [[ ! -d "$theme_dir" ]]; then
        theme_pack_fail "theme path is not a directory: $theme_dir"
        return 1
    fi

    for name in theme.conf palette.conf; do
        if [[ -L "$theme_dir/$name" || ! -f "$theme_dir/$name" || ! -r "$theme_dir/$name" ]]; then
            theme_pack_fail "$theme_dir/$name is missing or is not a readable regular, non-symlink file"
            return 1
        fi
    done

    for entry in "$theme_dir"/* "$theme_dir"/.[!.]* "$theme_dir"/..?*; do
        [[ -e "$entry" || -L "$entry" ]] || continue
        name="${entry##*/}"
        case "$name" in
            theme.conf|palette.conf) ;;
            *) theme_pack_fail "unexpected entry in theme pack: $entry"; return 1 ;;
        esac
    done

    if ! theme_manifest_load "$theme_dir/theme.conf" "$theme_id"; then
        theme_pack_fail "$theme_dir/theme.conf: $THEME_MANIFEST_ERROR"
        return 1
    fi
    if ! theme_definition_load "$theme_dir/palette.conf" "$theme_id"; then
        theme_pack_fail "$theme_dir/palette.conf: $THEME_DEFINITION_ERROR"
        return 1
    fi
}

# A missing, malformed, or symlinked state file is not evidence that a pack is
# inactive. Destructive commands must fail closed in all three cases.
theme_active_id_read() {
    local -a lines=()
    local state_size last_byte
    THEME_ACTIVE_ERROR=""
    THEME_ACTIVE_ID=""
    if [[ -L "$CURRENT_THEME_FILE" || ! -f "$CURRENT_THEME_FILE" || ! -r "$CURRENT_THEME_FILE" ]]; then
        THEME_ACTIVE_ERROR="current theme state is missing or is not a readable regular, non-symlink file: $CURRENT_THEME_FILE"
        return 1
    fi
    if ! state_size="$(stat -c %s -- "$CURRENT_THEME_FILE")" ||
       [[ ! "$state_size" =~ ^[0-9]+$ || "$state_size" -gt 256 ]]; then
        THEME_ACTIVE_ERROR="current theme state is malformed or too large: $CURRENT_THEME_FILE"
        return 1
    fi
    if ! mapfile -t lines < "$CURRENT_THEME_FILE"; then
        THEME_ACTIVE_ERROR="unable to read current theme state: $CURRENT_THEME_FILE"
        return 1
    fi
    if [[ "${#lines[@]}" -ne 1 ]] || ! theme_id_validate "${lines[0]:-}"; then
        THEME_ACTIVE_ERROR="current theme state contains an invalid theme ID: $CURRENT_THEME_FILE"
        return 1
    fi
    # Bash read ignores NUL bytes. Compare the actual byte count and require
    # any final extra byte to be the newline written by theme_set.
    if [[ "$state_size" -ne "${#lines[0]}" ]]; then
        if [[ "$state_size" -ne "$((${#lines[0]} + 1))" ]] ||
           ! last_byte="$(tail -c 1 -- "$CURRENT_THEME_FILE" | od -An -tu1)" ||
           [[ "$last_byte" -ne 10 ]]; then
            THEME_ACTIVE_ERROR="current theme state contains unexpected bytes: $CURRENT_THEME_FILE"
            return 1
        fi
    fi
    THEME_ACTIVE_ID="${lines[0]}"
}

# Printable ASCII data stays readable; other bytes are shell escaped so
# repository supplied text cannot control a terminal or hide an output row.
theme_display_value() {
    local value="$1" LC_ALL=C
    if [[ "$value" =~ ^[[:print:]]*$ ]]; then
        printf '%s' "$value"
    else
        printf '%q' "$value"
    fi
}
