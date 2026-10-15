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
    install <owner/repo>
    wallpaper help|list|current|random|set <file>
    palette generate
    render <module>
    import analyze|preview <source> [--theme <relative-file>]
    import convert <source> <new-output-directory> [--theme <relative-file>]
    import install <pack-directory>

Source: owner/repo[@commit-sha], HTTPS GitHub URL, or local path.
For multiple theme files, preview lists candidates; select one by exact relative path.
Preview prints the exact commit SHA to reuse for conversion. Import stages do not activate a theme.
Use an absolute path or ./relative-path for a local source.
EOF

}
