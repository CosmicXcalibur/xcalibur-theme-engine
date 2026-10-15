# External theme importer

The import pipeline has four separate user actions:

1. `theme import analyze <owner/repo|GitHub HTTPS URL|local-directory>` prints JSON inventory.
2. `theme import preview <source>` prints a readable conversion plan.
3. `theme import convert <source> <new-output-directory>` writes a native pack for review.
4. `theme import install <pack-directory>` validates and copies a reviewed pack to `themes/<id>` without activating it.

Only a later `theme set <id>` activates an installed pack. Local sources use absolute or `./relative` paths and are read without a network clone; a local Git HEAD is recorded if available, otherwise the revision is `unversioned`. Local content must remain unchanged during each command. GitHub commands retrieve a fresh shallow checkout, so the revision may change between calls. Pinning a requested revision is unsupported. Converted packs preserve source and license evidence in `source.json`.

## Source and scan boundaries

Only `owner/repo`, `https://github.com/owner/repo[.git]`, absolute local directories, and `./relative` local directories are accepted. Query strings, fragments, credentials, other hosts, revision suffixes, and archives are rejected. Git prompts, global/system configuration, hooks, submodules, and file transport are disabled for clone. Clone has a 60 second timeout. The scanner visits at most 2,000 directories and 2,000 files, to depth 8; candidate files are at most 256 KiB each and 4 MiB total, with a 10 second scan limit. Symlinks and special files are skipped, and candidate files are opened with `O_NOFOLLOW`. Staging is cleaned on ordinary success, errors, and handled signals. Strict network byte and checkout disk quotas are not yet implemented. Concurrent replacement of a parent directory is a remaining race.

Source files are never sourced or executed. The analyzer reads only UTF-8 text. It recognizes:

| Format | Accepted color form | Notes |
| --- | --- | --- |
| Kitty `.conf` | `background #RRGGBB`, `foreground`, `cursor`, `selection_*`, `color0..15` | ANSI indices remain raw; no invented semantic role |
| CSS | `--name: #RRGGBB;` and `@define-color name #RRGGBB;` | Applies to recognized GTK, Waybar, Wofi, SwayNC, and general CSS files |
| Simple palette `.conf` or `.theme` | `KEY=#RRGGBB` in palette/colors filenames | Includes raw `COLOR0` through `COLOR15` |
| Hyprlock `.conf` | `name = rgba(RRGGBBff)` | Opaque values only; `background.color` maps to `BACKGROUND` |

The analyzer does not resolve CSS variables, gradients, alpha expressions, shell variables, templates, short hex, named colors, or arbitrary source scripts. Files with unsupported formats contribute no roles. A source that contains colors is not evidence that its full application style is portable.

## Intermediate representation and mapping

The JSON report has `schema: 1`, `source_kind`, `source_url`, `repository`, `revision`, `inventory`, `semantic_roles`, `conflicts`, `skipped`, `unsupported_constructs`, `license_files`, `licenses`, `license_status`, and scan limits. Each inventory entry records path, format, application hint, extracted named colors, local semantic candidates, and confidence (`high` or `raw_colors_only`). Every semantic candidate records its source path, original key, and value. Exact aliases in `engine/importer/analyze.py` map to native roles; `color4`, for example, is not guessed to mean `PRIMARY`. A role enters top-level `semantic_roles` only when all candidates agree. Conflicts list every disagreement with provenance. Duplicate keys and malformed literals are reported. Unsupported literal forms are reported with path, construct name, and reason.

Preview shows recognized and missing roles, conflicts, skipped files, license status, planned files, existing theme ID conflicts, and whether conversion is ready. Conversion requires unambiguous `BACKGROUND` and `FOREGROUND`. Optional unambiguous roles are copied as literal colors; missing roles use native CWAL fallbacks when the pack is later applied. Conflicting roles are omitted. Raw ANSI indices are preserved with their source paths in `source.json`, without assigning semantic meaning. The output directory must be new and have no symlinked parent. Linux exclusive atomic rename prevents an output collision during publication. `theme.conf`, `palette.conf`, and `source.json` contain only validated data. Explicit installation validates all three, claims the installed ID exclusively, and rolls back a failed copy. It does not apply or reload a theme.

License files beginning with `LICENSE` or `COPYING` are recorded. `source.json` keeps the total count and up to 64 paths. At most four regular UTF-8 files of at most 32 KiB each are captured with text and SHA-256 digests. The status is `missing`, `present_unverified`, `ambiguous_or_incomplete`, or `restrictive_terms_found`. The last status is a keyword warning, not a legal conclusion. Multiple, oversized, unreadable, or excess license files require manual review. No detected file establishes redistribution permission; inspect upstream terms and attribution obligations before use.

## Example with disposable output

```sh
engine/bin/theme import analyze ./downloaded-theme > /tmp/theme-analysis.json
engine/bin/theme import preview ./downloaded-theme
engine/bin/theme import convert ./downloaded-theme /tmp/review-this-pack
cat /tmp/review-this-pack/theme.conf /tmp/review-this-pack/palette.conf
python3 -m json.tool /tmp/review-this-pack/source.json
engine/bin/theme import install /tmp/review-this-pack
```

The final command installs into this checkout's `themes/`; use a disposable checkout for tests. Analysis and conversion are tested with local Git repositories and mocked Git, not live GitHub. Clone download size, repository changes between actions, and mixed variants in one repository remain limitations. A concurrent process with write access to source or destination parents can replace a path after validation. Conversion copies colors only; application CSS and settings are not copied.
