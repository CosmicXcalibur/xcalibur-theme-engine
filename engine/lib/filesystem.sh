#!/usr/bin/env bash

# Check each component before creating anything beneath it. This rejects
# pre-existing symlinked parents; Bash path checks cannot prevent a concurrent
# process with write access from replacing a component after the check.
fs_directory_safe() {
    local path="$1" create="${2:-false}" component current=""
    local -a components
    [[ "$path" == /* && "$path" != *'//'* && "$path" != */ &&
       ! "$path" =~ [[:cntrl:]] ]] || return 1
    IFS=/ read -r -a components <<< "$path"
    for component in "${components[@]}"; do
        [[ -n "$component" ]] || continue
        [[ "$component" != . && "$component" != .. ]] || return 1
        current+="/$component"
        [[ ! -L "$current" ]] || return 1
        if [[ ! -e "$current" ]]; then
            [[ "$create" == true ]] || return 1
            mkdir -- "$current" || return 1
        fi
        [[ -d "$current" && ! -L "$current" ]] || return 1
    done
}

# Replace one engine-owned application file without exposing a partial write.
fs_install_atomic() {
    local source_file="$1" target="$2" mode="${3:-644}" target_dir tmp
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
    [[ -f "$source_file" && ! -L "$source_file" && ! -L "$target" &&
       "$target" == /* && ! "$target" =~ [[:cntrl:]] ]] || {
        log_error "Invalid installation source or target: $target"
        return 1
    }
    target_dir="$(dirname "$target")"
    fs_directory_safe "$target_dir" true || {
        log_error "Unsafe installation directory: $target_dir"
        return 1
    }
    [[ ! -e "$target" || -f "$target" ]] || return 1
    tmp="$(mktemp "$target_dir/.xcalibur.XXXXXX")" || return 1
    if ! install -m "$mode" -- "$source_file" "$tmp" ||
       ! fs_directory_safe "$target_dir" false ||
       [[ -L "$target" || ( -e "$target" && ! -f "$target" ) ]] ||
       ! mv -fT -- "$tmp" "$target"; then
        rm -f -- "$tmp"
        return 1
    fi
}

# During a theme transaction, avoid treating an unchanged engine output as an
# original user configuration on a later application.
fs_matches_previous_generated() {
    local target="$1" filename="$2" previous_dir="${THEME_APPLY_PREVIOUS_GENERATED_DIR:-}"
    [[ -n "$previous_dir" && -f "$previous_dir/$filename" &&
       ! -L "$previous_dir/$filename" ]] &&
        fs_directory_safe "$previous_dir" false &&
        cmp -s -- "$target" "$previous_dir/$filename"
}
