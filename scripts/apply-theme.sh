#!/usr/bin/env bash

set -e

WALL="$1"

if [[ -z "$WALL" ]]; then
    echo "Usage: apply-theme.sh <wallpaper>"
    exit 1
fi

echo "Generating theme..."

cwal -i "$WALL"

echo "Done."
