#!/usr/bin/env bash

# ==========================================================
# Theme Pack Installation
# ==========================================================

theme_install_repo_validate() {
    local repository="$1"

    [[ "$repository" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9][A-Za-z0-9._-]{0,99}$ ]] ||
        return 1

    [[ "$repository" != *..* ]]
}

theme_install_root_file_validate() {
    local file="$1"

    [[ -f "$file" && ! -L "$file" ]] &&
        [[ "$(stat -c %s -- "$file")" -le 262144 ]]
}

# Install only validated root data files from a local, reviewable pack.
theme_install_from_directory() (
    local source_dir="$1" theme_id theme_dir=""
    [[ "$source_dir" != ./* ]] || source_dir="${source_dir#./}"
    [[ "$source_dir" == /* ]] || source_dir="$PWD/$source_dir"
    if ! fs_directory_safe "$source_dir" false ||
       ! theme_install_root_file_validate "$source_dir/theme.conf" ||
       ! theme_install_root_file_validate "$source_dir/palette.conf"; then
        log_error "Pack must have a safe directory and regular theme.conf and palette.conf files."
        return 1
    fi
    if ! theme_manifest_load "$source_dir/theme.conf" ""; then
        log_error "Invalid theme manifest: $THEME_MANIFEST_ERROR"
        return 1
    fi
    theme_id="$THEME_ID"
    if ! theme_definition_load "$source_dir/palette.conf" ""; then
        log_error "Invalid theme palette: $THEME_DEFINITION_ERROR"
        return 1
    fi
    if [[ -e "$source_dir/source.json" || -L "$source_dir/source.json" ]]; then
        if ! theme_install_root_file_validate "$source_dir/source.json" ||
           ! cmd_exists python3 ||
           ! python3 "$ENGINE_DIR/importer/convert.py" validate-metadata "$source_dir/source.json" "$theme_id"; then
            log_error "Invalid or unsafe source metadata: $source_dir/source.json"
            return 1
        fi
    fi
    theme_dir="$THEMES_DIR/$theme_id"
    if [[ "$THEMES_DIR" != "$THEME_ROOT/themes" ]] ||
       ! fs_directory_safe "$THEMES_DIR" true; then
        log_error "Unsafe themes directory: $THEMES_DIR"
        return 1
    fi
    if [[ -e "$theme_dir" || -L "$theme_dir" ]]; then
        log_error "Theme '$theme_id' is already installed."
        return 1
    fi
    if ! cmd_exists python3 ||
       ! python3 "$ENGINE_DIR/importer/convert.py" install-pack \
           "$source_dir" "$theme_dir" "$theme_id"; then
        log_error "Unable to install validated theme '$theme_id'."
        return 1
    fi
    log_success "Theme installed: $theme_id"
)

theme_install() {
    if [[ "$#" -ne 2 && "$#" -ne 4 ]] ||
       { [[ "$#" -eq 4 ]] && [[ "$3" != --theme ]]; }; then
        log_error "Usage: theme install <owner/repo[@commit-sha]> [--theme <relative-file>]"
        return 2
    fi
    # The import command owns retrieval and conversion. This public command
    # requests installation of its validated result without applying a theme.
    command_import_source install-source "${@:2}"
}
