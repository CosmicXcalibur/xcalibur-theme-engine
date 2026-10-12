#!/usr/bin/env bash

# ==========================================================
# Theme Pack Installation
# ==========================================================

THEME_INSTALL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -F theme_pack_validate > /dev/null; then
    source "$THEME_INSTALL_LIB_DIR/theme_pack.sh"
fi

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

theme_install_adapter_spec() {
    # Each adapter declares its one trusted repository, data input, local
    # converter, and allowed variants. Empty variants mean no --variant.
    case "$1" in
        catppuccin)
            THEME_ADAPTER_REPOSITORY=catppuccin/palette
            THEME_ADAPTER_INPUT=palette.json
            THEME_ADAPTER_CONVERTER=catppuccin.py
            THEME_ADAPTER_VARIANTS="latte frappe macchiato mocha"
            ;;
        rose-pine)
            THEME_ADAPTER_REPOSITORY=rose-pine/rose-pine-palette
            THEME_ADAPTER_INPUT=palette.json
            THEME_ADAPTER_CONVERTER=rose_pine.py
            THEME_ADAPTER_VARIANTS="main moon dawn"
            ;;
        nord)
            THEME_ADAPTER_REPOSITORY=nordtheme/nord
            THEME_ADAPTER_INPUT=src/nord.css
            THEME_ADAPTER_CONVERTER=nord.py
            THEME_ADAPTER_VARIANTS=""
            ;;
        *) return 1 ;;
    esac
}

theme_install_adapter_variant_validate() {
    local variant="$1"
    local allowed_variant

    for allowed_variant in $THEME_ADAPTER_VARIANTS; do
        [[ "$variant" == "$allowed_variant" ]] && return 0
    done
    return 1
}

theme_install_source_file_validate() {
    local repository_dir="$1"
    local relative_path="$2"
    local path="$repository_dir"
    local component
    local -a components=()

    IFS='/' read -r -a components <<< "$relative_path"
    for component in "${components[@]}"; do
        path="$path/$component"
        [[ ! -L "$path" ]] || return 1
    done
    [[ -f "$path" ]]
}

# Install a staged native pack. Both native repositories and adapter output
# pass through this function and the same manifest/definition validators.
theme_install_native_pack() {
    local source_dir="$1"
    local manifest="$source_dir/theme.conf"
    local definition="$source_dir/palette.conf"
    local theme_id=""
    local theme_dir=""
    local destination_created=false

    if ! theme_install_root_file_validate "$manifest"; then
        log_error "Theme pack is missing a regular, non-symlink theme.conf at its root."
        return 1
    fi

    if ! theme_install_root_file_validate "$definition"; then
        log_error "Theme pack is missing a regular, non-symlink palette.conf at its root."
        return 1
    fi

    if ! theme_manifest_load "$manifest" ""; then
        log_error "Invalid theme manifest: $THEME_MANIFEST_ERROR"
        return 1
    fi

    theme_id="$THEME_ID"

    if ! theme_id_validate "$theme_id"; then
        log_error "Invalid theme ID: $theme_id"
        return 1
    fi

    if ! theme_definition_load "$definition" ""; then
        log_error "Invalid theme palette definition: $THEME_DEFINITION_ERROR"
        return 1
    fi

    if ! theme_library_check; then
        log_error "$(theme_display_value "$THEME_PACK_ERROR")"
        return 1
    fi

    theme_dir="$THEMES_DIR/$theme_id"

    if [[ -e "$theme_dir" || -L "$theme_dir" ]]; then
        log_error "Theme '$theme_id' is already installed."
        return 1
    fi

    if ! mkdir "$theme_dir"; then
        log_error "Unable to create theme directory: $theme_dir"
        return 1
    fi
    destination_created=true

    if ! cp -- "$manifest" "$theme_dir/theme.conf" ||
       ! cp -- "$definition" "$theme_dir/palette.conf"; then
        if [[ "$destination_created" == true ]]; then
            rm -rf -- "$theme_dir"
        fi
        log_error "Unable to install theme '$theme_id'."
        return 1
    fi

    if ! theme_pack_validate "$theme_id"; then
        if [[ "$destination_created" == true ]]; then
            rm -rf -- "$theme_dir"
        fi
        log_error "Installed theme '$theme_id' failed verification: $(theme_display_value "$THEME_PACK_ERROR")"
        return 1
    fi

    log_success "Theme installed: $theme_id"
}

# Convert one staged repository into a native pack, then use the common
# native validation and installation path above.
theme_install_staged_repository() {
    local repository_dir="$1"
    local format="$2"
    local variant="$3"
    local staging_dir="$4"
    local native_dir="$repository_dir"
    local input_file=""
    local -a converter_command=()

    case "$format" in
        native)
            if [[ -e "$repository_dir/theme.conf" || -e "$repository_dir/palette.conf" ||
                  -L "$repository_dir/theme.conf" || -L "$repository_dir/palette.conf" ]]; then
                theme_install_native_pack "$repository_dir"
                return $?
            fi

            log_error "Repository is missing root-level theme.conf and palette.conf."
            return 1
            ;;
        *)
            if ! theme_install_adapter_spec "$format"; then
                log_error "Unsupported theme source format: $format"
                return 1
            fi
            input_file="$repository_dir/$THEME_ADAPTER_INPUT"
            if ! theme_install_source_file_validate "$repository_dir" "$THEME_ADAPTER_INPUT"; then
                log_error "Repository is missing a regular, non-symlink $THEME_ADAPTER_INPUT."
                return 1
            fi

            native_dir="$staging_dir/native-pack"
            converter_command=(python3 "$THEME_INSTALL_LIB_DIR/adapters/$THEME_ADAPTER_CONVERTER"
                --input "$input_file" --output "$native_dir")
            if [[ -n "$variant" ]]; then
                converter_command+=(--variant "$variant")
            fi
            if ! "${converter_command[@]}"; then
                log_error "Unable to convert $format palette."
                return 1
            fi

            theme_install_native_pack "$native_dir"
            return $?
            ;;
    esac
}

theme_install() {
    if [[ "$#" -lt 2 ]]; then
        log_error "Usage: theme install <owner/repo> [--format <adapter> [--variant <variant>]]"
        return 1
    fi

    local repository="$2"
    local format=native
    local variant=""
    local format_seen=false
    local variant_seen=false
    local staging_dir=""
    local repository_dir=""
    local install_status=0

    shift 2
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --format)
                if [[ "$format_seen" == true || "$#" -lt 2 ]]; then
                    log_error "Duplicate or missing --format value."
                    return 1
                fi
                format="$2"
                format_seen=true
                shift 2
                ;;
            --variant)
                if [[ "$variant_seen" == true || "$#" -lt 2 ]]; then
                    log_error "Duplicate or missing --variant value."
                    return 1
                fi
                variant="$2"
                variant_seen=true
                shift 2
                ;;
            *)
                log_error "Unknown install option: $1"
                return 1
                ;;
        esac
    done

    if [[ "$variant_seen" == true && "$format_seen" == false ]]; then
        log_error "--variant requires an external --format."
        return 1
    fi

    if ! theme_install_repo_validate "$repository"; then
        log_error "Invalid GitHub repository reference: $repository"
        return 1
    fi

    if [[ "$format_seen" == true ]]; then
        if ! theme_install_adapter_spec "$format"; then
            log_error "Unsupported theme source format: $format"
            return 1
        fi
        if [[ "$repository" != "$THEME_ADAPTER_REPOSITORY" ]]; then
            log_error "The $format adapter supports only: $THEME_ADAPTER_REPOSITORY."
            return 1
        fi
        if [[ -n "$THEME_ADAPTER_VARIANTS" && "$variant_seen" == false ]]; then
            log_error "$format installs require --variant (expected: $THEME_ADAPTER_VARIANTS)."
            return 1
        fi
        if [[ -z "$THEME_ADAPTER_VARIANTS" && "$variant_seen" == true ]]; then
            log_error "$format does not support --variant."
            return 1
        fi
        if [[ "$variant_seen" == true ]] && ! theme_install_adapter_variant_validate "$variant"; then
            log_error "Invalid $format variant: $variant (expected: $THEME_ADAPTER_VARIANTS)."
            return 1
        fi
    fi

    if ! cmd_exists git; then
        log_error "Required command not found: git"
        return 1
    fi

    if [[ "$format_seen" == true ]] && ! cmd_exists python3; then
        log_error "Required command not found: python3 (needed for external palette import)."
        return 1
    fi

    if ! staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/xcalibur-theme-install.XXXXXX")"; then
        log_error "Unable to create temporary staging directory."
        return 1
    fi

    repository_dir="$staging_dir/repository"

    if ! GIT_TERMINAL_PROMPT=0 git clone \
        --depth 1 \
        --no-recurse-submodules \
        --quiet \
        "https://github.com/$repository.git" \
        "$repository_dir"; then
        log_error "Unable to retrieve GitHub repository: $repository"
        install_status=1
    elif ! theme_install_staged_repository "$repository_dir" "$format" "$variant" "$staging_dir"; then
        install_status=1
    fi

    if ! rm -rf -- "$staging_dir"; then
        log_error "Unable to remove temporary staging directory: $staging_dir"
        install_status=1
    fi

    return "$install_status"
}
