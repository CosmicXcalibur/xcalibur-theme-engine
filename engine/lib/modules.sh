#!/usr/bin/env bash

# ==========================================================
# Xcalibur Module Loader
# ==========================================================

load_modules() {
    [[ "$MODULES_DIR" == "$THEME_ROOT/modules" ]] || die "Modules directory is outside the engine root: $MODULES_DIR"
    fs_directory_safe "$MODULES_DIR" false || die "Unsafe modules directory: $MODULES_DIR"

    for module_dir in "$MODULES_DIR"/*; do

        [[ -d "$module_dir" && ! -L "$module_dir" ]] || continue

        for module_file in "$module_dir"/*.sh; do

            [[ -f "$module_file" && ! -L "$module_file" ]] || continue

            source "$module_file"

        done

    done

}

