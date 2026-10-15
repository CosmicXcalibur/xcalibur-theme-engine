# Xcalibur Theme Engine

Xcalibur is a Bash theme engine for Hyprland desktops. It changes a Hyprpaper wallpaper, generates colors with CWAL, resolves semantic roles from a native theme pack, renders trusted templates, and installs styles for Kitty, Waybar, Wofi, GTK 3/4, Hyprlock, and SwayNC. It also analyzes public GitHub theme repositories and converts recognized colors into reviewable native packs. CLI version: `0.1.0`.

## Requirements and setup

Run `engine/bin/theme` from this checkout. The CLI locates its repository from its own path. Bash, GNU coreutils, and standard shell tools are required. `wallpaper set` needs `cwal`, `hyprctl`, a running Hyprpaper session, and `timeout`. Import analysis, preview, conversion, and native GitHub pack installation need Python 3 and `timeout`; local Git revision detection also uses Git when available. Installing a converted pack needs Python 3 for native validation and atomic publication. Application commands are needed only when their enabled integration reloads a running application. `theme doctor` distinguishes workflow requirements from optional tools.

To install a copy under an existing user-writable prefix, run `python3 scripts/package.py install "$HOME/.local"`. This creates `$HOME/.local/share/xcalibur-theme-engine` and a `$HOME/.local/bin/theme` symlink, refusing collisions. If `$HOME/.local` does not exist, create it first. `python3 scripts/package.py uninstall "$HOME/.local"` removes that copy only when its manifest, files, and command symlink match; it refuses to erase edits, added files, or runtime data. Keep the checkout for development and run `make check` there. Package installation requires Python 3 and does not modify application styles or desktop settings.

Engine settings in `config/theme.conf`, `config/paths.conf`, and `config/applications.conf` are parsed as data with a fixed key list. Edit `WALLPAPER_DIR` in `config/paths.conf` and module enablement in `config/applications.conf` to suit your desktop. The supported settings are `COLOR_ENGINE=cwal` and `WALLPAPER_BACKEND=hyprpaper`; unsupported values fail clearly. Qt has no integration; `QT_ENABLED` is reserved and has no effect. Native and imported theme data is also parsed and never sourced.

Generated output and persistent selection state live under `runtime/` inside the checkout and are ignored by Git. Direct `set` and `wallpaper set` commands install live files in your home directory; development tests use temporary homes and mocks. Running `make check` does not change your desktop or `~/.config/theme`.

## CLI reference

```text
theme help
theme version
theme status
theme doctor
theme list
theme current
theme set <theme-id>
theme install <owner/repo>
theme wallpaper help|list|current|random|set <file>
theme palette generate
theme render <module>
theme import analyze <source> [--theme <relative-file>]
theme import preview <source> [--theme <relative-file>]
theme import convert <source> <new-output-directory> [--theme <relative-file>]
theme import install <pack-directory>
```

`wallpaper set` accepts an absolute file path or a filename relative to `WALLPAPER_DIR`; PNG, JPEG, and WebP extensions are accepted. It uses the first monitor reported by `hyprctl monitors`, preloads the image, and asks Hyprpaper to set it. A successful wallpaper command runs the full palette and application pipeline and then records the wallpaper. On failure it attempts to restore the previously recorded wallpaper, runtime palette, and installed application files. If there was no previous wallpaper, it reports that manual wallpaper recovery may be needed.

`palette generate` only generates and validates `runtime/generated/colors.sh`; it does not install application styles. `render <module>` renders one module into `runtime/generated/` without installing it. `set <theme-id>` validates an installed pack, generates and applies its colors, and records the selection only after the application pipeline succeeds. `status` returns failure for malformed or missing referenced state. Usage errors and unknown commands return 2; operational failures return 1.

## Native theme packs and color rules

Each pack resides in `themes/<theme-id>/` with `theme.conf` and `palette.conf`. Each file is limited to 256 KiB. The lowercase ID contains letters, digits, and internal hyphens. `theme.conf` requires exactly one each of `THEME_ID`, `THEME_NAME`, `THEME_VERSION`, `THEME_AUTHOR`, and `THEME_DESCRIPTION`. Version uses `major.minor.patch` with an optional suffix. The ID must match the installed directory name. The files are simple `KEY=VALUE` data: blank lines and lines beginning with `#` are ignored; duplicate, unknown, empty, malformed, and control-character values are rejected. `palette.conf` starts with `XCALIBUR_DEFINITION_VERSION=1` and may specify any of the roles below as `COLOR0` through `COLOR15` or a literal `#RRGGBB`:

```text
BACKGROUND FOREGROUND CURSOR PRIMARY SECONDARY ACCENT SUCCESS WARNING ERROR
MUTED SURFACE SURFACE_ALT BORDER SELECTION HIGHLIGHT
```

CWAL's raw `COLOR0` through `COLOR15` values are copied into the runtime palette without changing their role or case. Default semantic mappings are: background, foreground, cursor from CWAL's corresponding values; primary=`COLOR4`, secondary=`COLOR5`, accent=`COLOR6`, success=`COLOR2`, warning=`COLOR3`, error=`COLOR1`, muted=`COLOR7`, surface=`COLOR2`, surface_alt=`COLOR3`, border=`COLOR4`, selection=`COLOR5`, and highlight=`COLOR6`. A pack overrides only roles it declares. Hex values are validated; the runtime palette is generated atomically and parsed as data by the renderer. See `themes/xcalibur-test` for a complete sample.

CWAL runs with an isolated config and output directory under `runtime/cache/`, `--no-reload`, and a 30 second timeout. This prevents an old user cache file from being mistaken for new output and avoids CWAL config links or scripts in the user's profile. The generated CWAL output is read as data, never executed. Supported CWAL arguments follow the [upstream CLI](https://github.com/nitinbhat972/cwal).

## Application files and reloads

| Module | Installed file | Reload behavior |
| --- | --- | --- |
| Kitty | `~/.config/kitty/current-theme.conf` | `kitty @ set-colors` if Kitty runs |
| Waybar | `~/.config/waybar/styles/colors/xcalibur.css` | SIGUSR2 if Waybar runs |
| Wofi | `~/.config/wofi/style.css` | Applied on next launch |
| GTK | `~/.config/gtk-3.0/gtk.css`, `~/.config/gtk-4.0/gtk.css` | Applied by GTK when loaded; global preferences are untouched |
| Hyprlock | `~/.config/hypr/hyprlock.conf` | Applied on next lock session |
| SwayNC | `~/.config/swaync/style.css` | `swaync-client -rs` if SwayNC runs |

The Waybar file must be imported by your Waybar stylesheet; the Kitty file must be included by Kitty to persist colors across launches. Other listed files are whole engine-managed targets. Existing Hyprlock and SwayNC files receive one-time `.xcalibur-backup` copies, except when the target exactly matches the engine's previously generated output. The installer checks for symlinked targets and parent directories and replaces individual files atomically. Before multi-module installation it snapshots known targets, including backup files, and attempts to restore them on install, reload, or state-commit failure. An incomplete rollback is reported as an error. Waybar uses its documented [SIGUSR2 reload](https://github.com/Alexays/Waybar/blob/master/man/waybar.5.scd.in); SwayNC uses its documented [CSS reload client](https://github.com/ErikReider/SwayNotificationCenter).

## External theme import and conversion

The importer accepts public `owner/repo` references, an optional exact SHA as `owner/repo@<40 lowercase hex characters>`, HTTPS GitHub repository URLs with an optional trailing `.git`, and local directories named with an absolute or `./relative` path. Local directories are read without a network request; a local Git HEAD is recorded when available, otherwise the revision is `unversioned`. Local sources must remain unchanged during each command. GitHub input rejects query strings, fragment revisions, other hosts, and malformed names. Remote retrieval resolves the default branch commit via GitHub's API, then downloads only that commit's archive through a validated HTTPS redirect. It limits the archive body to 16 MiB and declared checkout size to 32 MiB; see [importer limits](docs/importer.md) for the full table. Repository files are scanned as data only. Scripts, templates, Makefiles, hooks, and application commands from the source repository are never executed. Repositories with several complete theme files require `--theme <exact-relative-file>` for preview or conversion; the first preview lists candidates and a pinned reference to reuse.

Supported color forms are literal six-digit hex values in Kitty assignments, CSS custom properties and GTK `@define-color`, simple palette `KEY=#RRGGBB` files, and opaque `rgba(RRGGBBff)` fields in Hyprlock configuration. Named colors, CSS expressions, partial alpha, short hex, shell expansions, and arbitrary app settings are not converted. Semantic names map by exact documented aliases in `engine/importer/analyze.py`; conflicting candidates remain unresolved. Duplicate keys and malformed literal colors are reported. Analysis JSON contains source paths, format, application hint, confidence, candidates, conflicts, skipped files, revision, and license evidence. Preview lists roles, conflicts, missing roles, license status, planned files, and existing theme ID conflicts. Converted packs contain `theme.conf`, `palette.conf`, and validated `source.json` provenance; no application configuration is copied. Raw ANSI `COLOR0` through `COLOR15` values remain in `source.json` with their source paths; they are not reinterpreted as semantic roles.

```sh
engine/bin/theme import analyze owner/repo
engine/bin/theme import preview ./local-theme
engine/bin/theme import convert ./local-theme /tmp/review-local-theme
engine/bin/theme import install /tmp/review-local-theme
```

Conversion requires unambiguous `BACKGROUND` and `FOREGROUND`. Preview prints a pinned reference to reuse for a later conversion. Conversion validates a private staged pack and publishes the whole directory with an exclusive Linux rename; explicit `import install` revalidates and publishes in the same way. Both refuse collisions. Analysis, preview, conversion, and installation never apply a theme; only a later `theme set <id>` does that. The license status is a review prompt, not permission to redistribute. Live GitHub retrieval has not been verified in the deterministic suite; local Git repositories and mocked HTTPS responses are used. See [importer documentation](docs/importer.md).

## Security and limitations

Theme files, engine settings, and CWAL palettes are data only; bundled module scripts are trusted code. Import scanning skips symlinks and special files, caps directory depth at 8, directories and files at 2,000 each, individual files at 256 KiB, total candidate text at 4 MiB, and analysis time at 10 seconds. Remote retrieval limits downloaded archive bytes and declared checkout sizes, and uses a 75 second outer process cap. Bash path checks reject symlinked path components at check time, but concurrent replacement between checks and use remains possible. Import publication uses directory file descriptors and exclusive rename, yet a same-user process can still race after the final parent identity check. Run imports and installs where untrusted users cannot write parent directories. Rollback restores file content and ordinary mode bits but not ACLs, extended attributes, or already observed application state. Waybar user configuration can override SIGUSR2 behavior. Multiple monitor selection and non-Hyprpaper backends remain deferred. Qt is deferred until a concrete frontend and integration contract are chosen.

## Development, checks, and releases

`make check` is the authoritative local and CI command. It runs Bash and Python compilation checks, Python unit tests, CLI smoke tests, isolated Bash regressions, an isolated CLI integration test, a deliberate failure probe for the runner, `git diff --check`, and whitespace checks for new files. It prints `PASS`, `FAIL`, `SKIP`, and `UNAVAILABLE` with counts and returns nonzero if a required check fails. Tests use disposable directories, mocked commands, and no real desktop session or network. The CI workflow runs the same command. To contribute, add a deterministic fixture for each new adapter or failure path, update documentation, run `make check`, inspect the diff, and commit on a development branch. The current version is development version 0.1.0; a release requires a verified live desktop and GitHub integration pass.

For diagnostics, run `theme doctor` and `theme status`. If a reload fails, inspect the reported module and rerun `theme set <theme-id>` after fixing it. If rollback reports an error, inspect the listed application files and `.xcalibur-backup` files before retrying. See [roadmap](docs/roadmap.md) for outstanding work and [changelog](CHANGELOG.md) for changes.
