# External theme adapters

External adapters turn official, structured palettes into Xcalibur's native
`theme.conf` and `palette.conf`. Installation always passes those two generated
files through the same manifest and definition validators used for a native
theme pack. Importing a theme does not select or apply it.

## Commands and verified sources

| Format | Official repository and consumed input | Variants | Example |
| --- | --- | --- | --- |
| Native | Any valid `<owner/repo>` containing root `theme.conf` and `palette.conf` | None | `theme install owner/repo` |
| Catppuccin | [`catppuccin/palette`](https://github.com/catppuccin/palette), root `palette.json` | `latte`, `frappe`, `macchiato`, `mocha` | `theme install catppuccin/palette --format catppuccin --variant mocha` |
| Rosé Pine | [`rose-pine/rose-pine-palette`](https://github.com/rose-pine/rose-pine-palette/blob/main/palette.json), root `palette.json` with arrays of `{role, hex}` colors | `main`, `moon`, `dawn` | `theme install rose-pine/rose-pine-palette --format rose-pine --variant moon` |
| Nord | [`nordtheme/nord`](https://github.com/nordtheme/nord/blob/develop/src/nord.css), `src/nord.css` with sixteen literal `--nordN` hex variables | One palette; omit `--variant` | `theme install nordtheme/nord --format nord` |

The Catppuccin, Rosé Pine, and Nord input paths and values above were checked
against the official repositories on 2026-10-12. Their test fixtures keep the
consumed color fields and source structure, omitting unrelated upstream metadata and
Nord's long explanatory comments. Catppuccin's input version comes from its
JSON. The consumed Rosé Pine JSON and Nord CSS contain no version field, so
their native packs use `THEME_VERSION=1.0.0` to identify this adapter mapping
revision; it is not an upstream release number.

The CLI requires an explicit variant for Catppuccin and Rosé Pine. It rejects
variants for Nord, unknown options, duplicate options, unsupported formats,
and repositories outside each adapter's verified source.

## Color mapping

All output colors are validated six digit hex values with an uppercase `#`.
Each adapter writes `XCALIBUR_DEFINITION_VERSION=1` and only the semantic roles
accepted by the native definition validator.

| Xcalibur role | Catppuccin `colors` key | Rosé Pine `role` | Nord CSS variable |
| --- | --- | --- | --- |
| `BACKGROUND` | `base` | `base` | `nord0` |
| `FOREGROUND` | `text` | `text` | `nord6` |
| `CURSOR` | `rosewater` | `rose` | `nord6` |
| `PRIMARY` | `blue` | `foam` | `nord8` |
| `SECONDARY` | `mauve` | `iris` | `nord10` |
| `ACCENT` | `lavender` | `rose` | `nord7` |
| `SUCCESS` | `green` | `pine` | `nord14` |
| `WARNING` | `yellow` | `gold` | `nord13` |
| `ERROR` | `red` | `love` | `nord11` |
| `MUTED` | `subtext1` | `muted` | `nord4` |
| `SURFACE` | `mantle` | `surface` | `nord1` |
| `SURFACE_ALT` | `surface0` | `overlay` | `nord2` |
| `BORDER` | `surface1` | `subtle` | `nord3` |
| `SELECTION` | `overlay2` | `overlay` | `nord2` |
| `HIGHLIGHT` | `lavender` | `iris` | `nord9` |

Rosé Pine's root `palette.json` has no literal highlight colors, although its
other outputs describe highlight roles. The adapter uses `overlay` for
selection and `iris` for highlighting; these are approximations. Its `rose`
accent also serves as cursor. Nord is a sixteen color palette without
application semantic roles, so the mapping chooses contrasting Snow Storm
text, Polar Night surfaces, Frost accents, and Aurora status colors. Unused
source colors are not exported as extra native roles. Xcalibur's CWAL derived
raw `COLOR0` through `COLOR15` values remain unchanged; a selected theme only
overlays the semantic roles when the normal apply pipeline runs.

## Adapter contract

1. Add one entry to `theme_install_adapter_spec()` in
   `engine/lib/theme_install.sh`: format name, exact official repository,
   repository relative input path, local converter filename, and allowed
   variants. An empty variant list means no `--variant` option.
2. Put the converter in `engine/lib/adapters/`. It receives `--input PATH` and
   `--output PATH`, plus `--variant NAME` when the source has variants. The
   converter parses only the declared data file and writes a new native pack.
3. Use `common.py` for bounded regular file reads, duplicate safe JSON parsing
   when applicable, hex normalization, and exclusive pack creation. Source
   specific parsing and the semantic mapping remain in the converter.
4. Add a local fixture based on the current official format and tests for every
   variant, invalid data, and full installation. The native installer validates
   both generated files, installs only those files, and cleans staging on every
   result.

The installer checks each input path component for symlinks. Converters do not
execute repository code or load repository modules. JSON is parsed by Python's
standard library with duplicate keys and non finite numbers rejected, and CSS
accepts only Nord's literal hex declarations. Input is capped at 1 MiB, JSON
nesting is capped at 128 levels, and malformed data fails before output
creation. New pack
and installed theme directories use exclusive creation, so existing data is
never overwritten. Failed installation removes only a destination created by
that attempt. Clone, conversion, and copy failures clean their temporary
staging directory. Remote scripts, templates, configs, and other files are
never installed or executed.

## Tests

From the repository root:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_*.py'
bash tests/test_theme_install.sh
while IFS= read -r file; do bash -n "$file" || exit 1; done < <(rg --files -g '*.sh' engine tests)
PYTHONPYCACHEPREFIX=/tmp/xcalibur-python-cache python3 -m py_compile engine/lib/adapters/*.py tests/*.py
git diff --check
```

The ordinary tests use local fixtures and mock `git clone`; they do not need
GitHub access or change the active theme.
