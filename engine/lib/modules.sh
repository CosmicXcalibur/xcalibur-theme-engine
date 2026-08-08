#!/usr/bin/env bash

# ==========================================================
# Xcalibur Module Loader
# ==========================================================

load_modules() {

    for module_dir in "$MODULES_DIR"/*; do

        [[ -d "$module_dir" ]] || continue

        for module_file in "$module_dir"/*.sh; do

            [[ -f "$module_file" ]] || continue

            source "$module_file"

        done

    done

}

