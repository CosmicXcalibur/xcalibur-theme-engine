#!/usr/bin/env bash

set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$#" -ne 1 ]]; then
    printf 'Usage: set-wallpaper.sh <wallpaper>\n' >&2
    exit 2
fi
exec "$ROOT/engine/bin/theme" wallpaper set "$1"
