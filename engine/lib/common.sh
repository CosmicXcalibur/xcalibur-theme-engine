#!/usr/bin/env bash

# ============================================================
# Theme Engine Common Library
#
# Generic helper functions used across the Theme Engine.
#
# This file MUST NOT contain:
#   - Wallpaper logic
#   - Theme generation
#   - Rendering
#   - Application-specific code
#
# Only generic reusable utilities belong here.
# ============================================================

# ------------------------------------------------------------
# Colors
# ------------------------------------------------------------

readonly COLOR_RESET="\033[0m"
readonly COLOR_RED="\033[31m"
readonly COLOR_GREEN="\033[32m"
readonly COLOR_YELLOW="\033[33m"
readonly COLOR_BLUE="\033[34m"

# ------------------------------------------------------------
# Logging
# ------------------------------------------------------------

log_info() {
    printf "${COLOR_BLUE}[INFO]${COLOR_RESET} %s\n" "$*"
}

log_success() {
    printf "${COLOR_GREEN}[ OK ]${COLOR_RESET} %s\n" "$*"
}

log_warn() {
    printf "${COLOR_YELLOW}[WARN]${COLOR_RESET} %s\n" "$*"
}

log_error() {
    printf "${COLOR_RED}[FAIL]${COLOR_RESET} %s\n" "$*" >&2
}

die() {
    log_error "$*"
    exit 1
}

# ------------------------------------------------------------
# Utilities
# ------------------------------------------------------------

util_timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

# ------------------------------------------------------------
# Command Helpers
# ------------------------------------------------------------

cmd_exists() {
    command -v "$1" >/dev/null 2>&1
}

require_commands() {
    local cmd

    for cmd in "$@"; do
        if ! cmd_exists "$cmd"; then
            die "Required command not found: $cmd"
        fi
    done
}

# ------------------------------------------------------------
# Filesystem Helpers
# ------------------------------------------------------------

fs_ensure_dir() {
    mkdir -p "$1"
}

fs_ensure_file() {
    touch "$1"
}

fs_require_file() {
    [[ -f "$1" ]] || die "File not found: $1"
}

fs_require_dir() {
    [[ -d "$1" ]] || die "Directory not found: $1"
}
