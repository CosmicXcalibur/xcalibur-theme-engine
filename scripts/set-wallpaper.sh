#!/usr/bin/env bash

set -e

WALL="$1"

if [[ ! -f "$WALL" ]]; then
    echo "Wallpaper not found."
    exit 1
fi

echo "$WALL" > ~/.config/theme/current

hyprctl hyprpaper unload all >/dev/null 2>&1 || true
hyprctl hyprpaper preload "$WALL"
hyprctl hyprpaper wallpaper ",$WALL"

~/.config/theme/scripts/apply-theme.sh "$WALL"
