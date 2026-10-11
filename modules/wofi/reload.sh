#!/usr/bin/env bash

# ==========================================================
# Wofi Reload
# ==========================================================

wofi_reload() {
    # Wofi reads style.css when launched. Closing an active launcher would
    # discard the user's current interaction.
    return 0
}
