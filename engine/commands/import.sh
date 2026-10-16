#!/usr/bin/env bash

command_import_source() (
    local mode="${1:-}" repository="${2:-}" output="${3:-}" staging="" revision report_file
    local source_kind=github source_dir="" retrieval_info="" source_ref="" pinned_revision="" slug
    local selector="" component
    local -a selector_parts=()
    if [[ "$mode" == install ]]; then
        [[ "$#" -eq 2 ]] || { log_error "Usage: theme import install <pack-directory>"; return 2; }
        theme_install_from_directory "$repository"
        return
    fi
    if [[ "$mode" != analyze && "$mode" != preview && "$mode" != convert &&
          "$mode" != install-source ]] ||
       { [[ "$mode" == convert && "$#" -ne 3 && "$#" -ne 5 ]] ||
         [[ "$mode" != convert && "$#" -ne 2 && "$#" -ne 4 ]]; } ||
       { [[ "$mode" == convert && "$#" -eq 5 && "${4:-}" != --theme ]] ||
         [[ "$mode" != convert && "$#" -eq 4 && "${3:-}" != --theme ]]; }; then
        log_error "Usage: theme import analyze|preview <source> [--theme <relative-file>] | convert <source> <new-output-directory> [--theme <relative-file>] | install <pack-directory>"
        return 2
    fi
    if [[ "$mode" == convert && "$#" -eq 5 ]]; then
        selector="$5"
    elif [[ "$mode" != convert && "$#" -eq 4 ]]; then
        selector="$4"
    fi
    if [[ "$#" -gt 3 || -n "$selector" ]]; then
        if [[ -z "$selector" || "$selector" == /* || "$selector" == *\\* ||
              "$selector" =~ [[:cntrl:]] || ${#selector} -gt 1024 ||
              ( "${selector,,}" != *.conf && "${selector,,}" != *.css &&
                "${selector,,}" != *.theme ) ]]; then
            log_error "Invalid theme selector; use an exact relative .conf, .css, or .theme file path."
            return 2
        fi
        IFS='/' read -r -a selector_parts <<< "$selector"
        if [[ ${#selector_parts[@]} -gt 9 || "$selector" == *//* ]]; then
            log_error "Invalid theme selector path."
            return 2
        fi
        for component in "${selector_parts[@]}"; do
            if [[ -z "$component" || "$component" == . || "$component" == .. ]]; then
                log_error "Invalid theme selector path."
                return 2
            fi
        done
    fi
    if [[ "$mode" == install-source &&
          ( "$repository" == /* || "$repository" == ./* || "$repository" == ../* ) ]]; then
        log_error "theme install requires a GitHub repository; use theme import install for a reviewed local pack."
        return 2
    fi
    if [[ "$repository" == /* || "$repository" == ./* || "$repository" == ../* ]]; then
        source_kind=local
        if [[ "$repository" != /* ]]; then
            repository="$PWD/${repository#./}"
        fi
        if ! fs_directory_safe "$repository" false; then
            log_error "Unsafe or missing local source directory: $2"
            return 2
        fi
        source_dir="$repository"
        slug="$(basename -- "$source_dir" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/-\+/-/g; s/^-//; s/-$//')"
        if [[ -z "$slug" || ${#slug} -gt 80 ]]; then
            log_error "Local source name cannot become a safe theme ID: $2"
            return 2
        fi
        repository="local/$slug"
    else
        repository="${repository#https://github.com/}"
        repository="${repository%/}"
        repository="${repository%.git}"
        if [[ "$repository" == *@* ]]; then
            pinned_revision="${repository##*@}"
            repository="${repository%@*}"
            if [[ ! "$pinned_revision" =~ ^[0-9a-f]{40}$ ]]; then
                log_error "Pinned GitHub revision must be a lowercase 40-character commit SHA."
                return 2
            fi
        fi
        if ! theme_install_repo_validate "$repository"; then
            log_error "Invalid GitHub repository reference: $2"
            return 2
        fi
        source_ref="$repository${pinned_revision:+@$pinned_revision}"
    fi
    if ! cmd_exists python3 || ! cmd_exists timeout; then
        log_error "Import analysis requires python3 and timeout."
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
    if [[ "$source_kind" == github ]]; then
        retrieval_info="$staging/retrieval.json"
        revision="$(timeout 75s python3 "$ENGINE_DIR/importer/retrieve.py" \
            "$source_ref" "$staging/repository" "$retrieval_info")" || {
            log_error "Unable to retrieve bounded GitHub source: $repository"
            return 1
        }
        if [[ ! "$revision" =~ ^[0-9a-f]{40}$ || ! -f "$retrieval_info" ]]; then
            log_error "Retrieval returned invalid commit information: $repository"
            return 1
        fi
        source_dir="$staging/repository"
    else
        revision=unversioned
        if cmd_exists git && [[ -d "$source_dir/.git" && ! -L "$source_dir/.git" ]]; then
            revision="$(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_OPTIONAL_LOCKS=0 \
                timeout 10s git -c core.hooksPath=/dev/null -C "$source_dir" rev-parse --verify HEAD)" || {
                log_error "Unable to identify local repository revision: $2"
                return 1
            }
            [[ "$revision" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] || {
                log_error "Invalid local repository revision: $2"
                return 1
            }
        fi
    fi
    report_file="$staging/report.json"
    if [[ "$mode" == analyze ]]; then
        python3 "$ENGINE_DIR/importer/analyze.py" "$source_dir" "$repository" "$revision" "$source_kind" "${retrieval_info:--}" "${selector:--}" || {
            log_error "Unable to analyze source: $2"
            return 1
        }
        return 0
    fi
    if ! python3 "$ENGINE_DIR/importer/analyze.py" "$source_dir" "$repository" "$revision" "$source_kind" "${retrieval_info:--}" "${selector:--}" > "$report_file"; then
        log_error "Unable to analyze source: $2"
        return 1
    fi
    if [[ "$mode" == install-source ]]; then
        local candidate_count
        if ! python3 "$ENGINE_DIR/importer/convert.py" preview "$report_file" "$THEMES_DIR" > "$staging/preview.txt"; then
            log_error "Unable to preview retrieved theme: $2"
            return 1
        fi
        candidate_count="$(python3 - "$report_file" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as source:
    print(len(json.load(source)["theme_candidates"]))
PY
)" || return 1
        if [[ ! "$candidate_count" =~ ^[0-9]+$ ]]; then
            log_error "Invalid candidate count in analysis report."
            return 1
        fi
        if [[ -z "$selector" && "$candidate_count" -gt 1 ]]; then
            cat "$staging/preview.txt"
            log_error "Multiple themes found. Retry with --theme <exact-relative-file> and the pinned source shown above."
            return 2
        fi
        if [[ -z "$selector" && "$candidate_count" -eq 0 ]] &&
           theme_install_root_file_validate "$source_dir/theme.conf" &&
           theme_install_root_file_validate "$source_dir/palette.conf" &&
           theme_manifest_load "$source_dir/theme.conf" "" &&
           theme_definition_load "$source_dir/palette.conf" ""; then
            log_info "Installing validated native pack from $repository@$revision."
            sed -n '/^License status:/p' "$staging/preview.txt"
            log_warn "Review upstream license terms before use or redistribution."
            theme_install_from_directory "$source_dir"
            return
        fi
        cat "$staging/preview.txt"
        if ! python3 "$ENGINE_DIR/importer/convert.py" convert "$report_file" "$staging/converted"; then
            log_error "Unable to convert source; review the preview and select a supported candidate."
            return 1
        fi
        theme_install_from_directory "$staging/converted"
    elif [[ "$mode" == preview ]]; then
        python3 "$ENGINE_DIR/importer/convert.py" preview "$report_file" "$THEMES_DIR"
    else
        [[ "$output" != ./* ]] || output="${output#./}"
        [[ "$output" == /* ]] || output="$PWD/$output"
        python3 "$ENGINE_DIR/importer/convert.py" convert "$report_file" "$output" || return 1
        log_success "Validated converted theme pack: $output"
    fi
)

command_import() {
    case "${1:-}" in
        analyze|preview|convert|install) command_import_source "$@" ;;
        *)
            log_error "Usage: theme import analyze|preview <source> [--theme <relative-file>] | convert <source> <new-output-directory> [--theme <relative-file>] | install <pack-directory>"
            return 2
            ;;
    esac
}
