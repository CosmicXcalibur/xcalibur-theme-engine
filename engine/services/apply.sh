#!/usr/bin/env bash

# Prepare privately, snapshot every owned destination, install, reload, then
# commit selection state. The helper verifies journals before recovery.
THEME_TRANSACTION_HELPER="$ENGINE_DIR/lib/transaction.py"

theme_txn_call() {
    python3 "$THEME_TRANSACTION_HELPER" "$@"
}

theme_txn_plan() {
    printf '%s\0%s\0' "$1" "$2" >> "$THEME_TXN_PLAN_FILE"
}

theme_txn_root_lock() {
    local root="$RUNTIME_DIR/transactions"
    if [[ -L "$RUNTIME_DIR" || ( -e "$RUNTIME_DIR" && ! -d "$RUNTIME_DIR" ) ]]; then
        log_error "Unsafe runtime directory: $RUNTIME_DIR"
        return 1
    fi
    if ! mkdir -p -m 700 -- "$RUNTIME_DIR"; then
        log_error "Unable to create runtime directory: $RUNTIME_DIR"
        return 1
    fi
    if [[ -L "$root" || ( -e "$root" && ! -d "$root" ) ]]; then
        log_error "Unsafe transaction directory: $root"
        return 1
    fi
    if ! mkdir -p -m 700 -- "$root"; then
        log_error "Unable to create transaction directory: $root"
        return 1
    fi
    if [[ -L "$root/.lock" || ( -e "$root/.lock" && ! -f "$root/.lock" ) ]]; then
        log_error "Unsafe transaction lock: $root/.lock"
        return 1
    fi
    exec {THEME_TXN_LOCK_FD}>> "$root/.lock"
    if ! flock -n "$THEME_TXN_LOCK_FD"; then
        log_error "Another theme transaction is running."
        return 1
    fi
}

theme_apply_failure() {
    local txn="$1" original_error="$2"
    log_error "$original_error"
    if ! theme_txn_call rollback "$txn"; then
        log_error "Rollback failed; recovery files remain at $txn. Run 'theme recover ${txn##*/}'."
    fi
    return 0
}

theme_apply() (
    local requested_theme="${1-__current__}"
    local requested_wallpaper="${2:-}"
    local selected_theme="$requested_theme"
    local old_wallpaper=""
    local live_generated="$GENERATED_DIR"
    local txn stage module_dir module fn file
    local wallpaper_reloaded=false
    local -a modules_to_apply=()

    if [[ "$requested_theme" == __current__ ]]; then
        selected_theme=""
        if [[ -e "$CURRENT_THEME_FILE" || -L "$CURRENT_THEME_FILE" ]]; then
            if ! theme_active_id_read; then
                log_error "$(theme_display_value "$THEME_ACTIVE_ERROR")"
                return 1
            fi
            selected_theme="$THEME_ACTIVE_ID"
        fi
    elif [[ -n "$requested_theme" ]] && ! theme_id_validate "$requested_theme"; then
        log_error "Invalid theme ID: $(theme_display_value "$requested_theme")"
        return 1
    fi
    if [[ -n "$selected_theme" ]] && ! theme_pack_validate "$selected_theme"; then
        log_error "Theme '$selected_theme' is invalid: $(theme_display_value "$THEME_PACK_ERROR")"
        return 1
    fi
    if [[ -e "$CURRENT_THEME_FILE" || -L "$CURRENT_THEME_FILE" ]] && ! theme_active_id_read; then
        log_error "$(theme_display_value "$THEME_ACTIVE_ERROR")"
        return 1
    fi
    if [[ -e "$STATE_DIR/current_wallpaper" || -L "$STATE_DIR/current_wallpaper" ]]; then
        if [[ -L "$STATE_DIR/current_wallpaper" || ! -f "$STATE_DIR/current_wallpaper" ]]; then
            log_error "Unsafe current wallpaper state."
            return 1
        fi
        old_wallpaper="$(< "$STATE_DIR/current_wallpaper")"
        if ! color_wallpaper_path_validate "$old_wallpaper"; then
            log_error "Current wallpaper state names an unsafe or missing file."
            return 1
        fi
    fi
    [[ -n "$requested_wallpaper" ]] || requested_wallpaper="$old_wallpaper"
    if [[ -z "$requested_wallpaper" ]]; then
        log_error "No current wallpaper selected."
        return 1
    fi
    if ! command -v python3 >/dev/null || ! command -v flock >/dev/null; then
        log_error "Theme application requires python3 and flock."
        return 1
    fi
    theme_txn_root_lock || return 1
    if ! theme_txn_call check "$RUNTIME_DIR/transactions"; then
        log_error "Resolve the incomplete transaction with 'theme recover' before applying another theme."
        return 1
    fi
    if ! txn="$(theme_txn_call create "$RUNTIME_DIR/transactions" "$HOME" "$live_generated" \
        "${CWAL_COLORS%/*}" "$CURRENT_THEME_FILE" "$STATE_DIR/current_wallpaper")"; then
        log_error "Unable to start theme transaction."
        return 1
    fi
    stage="$txn/stage"
    THEME_TXN_STAGE_DIR="$stage"
    if ! mkdir -m 700 -- "$stage/generated" "$stage/cwal"; then
        theme_apply_failure "$txn" "Unable to create theme preparation directories."
        return 1
    fi
    GENERATED_DIR="$stage/generated"
    RUNTIME_COLORS="$GENERATED_DIR/colors.sh"
    if ! color_generate "$requested_wallpaper" "$selected_theme" "$stage/cwal"; then
        theme_apply_failure "$txn" "Palette preparation failed."
        return 1
    fi

    for module_dir in "$MODULES_DIR"/*; do
        [[ -d "$module_dir" ]] || continue
        module="${module_dir##*/}"
        fn="${module}_render"
        if ! declare -F "$fn" > /dev/null; then continue; fi
        if ! declare -F "${module}_transaction_plan" > /dev/null; then
            theme_apply_failure "$txn" "Module '$module' has no transaction destination plan."
            return 1
        fi
        modules_to_apply+=("$module")
        if ! "$fn"; then
            theme_apply_failure "$txn" "Rendering failed for module '$module'."
            return 1
        fi
    done
    if ! python3 "$ENGINE_DIR/renderer/render_template.py" validate "$GENERATED_DIR"; then
        theme_apply_failure "$txn" "Prepared output validation failed."
        return 1
    fi

    THEME_TXN_PLAN_FILE="$txn/plan.nul"
    : > "$THEME_TXN_PLAN_FILE" || { theme_apply_failure "$txn" "Unable to write transaction plan."; return 1; }
    local scheme_file
    shopt -s nullglob dotglob
    for file in "$stage/cwal"/*; do
        if [[ -d "$file" && ! -L "$file" ]]; then
            if [[ "${file##*/}" != schemes ]]; then
                theme_apply_failure "$txn" "Unexpected cwal output directory: $file"
                return 1
            fi
            for scheme_file in "$file"/*; do
                if [[ ! -f "$scheme_file" || -L "$scheme_file" ]] ||
                   ! theme_txn_plan "$scheme_file" "${CWAL_COLORS%/*}/schemes/${scheme_file##*/}"; then
                    theme_apply_failure "$txn" "Unable to record cwal scheme: $scheme_file"
                    return 1
                fi
            done
        elif [[ ! -f "$file" || -L "$file" ]] ||
             ! theme_txn_plan "$file" "${CWAL_COLORS%/*}/${file##*/}"; then
            theme_apply_failure "$txn" "Unable to record cwal output: $file"
            return 1
        fi
    done
    for file in "$stage/generated"/*; do
        if [[ ! -f "$file" || -L "$file" ]] ||
           ! theme_txn_plan "$file" "$live_generated/${file##*/}"; then
            theme_apply_failure "$txn" "Unable to record generated output: $file"
            return 1
        fi
    done
    for module in "${modules_to_apply[@]}"; do
        if ! "${module}_transaction_plan"; then
            theme_apply_failure "$txn" "Unable to plan module '$module' destinations."
            return 1
        fi
    done
    local state_theme=- state_wallpaper=-
    [[ "$requested_theme" == __current__ ]] || state_theme="$requested_theme"
    [[ -z "${2:-}" ]] || state_wallpaper="$requested_wallpaper"
    if ! theme_txn_call prepare "$txn" "$THEME_TXN_PLAN_FILE" "$state_theme" "$state_wallpaper"; then
        theme_apply_failure "$txn" "Unable to snapshot theme destinations."
        return 1
    fi
    if ! theme_txn_call install "$txn"; then
        theme_apply_failure "$txn" "Theme configuration installation failed."
        return 1
    fi
    if ! theme_txn_call phase "$txn" reloading; then
        theme_apply_failure "$txn" "Unable to record reload phase."
        return 1
    fi
    if [[ -n "${2:-}" ]]; then
        if ! wallpaper_reload "$requested_wallpaper"; then
            theme_apply_failure "$txn" "Wallpaper reload failed."
            if [[ -n "$old_wallpaper" ]]; then wallpaper_reload "$old_wallpaper" || log_error "Unable to restore the previous live wallpaper."; fi
            return 1
        fi
        wallpaper_reloaded=true
    fi
    for module in "${modules_to_apply[@]}"; do
        [[ "$module" == hyprlock ]] && continue
        fn="${module}_reload"
        if declare -F "$fn" > /dev/null && ! "$fn"; then
            theme_apply_failure "$txn" "Required reload failed for module '$module'."
            if [[ "$wallpaper_reloaded" == true && -n "$old_wallpaper" ]]; then
                wallpaper_reload "$old_wallpaper" || log_error "Unable to restore the previous live wallpaper."
            fi
            return 1
        fi
    done
    if ! theme_txn_call commit "$txn"; then
        theme_apply_failure "$txn" "Unable to commit theme state."
        if [[ "$wallpaper_reloaded" == true && -n "$old_wallpaper" ]]; then
            wallpaper_reload "$old_wallpaper" || log_error "Unable to restore the previous live wallpaper."
        fi
        return 1
    fi
    if ! theme_txn_call finish "$txn"; then
        log_error "Theme files and state were committed, but cleanup failed at $txn. Run 'theme recover ${txn##*/}'."
        return 1
    fi
    log_success "Theme applied."
)

theme_transaction_recover() (
    if [[ "$#" -gt 1 ]]; then
        log_error "Usage: theme recover [--list|transaction-id]"
        return 1
    fi
    theme_txn_root_lock || return 1
    case "${1:-}" in
        --list) theme_txn_call list "$RUNTIME_DIR/transactions" ;;
        "") theme_txn_call recover "$RUNTIME_DIR/transactions" ;;
        *) theme_txn_call recover "$RUNTIME_DIR/transactions" "$1" ;;
    esac
)
