# External theme importer

The import pipeline has four separate user actions:

1. `theme import analyze <owner/repo|GitHub HTTPS URL|local-directory> [--theme <relative-file>]` prints JSON inventory.
2. `theme import preview <source> [--theme <relative-file>]` prints a readable conversion plan.
3. `theme import convert <source> <new-output-directory> [--theme <relative-file>]` writes a native pack for review.
4. `theme import install <pack-directory>` validates and publishes a reviewed pack to `themes/<id>` without activating it.

Only a later `theme set <id>` activates an installed pack. Local sources use absolute or `./relative` paths and are read without a network request; a local Git HEAD is recorded if available, otherwise the revision is `unversioned`. Local content must remain unchanged during each command. GitHub commands resolve the default branch to a commit SHA, then request that SHA's archive. Each invocation retrieves independently; use the `owner/repo@<40-character-lowercase-SHA>` reference printed by preview to convert the same revision later. A failed pinned retrieval does not fall back to a branch. Converted packs preserve source and license evidence in `source.json`.

`theme install owner/repo[@SHA] [--theme <relative-file>]` is the explicit one-command GitHub path. It retrieves once, analyzes and previews that pinned checkout, converts a single supported candidate in private staging, validates it, and installs it into `themes/<id>` without activating it. A repository with several complete candidates requires the exact `--theme` path; the command prints candidates and a pinned reference on failure. With one candidate it converts automatically. With no convertible candidate, a valid native `theme.conf` and `palette.conf` at the repository root can be installed as-is. Native packs retain their upstream files; converted packs include generated `source.json` evidence. Neither path overwrites an installed theme. A repository without a supported candidate or valid native root pack fails without installation. The command does not install local directories; use `theme import convert` and `theme import install` for local sources.

## Source and scan boundaries

Accepted remote forms are `owner/repo`, `owner/repo@<40-character-lowercase-SHA>`, `https://github.com/owner/repo`, and `https://github.com/owner/repo.git`. Absolute local directories and `./relative` local directories are also accepted. Query strings, fragments, credentials, other hosts, branches, tags, archives, and GitHub Enterprise hosts are rejected. The importer uses the GitHub REST API to resolve the default branch commit, then requests its tarball by exact SHA. It accepts only the expected HTTPS redirect to `codeload.github.com` for that SHA. It never runs Git hooks, scripts, submodules, build tools, or source commands. Python's HTTPS certificate checks remain enabled.

The retrieval helper enforces these limits while reading or extracting:

| Resource | Limit | Enforcement |
| --- | ---: | --- |
| Commit API response body | 64 KiB | Stream stops at limit |
| Downloaded archive body | 16 MiB | Stream stops at limit, even without `Content-Length` |
| Sum of declared archive file sizes | 32 MiB | Checked before each member is extracted |
| Any archive file | 8 MiB | Checked before extraction |
| Candidate theme file | 256 KiB | Checked before extraction |
| Sum of candidate theme files | 4 MiB | Checked before extraction |
| Archive files / directories / all members | 2,000 / 2,000 / 4,000 | Checked per member |
| Path depth below archive root | 8 | Checked per member |
| Retrieval time | 60 seconds in Python, 75 second outer process limit | Monotonic checks; outer `timeout` interrupts blocking operations |
| Analysis | 2,000 files and directories each; 256 KiB per candidate; 4 MiB total candidate text; 10 seconds | Scanner checks during traversal and reading |
| Captured license evidence | Four regular UTF-8 files, up to 32 KiB each | Larger or additional files are flagged for review |

The archive body is the strict bound for temporary compressed disk use; extracted candidates are bounded to 4 MiB plus directory and metadata overhead. Archive headers, TLS traffic, and HTTP headers are not individually byte counted. The outer 75 second limit is the process cap; individual network reads may exceed the Python 60 second deadline before the next check. Noncandidate archive members count toward declared checkout and file limits but are never written to disk. Symlinks and hard links are skipped; special files, unsafe paths, and duplicate members fail retrieval. Stage files use private directories, `O_NOFOLLOW`, and directory file descriptors. Normal failures and handled signals clean the stage. A force kill or power failure may leave a private temporary directory for manual cleanup.

Source files are never sourced or executed. The analyzer reads only UTF-8 text. It recognizes:

| Format | Accepted color form | Notes |
| --- | --- | --- |
| Kitty `.conf` | `background #RRGGBB`, `foreground`, `cursor`, `selection_*`, `color0..15` | ANSI indices remain raw; no invented semantic role |
| CSS | `--name: #RRGGBB;` and `@define-color name #RRGGBB;` | Applies to recognized GTK, Waybar, Wofi, SwayNC, and general CSS files |
| Simple palette `.conf` or `.theme` | `KEY=#RRGGBB` in palette/colors filenames | Includes raw `COLOR0` through `COLOR15` |
| Hyprlock `.conf` | `name = rgba(RRGGBBff)` | Opaque values only; `background.color` maps to `BACKGROUND` |

The analyzer ignores CSS comments and quoted strings when finding declarations. It does not resolve CSS variables, gradients, alpha expressions, shell variables, templates, short hex, named colors, or arbitrary source scripts. Files with unsupported formats contribute no roles. A source that contains colors is not evidence that its full application style is portable.

## Intermediate representation and mapping

The JSON report has `schema: 1`, `source_kind`, `source_url`, `repository`, `revision`, `inventory`, `theme_candidates`, `selected_candidate`, `semantic_roles`, `conflicts`, `skipped`, `unsupported_constructs`, `license_files`, `licenses`, `license_status`, and scan limits. Each inventory entry records path, format, application hint, extracted named colors, local semantic candidates, and confidence (`high` or `raw_colors_only`). Every semantic candidate records its source path, original key, and value. Exact aliases in `engine/importer/analyze.py` map to native roles; `color4`, for example, is not guessed to mean `PRIMARY`. A role enters top-level `semantic_roles` only when all candidates in its scope agree. Conflicts list every disagreement with provenance. Duplicate keys and malformed literals are reported. Unsupported literal forms are reported with path, construct name, and reason.

## Repositories with several themes

A candidate is one supported `.conf`, `.css`, or `.theme` file with an unambiguous `BACKGROUND` and `FOREGROUND`. The importer lists each candidate by exact repository-relative path, filename stem, format, and required colors. If two or more candidates exist, top-level roles and raw ANSI colors remain empty until a file is selected; conversion fails with a selection instruction. Candidate filenames can repeat in different directories, so selectors must use the exact path shown by preview. Absolute paths, traversal, symlinks, missing files, unsupported formats, and files without both required roles are refused.

For example, the Catppuccin Kitty repository has independent `themes/frappe.conf`, `themes/latte.conf`, `themes/macchiato.conf`, and `themes/mocha.conf` files. To review and convert Mocha while keeping a fixed revision:

```sh
engine/bin/theme import preview catppuccin/kitty
engine/bin/theme import preview catppuccin/kitty@43098316202b84d6a71f71aaf8360f102f4d3f1a --theme themes/mocha.conf
engine/bin/theme import convert catppuccin/kitty@43098316202b84d6a71f71aaf8360f102f4d3f1a /tmp/catppuccin-kitty-mocha --theme themes/mocha.conf
```

Use the SHA actually printed by your preview; the example SHA is one observed revision and may later be unavailable. Selecting a candidate scopes semantic roles, raw ANSI colors, detected format, and conversion warnings to that file. The pack's `source.json` records the selected path, name, format, original repository and revision, and global license evidence. The generated theme ID includes the source path and a short path digest so files with the same basename remain distinct. Selection does not establish a license or redistribution permission. With exactly one full candidate, the existing convenient behavior remains: nonconflicting supplementary role files may contribute colors. If they conflict, conversion still requires resolving the conflict.

Preview shows recognized and missing roles, candidate names and paths, conflicts, skipped files, license status, planned files, existing theme ID conflicts once a candidate is known, a pinned reference, and whether conversion is ready. Conversion requires unambiguous `BACKGROUND` and `FOREGROUND`. Optional unambiguous roles are copied as literal colors; missing roles use native CWAL fallbacks when the pack is later applied. Conflicting roles are omitted. Raw ANSI indices are preserved with their source paths in `source.json`, without assigning semantic meaning. The output directory must be new and have no symlinked parent. Conversion writes `theme.conf`, `palette.conf`, and `source.json` into a private sibling directory, validates the native pack, then uses Linux `renameat2(RENAME_NOREPLACE)` to publish the completed directory exclusively. Explicit installation copies regular pack files into its own private sibling directory, revalidates them, and publishes with the same exclusive rename. Failed stages are removed; existing packs are never replaced. Neither operation applies or reloads a theme.

`source.json` records the canonical URL, exact commit SHA, retrieval method, archive URL and SHA-256 digest, detected formats, role and raw ANSI origins, warnings, and license hashes and text where captured. This is provenance evidence, not a signature or independent proof that the archive bytes match a Git tree. Repository metadata is untrusted. Native packs made from older reports may record `retrieval.method=unspecified`; only packs produced through bounded retrieval carry the pinned archive evidence.

License files beginning with `LICENSE` or `COPYING` are recorded. `source.json` keeps the total count and up to 64 paths. At most four regular UTF-8 files of at most 32 KiB each are captured with text and SHA-256 digests. The status is `missing`, `present_unverified`, `ambiguous_or_incomplete`, or `restrictive_terms_found`. Metadata validation rejects a status that conflicts with the captured evidence. The last status is a keyword warning, not a legal conclusion. Multiple, oversized, unreadable, or excess license files require manual review. No detected file establishes redistribution permission; inspect upstream terms and attribution obligations before use.

## Example with disposable output

For a remote source, preview `owner/repo`, copy the exact `owner/repo@SHA` reference it prints, then pass that reference to `convert`. This keeps separate commands on the same commit. Review the generated pack before explicitly installing it.

```sh
engine/bin/theme import analyze ./downloaded-theme > /tmp/theme-analysis.json
engine/bin/theme import preview ./downloaded-theme
engine/bin/theme import convert ./downloaded-theme /tmp/review-this-pack
cat /tmp/review-this-pack/theme.conf /tmp/review-this-pack/palette.conf
python3 -m json.tool /tmp/review-this-pack/source.json
engine/bin/theme import install /tmp/review-this-pack
```

The final command installs into this checkout's `themes/`; use a disposable checkout for tests. Conversion output and reviewed pack paths can also use `./relative` paths. Analysis and conversion are tested with local Git repositories and mocked HTTPS responses, not live GitHub. A GitHub request may fail for network, authentication, rate limit, missing repository, redirect, size, or time reasons; the error reports the stage and the temporary data is cleaned on ordinary failure. An unpinned source can advance between separate invocations. A concurrent process with write access to source or destination parents can still race after the final identity check; directory file descriptors keep the operation in the opened parent, and publication refuses a collision. Conversion copies colors only; application CSS and settings are not copied. The retrieval and exclusive rename implementation targets Linux.
