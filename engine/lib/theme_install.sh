#!/usr/bin/env bash

# ==========================================================
# Theme Pack Installation
# ==========================================================

theme_install_repo_validate() {
    local repository="$1"

    [[ "$repository" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
        return 1

    [[ "$repository" != *..* ]]
}

theme_install_root_file_validate() {
    local file="$1"

    [[ -f "$file" && ! -L "$file" ]]
}

theme_install() {
    if [[ "$#" -ne 2 ]]; then
        log_error "Usage: theme install <owner/repo>"
        return 1
    fi

    local repository="$2"
    local staging_dir=""
    local repository_dir=""
    local manifest=""
    local definition=""
    local theme_id=""
    local theme_dir=""
    local destination_created=false

    if ! theme_install_repo_validate "$repository"; then
        log_error "Invalid GitHub repository reference: $repository"
        return 1
    fi

    if ! cmd_exists git; then
        log_error "Required command not found: git"
        return 1
    fi

    if ! staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/xcalibur-theme-install.XXXXXX")"; then
        log_error "Unable to create temporary staging directory."
        return 1
    fi

    repository_dir="$staging_dir/repository"
    manifest="$repository_dir/theme.conf"
    definition="$repository_dir/palette.conf"

    if ! GIT_TERMINAL_PROMPT=0 git clone \
        --depth 1 \
        --no-recurse-submodules \
        --quiet \
        "https://github.com/$repository.git" \
        "$repository_dir"; then
        rm -rf -- "$staging_dir"
        log_error "Unable to retrieve GitHub repository: $repository"
        return 1
    fi

    if ! theme_install_root_file_validate "$manifest"; then
        rm -rf -- "$staging_dir"
        log_error "Repository is missing a regular, non-symlink theme.conf at its root."
        return 1
    fi

    if ! theme_install_root_file_validate "$definition"; then
        rm -rf -- "$staging_dir"
        log_error "Repository is missing a regular, non-symlink palette.conf at its root."
        return 1
    fi

    if ! theme_manifest_load "$manifest" ""; then
        rm -rf -- "$staging_dir"
        log_error "Invalid theme manifest: $THEME_MANIFEST_ERROR"
        return 1
    fi

    theme_id="$THEME_ID"

    if ! theme_id_validate "$theme_id"; then
        rm -rf -- "$staging_dir"
        log_error "Invalid theme ID: $theme_id"
        return 1
    fi

    if ! theme_definition_load "$definition" ""; then
        rm -rf -- "$staging_dir"
        log_error "Invalid theme palette definition: $THEME_DEFINITION_ERROR"
        return 1
    fi

    theme_dir="$THEMES_DIR/$theme_id"

    if [[ -e "$theme_dir" || -L "$theme_dir" ]]; then
        rm -rf -- "$staging_dir"
        log_error "Theme '$theme_id' is already installed."
        return 1
    fi

    if ! mkdir -p "$theme_dir"; then
        rm -rf -- "$staging_dir"
        log_error "Unable to create theme directory: $theme_dir"
        return 1
    fi
    destination_created=true

    if ! cp -- "$manifest" "$theme_dir/theme.conf" ||
       ! cp -- "$definition" "$theme_dir/palette.conf"; then
        if [[ "$destination_created" == true ]]; then
            rm -rf -- "$theme_dir"
        fi
        rm -rf -- "$staging_dir"
        log_error "Unable to install theme '$theme_id'."
        return 1
    fi

    if ! theme_install_root_file_validate "$theme_dir/theme.conf" ||
       ! theme_install_root_file_validate "$theme_dir/palette.conf" ||
       ! theme_manifest_load "$theme_dir/theme.conf" "$theme_id" ||
       ! theme_definition_load "$theme_dir/palette.conf" "$theme_id"; then
        if [[ "$destination_created" == true ]]; then
            rm -rf -- "$theme_dir"
        fi
        rm -rf -- "$staging_dir"
        log_error "Installed theme '$theme_id' failed verification."
        return 1
    fi

    rm -rf -- "$staging_dir"
    log_success "Theme installed: $theme_id"
}
