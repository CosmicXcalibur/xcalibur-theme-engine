#!/usr/bin/env bash

command_help() {

    show_banner

    cat <<EOF
Usage:
    theme <command>

Commands:
    help
    version
    status
    doctor
    list
    current
    set <theme-id>
    install <owner/repo[@commit-sha]> [--theme <relative-file>]
    wallpaper help|list|current|random|set <file>
    palette generate
    render <module>
    import analyze|preview <source> [--theme <relative-file>]
    import convert <source> <new-output-directory> [--theme <relative-file>]
    import install <pack-directory>

Source: owner/repo[@commit-sha], HTTPS GitHub URL, or local path.
Install converts one complete theme candidate and never activates it. Multiple
theme files require --theme with an exact relative path; preview lists candidates.
If no convertible candidate exists, a valid native pack at the repository root
can be installed as-is. Installation refuses an existing theme ID.
Preview prints the exact commit SHA to reuse for conversion. Import stages do not activate a theme.
Use an absolute path or ./relative-path for a local source.
EOF

}
