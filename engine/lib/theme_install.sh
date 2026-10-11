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

theme_install_rollback() {
    local theme_dir="$1"
    if ! fs_directory_safe "$THEMES_DIR" false ||
       [[ ! -d "$theme_dir" || -L "$theme_dir" ]]; then
        log_warn "Partial theme directory needs manual cleanup: $theme_dir"
        return 1
    fi
    # Only these two names are created by the installer. Leave an unexpected
    # directory entry untouched rather than recursively removing it.
    if ! rm -f -- "$theme_dir/theme.conf" "$theme_dir/palette.conf" ||
       ! rmdir -- "$theme_dir"; then
        log_warn "Partial theme directory needs manual cleanup: $theme_dir"
        return 1
    fi
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

    if ! GIT_TERMINAL_PROMPT=0 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
        git -c init.templateDir=/dev/null -c core.hooksPath=/dev/null \
        -c protocol.file.allow=never clone \
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

    if [[ "$THEMES_DIR" != "$THEME_ROOT/themes" ]] ||
       ! fs_directory_safe "$THEMES_DIR" true; then
        rm -rf -- "$staging_dir"
        log_error "Unsafe or unwritable themes directory: $THEMES_DIR"
        return 1
    fi

    if [[ -e "$theme_dir" || -L "$theme_dir" ]]; then
        rm -rf -- "$staging_dir"
        log_error "Theme '$theme_id' is already installed."
        return 1
    fi

    # Plain mkdir is exclusive: a concurrent installer cannot claim this ID.
    if ! mkdir -m 700 -- "$theme_dir"; then
        rm -rf -- "$staging_dir"
        log_error "Unable to create theme directory: $theme_dir"
        return 1
    fi
    destination_created=true

    if ! cp -- "$manifest" "$theme_dir/theme.conf" ||
       ! cp -- "$definition" "$theme_dir/palette.conf"; then
        [[ "$destination_created" != true ]] || theme_install_rollback "$theme_dir" || true
        rm -rf -- "$staging_dir"
        log_error "Unable to install theme '$theme_id'."
        return 1
    fi

    if ! theme_install_root_file_validate "$theme_dir/theme.conf" ||
       ! theme_install_root_file_validate "$theme_dir/palette.conf" ||
       ! theme_manifest_load "$theme_dir/theme.conf" "$theme_id" ||
       ! theme_definition_load "$theme_dir/palette.conf" "$theme_id"; then
        [[ "$destination_created" != true ]] || theme_install_rollback "$theme_dir" || true
        rm -rf -- "$staging_dir"
        log_error "Installed theme '$theme_id' failed verification."
        return 1
    fi

    rm -rf -- "$staging_dir"
    log_success "Theme installed: $theme_id"
}
