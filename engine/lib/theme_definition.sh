#!/usr/bin/env bash

# ==========================================================
# Xcalibur Theme Definition Parser
# ==========================================================

THEME_DEFINITION_ERROR=""

declare -ga THEME_DEFINITION_ROLES=(
    BACKGROUND
    FOREGROUND
    CURSOR
    PRIMARY
    SECONDARY
    ACCENT
    SUCCESS
    WARNING
    ERROR
    MUTED
    SURFACE
    SURFACE_ALT
    BORDER
    SELECTION
    HIGHLIGHT
)

declare -gA THEME_DEFINITION_VALUES=()

theme_definition_fail() {
    THEME_DEFINITION_ERROR="$1"
    return 1
}

theme_definition_role_valid() {
    local role="$1"
    local allowed_role

    for allowed_role in "${THEME_DEFINITION_ROLES[@]}"; do
        [[ "$role" == "$allowed_role" ]] && return 0
    done

    return 1
}

theme_definition_value_valid() {
    local value="$1"

    [[ "$value" =~ ^#[0-9A-Fa-f]{6}$ || "$value" =~ ^COLOR([0-9]|1[0-5])$ ]]
}

theme_definition_load() {
    local definition="$1"
    local expected_id="$2"
    local definition_dir
    local line key value
    local seen_version=false

    THEME_DEFINITION_ERROR=""
    THEME_DEFINITION_VALUES=()

    if [[ ! -f "$definition" ]]; then
        theme_definition_fail "missing palette.conf"
        return 1
    fi

    if [[ -n "$expected_id" ]] && ! theme_id_validate "$expected_id"; then
        theme_definition_fail "invalid theme ID: $expected_id"
        return 1
    fi

    definition_dir="$(basename "$(dirname "$definition")")"

    if [[ -n "$expected_id" && "$definition_dir" != "$expected_id" ]]; then
        theme_definition_fail "theme ID does not match palette directory"
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue

        if [[ ! "$line" =~ ^([A-Z_]+)=(.*)$ ]]; then
            theme_definition_fail "invalid line: expected KEY=VALUE"
            return 1
        fi

        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"

        if [[ -z "$value" || "$value" =~ [[:cntrl:]] ]]; then
            theme_definition_fail "invalid value for $key"
            return 1
        fi

        if [[ "$key" == XCALIBUR_DEFINITION_VERSION ]]; then
            if [[ "$seen_version" == true ]]; then
                theme_definition_fail "duplicate field: XCALIBUR_DEFINITION_VERSION"
                return 1
            fi

            if [[ "$value" != 1 ]]; then
                theme_definition_fail "unsupported XCALIBUR_DEFINITION_VERSION: $value"
                return 1
            fi

            seen_version=true
            continue
        fi

        if ! theme_definition_role_valid "$key"; then
            theme_definition_fail "unknown field: $key"
            return 1
        fi

        if [[ -v "THEME_DEFINITION_VALUES[$key]" ]]; then
            theme_definition_fail "duplicate field: $key"
            return 1
        fi

        if ! theme_definition_value_valid "$value"; then
            theme_definition_fail "invalid color value for $key"
            return 1
        fi

        THEME_DEFINITION_VALUES["$key"]="$value"
    done < "$definition"

    if [[ "$seen_version" != true ]]; then
        theme_definition_fail "missing required field: XCALIBUR_DEFINITION_VERSION"
        return 1
    fi
}
