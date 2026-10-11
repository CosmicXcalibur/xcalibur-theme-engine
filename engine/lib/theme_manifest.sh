#!/usr/bin/env bash

# ==========================================================
# Xcalibur Theme Manifest Parser
# ==========================================================

THEME_MANIFEST_ERROR=""

theme_manifest_fail() {
    THEME_MANIFEST_ERROR="$1"
    return 1
}

theme_id_validate() {
    local theme_id="$1"

    [[ "$theme_id" =~ ^[a-z0-9]+([a-z0-9-]*[a-z0-9])?$ ]]
}

theme_manifest_load() {
    local manifest="$1"
    local expected_id="$2"
    local line key value
    local seen_theme_id=false
    local seen_theme_name=false
    local seen_theme_version=false
    local seen_theme_author=false
    local seen_theme_description=false

    THEME_MANIFEST_ERROR=""
    THEME_ID=""
    THEME_NAME=""
    THEME_VERSION=""
    THEME_AUTHOR=""
    THEME_DESCRIPTION=""

    if [[ ! -f "$manifest" || -L "$manifest" ]] ||
       [[ "$(stat -c %s -- "$manifest")" -gt 262144 ]]; then
        theme_manifest_fail "missing, unsafe, or oversized theme.conf"
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue

        if [[ ! "$line" =~ ^([A-Z_]+)=(.*)$ ]]; then
            theme_manifest_fail "invalid line: expected KEY=VALUE"
            return 1
        fi

        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"

        if [[ -z "$value" || "$value" =~ [[:cntrl:]] ]]; then
            theme_manifest_fail "invalid value for $key"
            return 1
        fi

        case "$key" in
            THEME_ID)
                [[ "$seen_theme_id" == false ]] || {
                    theme_manifest_fail "duplicate field: THEME_ID"
                    return 1
                }
                THEME_ID="$value"
                seen_theme_id=true
                ;;
            THEME_NAME)
                [[ "$seen_theme_name" == false ]] || {
                    theme_manifest_fail "duplicate field: THEME_NAME"
                    return 1
                }
                THEME_NAME="$value"
                seen_theme_name=true
                ;;
            THEME_VERSION)
                [[ "$seen_theme_version" == false ]] || {
                    theme_manifest_fail "duplicate field: THEME_VERSION"
                    return 1
                }
                THEME_VERSION="$value"
                seen_theme_version=true
                ;;
            THEME_AUTHOR)
                [[ "$seen_theme_author" == false ]] || {
                    theme_manifest_fail "duplicate field: THEME_AUTHOR"
                    return 1
                }
                THEME_AUTHOR="$value"
                seen_theme_author=true
                ;;
            THEME_DESCRIPTION)
                [[ "$seen_theme_description" == false ]] || {
                    theme_manifest_fail "duplicate field: THEME_DESCRIPTION"
                    return 1
                }
                THEME_DESCRIPTION="$value"
                seen_theme_description=true
                ;;
            *)
                theme_manifest_fail "unknown field: $key"
                return 1
                ;;
        esac
    done < "$manifest"

    if [[ "$seen_theme_id" != true ]]; then
        theme_manifest_fail "missing required field: THEME_ID"
        return 1
    fi

    if [[ "$seen_theme_name" != true ]]; then
        theme_manifest_fail "missing required field: THEME_NAME"
        return 1
    fi

    if [[ "$seen_theme_version" != true ]]; then
        theme_manifest_fail "missing required field: THEME_VERSION"
        return 1
    fi

    if [[ "$seen_theme_author" != true ]]; then
        theme_manifest_fail "missing required field: THEME_AUTHOR"
        return 1
    fi

    if [[ "$seen_theme_description" != true ]]; then
        theme_manifest_fail "missing required field: THEME_DESCRIPTION"
        return 1
    fi

    if ! theme_id_validate "$THEME_ID"; then
        theme_manifest_fail "invalid THEME_ID: $THEME_ID"
        return 1
    fi

    if [[ ! "$THEME_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][A-Za-z0-9.-]+)?$ ]]; then
        theme_manifest_fail "invalid THEME_VERSION: $THEME_VERSION"
        return 1
    fi

    if [[ -n "$expected_id" && "$THEME_ID" != "$expected_id" ]]; then
        theme_manifest_fail "THEME_ID does not match directory name"
        return 1
    fi
}
