#!/usr/bin/env bash

# ==========================================================
# Xcalibur Hyprlock Reload
# ==========================================================

hyprlock_reload() {
    # Hyprlock reads its configuration on the next launch. Never terminate an
    # active lock session just to refresh colors.
    return 0
}
