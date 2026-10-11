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

    [[ -f "$file" && ! -L "$file" ]] &&
        [[ "$(stat -c %s -- "$file")" -le 262144 ]]
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

# Install only validated root data files from a local, reviewable pack.
theme_install_from_directory() (
    local source_dir="$1" theme_id theme_dir="" destination_created=false complete=false
    theme_install_local_cleanup() {
        local result=$?
        trap - EXIT
        if [[ "$destination_created" == true && "$complete" != true ]]; then
            theme_install_rollback "$theme_dir" || result=1
        fi
        exit "$result"
    }
    trap 'theme_install_local_cleanup' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
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
    if ! mkdir -m 700 -- "$theme_dir"; then
        log_error "Unable to claim theme directory: $theme_dir"
        return 1
    fi
    destination_created=true
    if ! cp -- "$source_dir/theme.conf" "$theme_dir/theme.conf" ||
       ! cp -- "$source_dir/palette.conf" "$theme_dir/palette.conf" ||
       ! theme_manifest_load "$theme_dir/theme.conf" "$theme_id" ||
       ! theme_definition_load "$theme_dir/palette.conf" "$theme_id"; then
        log_error "Unable to install validated theme '$theme_id'."
        return 1
    fi
    complete=true
    log_success "Theme installed: $theme_id"
)

theme_install() (
    if [[ "$#" -ne 2 ]]; then
        log_error "Usage: theme install <owner/repo>"
        return 2
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
        return 2
    fi

    if ! cmd_exists git || ! cmd_exists timeout; then
        log_error "Native installation requires git and timeout."
        return 1
    fi

    fs_directory_safe "${TMPDIR:-/tmp}" false || {
        log_error "Unsafe temporary directory: ${TMPDIR:-/tmp}"
        return 1
    }

    if ! staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/xcalibur-theme-install.XXXXXX")"; then
        log_error "Unable to create temporary staging directory."
        return 1
    fi
    theme_install_cleanup() {
        local result=$?
        trap - EXIT
        if ! rm -rf -- "$staging_dir"; then
            log_error "Unable to remove native installation staging directory: $staging_dir"
            result=1
        fi
        exit "$result"
    }
    trap 'theme_install_cleanup' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    repository_dir="$staging_dir/repository"
    manifest="$repository_dir/theme.conf"
    definition="$repository_dir/palette.conf"

    if ! GIT_TERMINAL_PROMPT=0 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
        GIT_PROTOCOL_FROM_USER=0 GIT_LFS_SKIP_SMUDGE=1 \
        timeout 60s git -c init.templateDir=/dev/null -c core.hooksPath=/dev/null \
        -c protocol.file.allow=never clone \
        --depth 1 \
        --no-recurse-submodules \
        --quiet \
        "https://github.com/$repository.git" \
        "$repository_dir"; then
        log_error "Unable to retrieve GitHub repository: $repository"
        return 1
    fi

    if ! theme_install_from_directory "$repository_dir"; then
        return 1
    fi
)
