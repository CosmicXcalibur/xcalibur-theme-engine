# External theme importer

The import pipeline has four separate user actions:

1. `theme import analyze <owner/repo|GitHub HTTPS URL>` prints JSON inventory.
2. `theme import preview <source>` prints a readable conversion plan.
3. `theme import convert <source> <new-output-directory>` writes a native pack for review.
4. `theme import install <pack-directory>` validates and copies a reviewed pack to `themes/<id>` without activating it.

Only a later `theme set <id>` activates an installed pack. The first three commands retrieve a fresh shallow GitHub checkout, so the revision may change between calls. The analysis report records the exact commit. Pinning a requested revision is deliberately unsupported until safe, reproducible revision handling is implemented. A converted pack currently contains no provenance metadata beyond the generated owner/repository name; record the analysis JSON separately if precise attribution is needed.

## Source and scan boundaries

Only `owner/repo` and `https://github.com/owner/repo[.git]` are accepted. Query strings, fragments, credentials, other hosts, and revision suffixes are rejected. Git prompts, global/system configuration, hooks, submodules, and file transport are disabled for clone. Clone has a 60 second timeout. The scanner visits at most 2,000 directories and 2,000 files, to depth 8; candidate files are at most 256 KiB each and 4 MiB total, with a 10 second scan limit. Symlinks and special files are skipped, and candidate files are opened with `O_NOFOLLOW`. Staging is cleaned on ordinary success, errors, and handled signals. Strict network byte and checkout disk quotas are not yet implemented. Concurrent replacement of a parent directory is a remaining race.

Source files are never sourced or executed. The analyzer reads only UTF-8 text. It recognizes:

| Format | Accepted color form | Notes |
| --- | --- | --- |
| Kitty `.conf` | `background #RRGGBB`, `foreground`, `cursor`, `selection_*`, `color0..15` | ANSI indices remain raw; no invented semantic role |
| CSS | `--name: #RRGGBB;` and `@define-color name #RRGGBB;` | Applies to recognized GTK, Waybar, Wofi, SwayNC, and general CSS files |
| Simple palette `.conf` or `.theme` | `KEY=#RRGGBB` in palette/colors filenames | Only literal values |
| Hyprlock `.conf` | `name = rgba(RRGGBBff)` | Opaque values only; `background.color` maps to `BACKGROUND` |

The analyzer does not resolve CSS variables, gradients, alpha expressions, shell variables, templates, short hex, named colors, or arbitrary source scripts. Files with unsupported formats contribute no roles. A source that contains colors is not evidence that its full application style is portable.

## Intermediate representation and mapping

The JSON report has `schema: 1`, `repository`, `revision`, `inventory`, `semantic_roles`, `conflicts`, `skipped`, `unsupported_constructs`, `license_files`, and scan limits. Each inventory entry records path, format, application hint, extracted named colors, local semantic candidates, and confidence (`high` or `raw_colors_only`). Every semantic candidate records its source path, original key, and value. Exact aliases in `engine/importer/analyze.py` map to native roles; `color4`, for example, is not guessed to mean `PRIMARY`. A role enters top-level `semantic_roles` only when all candidates agree. Conflicts list every disagreement with provenance. Unsupported literal forms are reported with path, construct name, and reason.

Preview shows recognized roles, conflicts, skipped count, planned files, and whether conversion is ready. Conversion requires unambiguous `BACKGROUND` and `FOREGROUND`. Optional unambiguous roles are copied as literal colors; missing roles use native CWAL fallbacks when the pack is later applied. Conflicting roles are omitted. The output directory must be new and have no symlinked parent. `theme.conf` and `palette.conf` contain only validated data. After generation, the CLI runs the native pack parser on both files. Explicit installation uses the same parser, claims the installed ID exclusively, and rolls back a failed copy. It does not apply or reload a theme.

## Example with disposable output

```sh
engine/bin/theme import analyze owner/repo > /tmp/theme-analysis.json
engine/bin/theme import preview owner/repo
engine/bin/theme import convert owner/repo /tmp/review-this-pack
cat /tmp/review-this-pack/theme.conf /tmp/review-this-pack/palette.conf
engine/bin/theme import install /tmp/review-this-pack
```

Review license obligations before installing or redistributing. Analysis and conversion are tested with local fixtures and mocked Git, not live GitHub. Clone download size, repository changes between actions, and mixed variants in one repository remain limitations. Conversion copies colors only; application CSS and settings are not copied.
