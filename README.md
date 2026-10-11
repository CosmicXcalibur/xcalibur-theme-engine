# Xcalibur Theme Engine

A Bash theme engine for Hyprland. It generates a raw palette with CWAL, resolves the selected theme's semantic colors, renders engine-owned templates, and installs colors for Kitty, Waybar, Wofi, GTK 3/4, Hyprlock, and SwayNC. The project is under active development (CLI version 0.1.0).

## Setup

Run the CLI from this checkout with `engine/bin/theme`, or symlink that executable into your `PATH`. It resolves the engine root from its own location. Trusted engine settings live in `config/theme.conf`, `config/paths.conf`, and `config/applications.conf`; these files are sourced as Bash. Edit `WALLPAPER_DIR` in `config/paths.conf` for your wallpaper directory. Generated state stays under `runtime/` and is ignored by Git.

The wallpaper workflow needs CWAL, Hyprpaper, `hyprctl`, and ordinary shell utilities. `theme import analyze` additionally needs Git, Python 3, and `timeout`. Each enabled application needs its own installed configuration and reload tools. `theme doctor` prints a basic dependency check; it is diagnostic and does not repair settings.

The development checkout is separate from `~/.config/theme`. Running its CLI reads this checkout's config and runtime; a real `set` or `wallpaper set` still writes application files under `$HOME/.config`, so use the isolated tests for development.

## Commands

```text
theme help | version | status | doctor
theme list | current | set <theme-id> | install <owner/repo>
theme wallpaper help | list | current | random | set <file>
theme palette generate
theme render <module>
theme import analyze <owner/repo|https://github.com/owner/repo>
```

`wallpaper set` accepts a path relative to `WALLPAPER_DIR` or an absolute path to a readable PNG, JPEG, or WebP file. It asks Hyprpaper to change the wallpaper, records the path, then generates and applies colors. `palette generate` regenerates the runtime palette from the recorded wallpaper. `render` writes one generated module output and requires an existing runtime palette.

`theme set` validates an installed theme, generates colors from the recorded wallpaper, then renders all enabled modules before installing them. A render failure restores the previous selection and leaves live application files alone. An install or reload failure can leave some files changed; the new selection remains recorded and the command returns failure. Repeating `theme set <theme-id>` is the current recovery route. Multi-application installation is not atomic.

## Colors and theme packs

CWAL provides raw `COLOR0` through `COLOR15`, plus default background, foreground, and cursor. `themes/<id>/palette.conf` can map semantic roles to a raw color reference or a literal `#RRGGBB`. It does not alter the raw colors. The resolved palette is written to `runtime/generated/colors.sh` as validated color assignments. The engine parses this file as data when rendering and does not execute it.

A native theme pack has a root `theme.conf` and `palette.conf`. See `themes/xcalibur-test/` for a complete example. The manifest needs `THEME_ID`, `THEME_NAME`, `THEME_VERSION`, `THEME_AUTHOR`, and `THEME_DESCRIPTION`. The ID uses lowercase letters, digits, and internal hyphens. The palette starts with `XCALIBUR_DEFINITION_VERSION=1`; supported roles are `BACKGROUND`, `FOREGROUND`, `CURSOR`, `PRIMARY`, `SECONDARY`, `ACCENT`, `SUCCESS`, `WARNING`, `ERROR`, `MUTED`, `SURFACE`, `SURFACE_ALT`, `BORDER`, `SELECTION`, and `HIGHLIGHT`. Missing roles retain CWAL-based defaults. Duplicate or unknown fields and invalid values are rejected. Both files are parsed as data.

`theme install <owner/repo>` clones a native pack and installs only its validated root manifest and palette. It never activates the theme. It does not pin a revision or provide signatures, so the repository can change between installs. Existing installed IDs are protected from normal overwrite.

## External repository analysis

`theme import analyze` retrieves a public GitHub repository into a private temporary directory, scans nested files, and prints a JSON report. The first adapters recognize literal six-digit hexadecimal colors in Kitty assignments, CSS custom properties and `@define-color` definitions, and simple `KEY=#RRGGBB` palette files. The report includes paths, formats, extracted colors, candidate semantic roles, conflicts, skipped files, source revision, and license file names. Ambiguous roles are left unresolved. It does not generate, preview, install, or apply a theme pack, and it does not convert application settings or CSS styling. The command cleans staging on completion and failure, and reports cleanup errors.

The scanner limits traversal depth to 8, examined files to 2,000, individual files to 256 KiB, total candidate text to 4 MiB, and analysis to 10 seconds. Clone has a 60 second timeout. Clone download size is not yet bounded. Symlinks are not read. Attribution and redistribution require manual license review. The importer model and next stages are described in [docs/importer.md](docs/importer.md).

## Application file ownership

Modules render into `runtime/generated/` and then install these files:

| Module | Destination | Current reload behavior |
| --- | --- | --- |
| Kitty | `~/.config/kitty/current-theme.conf` | `kitty @ set-colors` |
| Waybar | `~/.config/waybar/styles/colors/xcalibur.css` | stop and start Waybar |
| Wofi | `~/.config/wofi/style.css` | stop running Wofi |
| GTK | `~/.config/gtk-3.0/gtk.css`, `~/.config/gtk-4.0/gtk.css` | request dark color scheme with `gsettings` |
| Hyprlock | `~/.config/hypr/hyprlock.conf` | no live reload |
| SwayNC | `~/.config/swaync/style.css` | stop and start SwayNC |

GTK, Wofi, Hyprlock, and SwayNC destinations are whole engine-managed files. Hyprlock and SwayNC make a one-time `.xcalibur-backup` of an existing target. Kitty and Waybar use dedicated generated files that other configuration must include or reference. `QT_ENABLED` exists in config but there is no Qt module or supported frontend; Qt is not themed.

## Tests and development

Run `bash tests/run.sh`. Tests use temporary directories and mocked service functions; they do not change the wallpaper or live application files. Run `bash -n` on changed Bash files for syntax checking. The repository is intended for the `codex/autonomous-dev` branch. Do not commit `runtime/` data. Contributions should keep theme packs as data, add fixtures for new source adapters, and document any new file ownership or reload behavior.

## Current limitations

Application installation is not transactional. Some reload methods can disrupt a running application and need refinement. Module enablement is a trusted Bash setting. Install paths reject pre-existing symlinked directory components, but Bash checks cannot close races with concurrent path replacement. The native installer claims theme IDs exclusively; an interrupted native install may still leave staging or a partial pack. The importer supports analysis only and cannot yet stage or preview a converted pack. A recognized color is evidence of compatibility, not proof that a full application configuration can be imported.
