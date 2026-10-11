#!/usr/bin/env bash

command_import() (
    local mode="${1:-}" repository="${2:-}" output="${3:-}" staging="" revision report_file
    if [[ "$mode" == install ]]; then
        [[ "$#" -eq 2 ]] || { log_error "Usage: theme import install <pack-directory>"; return 2; }
        theme_install_from_directory "$repository"
        return
    fi
    if [[ "$mode" != analyze && "$mode" != preview && "$mode" != convert ]] ||
       { [[ "$mode" == convert && "$#" -ne 3 ]] || [[ "$mode" != convert && "$#" -ne 2 ]]; }; then
        log_error "Usage: theme import analyze|preview <owner/repo|github-url> | convert <owner/repo|github-url> <new-output-directory> | install <pack-directory>"
        return 2
    fi
    repository="${repository#https://github.com/}"
    repository="${repository%/}"
    repository="${repository%.git}"
    if ! theme_install_repo_validate "$repository"; then
        log_error "Invalid GitHub repository reference: $2"
        return 2
    fi
    if ! cmd_exists git || ! cmd_exists python3 || ! cmd_exists timeout; then
        log_error "Import analysis requires git, python3, and timeout."
        return 1
    fi
    fs_directory_safe "${TMPDIR:-/tmp}" false || {
        log_error "Unsafe temporary directory: ${TMPDIR:-/tmp}"
        return 1
    }
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
        GIT_PROTOCOL_FROM_USER=0 GIT_LFS_SKIP_SMUDGE=1 \
        timeout 60s git -c init.templateDir=/dev/null -c core.hooksPath=/dev/null \
        -c protocol.file.allow=never clone \
        --depth 1 --no-recurse-submodules --quiet \
        "https://github.com/$repository.git" "$staging/repository"; then
        log_error "Unable to retrieve GitHub repository: $repository"
        return 1
    fi
    revision="$(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
        GIT_PROTOCOL_FROM_USER=0 timeout 10s git -c init.templateDir=/dev/null -c core.hooksPath=/dev/null \
        -c protocol.file.allow=never -C "$staging/repository" \
        rev-parse --verify HEAD)" || {
        log_error "Unable to identify repository revision: $repository"
        return 1
    }
    if [[ ! "$revision" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]]; then
        log_error "Repository returned an invalid revision: $repository"
        return 1
    fi
    report_file="$staging/report.json"
    if [[ "$mode" == analyze ]]; then
        python3 "$ENGINE_DIR/importer/analyze.py" "$staging/repository" "$repository" "$revision" || {
            log_error "Unable to analyze GitHub repository: $repository"
            return 1
        }
        return 0
    fi
    if ! python3 "$ENGINE_DIR/importer/analyze.py" "$staging/repository" "$repository" "$revision" > "$report_file"; then
        log_error "Unable to analyze GitHub repository: $repository"
        return 1
    fi
    if [[ "$mode" == preview ]]; then
        python3 "$ENGINE_DIR/importer/convert.py" preview "$report_file"
    else
        [[ "$output" == /* ]] || output="$PWD/$output"
        python3 "$ENGINE_DIR/importer/convert.py" convert "$report_file" "$output" || return 1
        if ! theme_manifest_load "$output/theme.conf" "" ||
           ! theme_definition_load "$output/palette.conf" ""; then
            log_error "Converted output failed native theme validation: $output"
            if fs_directory_safe "$output" false; then
                rm -f -- "$output/theme.conf" "$output/palette.conf" || true
                rmdir -- "$output" || log_error "Review and remove invalid conversion output manually: $output"
            fi
            return 1
        fi
        log_success "Validated converted theme pack: $output"
    fi
)
