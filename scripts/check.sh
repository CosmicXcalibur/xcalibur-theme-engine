#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
passed=0 failed=0 skipped=0 unavailable=0

run() {
    local label="$1"; shift
    printf '\nCHECK %s\n' "$label"
    if "$@"; then
        printf 'PASS %s\n' "$label"
        ((passed+=1))
    else
        printf 'FAIL %s\n' "$label" >&2
        ((failed+=1))
    fi
}

syntax() {
    local file
    while IFS= read -r file; do bash -n "$file" || return 1; done < <(find engine modules scripts tests -type f -name '*.sh' | sort)
}

python_syntax() {
    local file
    while IFS= read -r file; do PYTHONDONTWRITEBYTECODE=1 python3 - "$file" <<'PY' || return 1
import sys
from pathlib import Path
compile(Path(sys.argv[1]).read_text(), sys.argv[1], "exec")
PY
    done < <(find engine tests -type f -name '*.py' | sort)
}

cli_smoke() {
    local cli="$ROOT/engine/bin/theme" output status=0
    "$cli" help >/dev/null && "$cli" version >/dev/null && "$cli" list >/dev/null || return 1
    "$cli" definitely-unknown > /dev/null 2>&1 || status=$?
    [[ "$status" -eq 2 ]] || return 1
    status=0
    "$cli" wallpaper set > /dev/null 2>&1 || status=$?
    [[ "$status" -eq 2 ]] || return 1
    if "$cli" import analyze > /dev/null 2>&1; then return 1; fi
    if "$cli" version extra > /dev/null 2>&1; then return 1; fi
    if "$cli" doctor extra > /dev/null 2>&1; then return 1; fi
    if "$cli" wallpaper help extra > /dev/null 2>&1; then return 1; fi
    output="$("$cli" status)" || return 1
    [[ "$output" == *"Engine: $ROOT"* ]]
}

runner_self_test() {
    local output status=0
    output="$(bash "$ROOT/scripts/check.sh" --probe-failure 2>&1)" || status=$?
    [[ "$status" -ne 0 && "$output" == *'FAIL deliberate required check'* &&
       "$output" == *'Summary: 0 passed, 1 failed, 0 skipped, 0 unavailable'* ]]
}

untracked_whitespace() {
    local file bad=0
    while IFS= read -r -d '' file; do
        if ! awk '/[ \t]+$/ {print FILENAME ":" FNR ": trailing whitespace"; bad=1} END {exit bad}' "$file"; then
            bad=1
        fi
    done < <(git ls-files --others --exclude-standard -z)
    ((bad == 0))
}

if [[ "${1:-}" == --probe-failure ]]; then
    run 'deliberate required check' false
elif [[ "$#" -ne 0 ]]; then
    printf 'Usage: scripts/check.sh\n' >&2
    exit 2
else
    run 'Bash syntax' syntax
    if command -v python3 >/dev/null 2>&1; then
        run 'Python syntax' python_syntax
        if find tests -type f -name 'test_*.py' -print -quit | grep -q .; then
            run 'Python unit tests' env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_*.py'
        else
            printf 'SKIP Python unit tests: no Python test files exist\n'
            ((skipped+=1))
        fi
    else
        printf 'UNAVAILABLE Python syntax and unit tests: install python3\n'
        ((unavailable+=2))
    fi
    run 'CLI smoke' cli_smoke
    run 'isolated regressions' bash tests/run.sh
    run 'isolated CLI integration' bash tests/integration.sh
    run 'check runner failure propagation' runner_self_test
    run 'git diff whitespace' git diff --check
    run 'untracked file whitespace' untracked_whitespace
fi

printf '\nSummary: %d passed, %d failed, %d skipped, %d unavailable\n' "$passed" "$failed" "$skipped" "$unavailable"
((failed == 0 && unavailable == 0))
