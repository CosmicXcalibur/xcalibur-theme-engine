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
    import analyze|preview <owner/repo|github-url|local-path>
    import convert <owner/repo|github-url|local-path> <new-output-directory>
    import install <pack-directory>

Import preview and convert do not install or activate a theme.
Use an absolute path or ./relative-path for a local source.
EOF

}
