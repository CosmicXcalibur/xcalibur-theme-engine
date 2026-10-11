#!/usr/bin/env bash

command_import() (
    if [[ "$#" != 2 || "$1" != analyze ]]; then
        log_error "Usage: theme import analyze <owner/repo|github-url>"
        return 1
    fi
    local repository="$2" staging="" revision
    repository="${repository#https://github.com/}"
    repository="${repository%/}"
    repository="${repository%.git}"
    if ! theme_install_repo_validate "$repository"; then
        log_error "Invalid GitHub repository reference: $2"
        return 1
    fi
    if ! cmd_exists git || ! cmd_exists python3 || ! cmd_exists timeout; then
        log_error "Import analysis requires git, python3, and timeout."
        return 1
    fi
    import_cleanup() {
        local result=$?
        trap - EXIT
        if [[ -n "$staging" ]] && ! rm -rf -- "$staging"; then
            log_error "Unable to remove import staging directory: $staging"
            result=1
        fi
        exit "$result"
    }
    trap 'import_cleanup' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    staging="$(mktemp -d "${TMPDIR:-/tmp}/xcalibur-import.XXXXXX")" || {
        log_error "Unable to create import staging directory."
        return 1
    }
    if ! GIT_TERMINAL_PROMPT=0 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
        timeout 60s git -c init.templateDir=/dev/null -c core.hooksPath=/dev/null \
        -c protocol.file.allow=never clone \
        --depth 1 --no-recurse-submodules --quiet \
        "https://github.com/$repository.git" "$staging/repository"; then
        log_error "Unable to retrieve GitHub repository: $repository"
        return 1
    fi
    revision="$(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
        git -c init.templateDir=/dev/null -c core.hooksPath=/dev/null \
        -c protocol.file.allow=never -C "$staging/repository" \
        rev-parse --verify HEAD)" || {
        log_error "Unable to identify repository revision: $repository"
        return 1
    }
    if [[ ! "$revision" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]]; then
        log_error "Repository returned an invalid revision: $repository"
        return 1
    fi
    if ! python3 "$ENGINE_DIR/importer/analyze.py" "$staging/repository" "$repository" "$revision"; then
        log_error "Unable to analyze GitHub repository: $repository"
        return 1
    fi
)
