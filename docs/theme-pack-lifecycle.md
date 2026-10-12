# Theme-pack lifecycle

Installed packs live directly beneath `themes/<theme-id>/` and contain exactly
`theme.conf` and `palette.conf`. Native GitHub packs and Catppuccin, Rosé Pine,
and Nord imports all pass through the same native installer. Installation does
not select or apply a theme. The active ID is recorded separately in
`runtime/state/current_theme`.
The state file contains one valid theme ID, optionally followed by a newline,
and is limited to 256 bytes.

## Commands

```bash
theme list
theme current
theme info catppuccin-mocha
theme validate catppuccin-mocha
theme validate --all
theme set catppuccin-mocha
theme remove nord
```

`theme list` shows each library entry's ID, display name, version, active
status, and validation status. Damaged packs remain visible with a reason.
An active status of `?` means the current-theme state is missing or malformed.
An empty library says `No themes installed.`. Listing returns zero when it can
read the library, including when some entries are invalid.

`theme info <theme-id>` prints the metadata, installation path, definition
version, defined semantic roles, and validation status. It exits nonzero and
reports the offending path when the pack is invalid or missing. Metadata is
displayed as data: printable ASCII remains readable, while control and
non-ASCII bytes are escaped for terminal safety.

`theme validate <theme-id>` checks one installed pack. `theme validate --all`
checks every direct library entry, continues after failures, prints individual
results and a checked/valid/invalid summary, and exits nonzero if any entry is
invalid. Inspection and validation do not change themes or runtime state.

`theme remove <theme-id>` removes a direct, inactive theme directory. It
rejects invalid IDs, missing entries, symlinked paths, and non-directory
entries. It refuses the active pack and refuses all removal when the active
state is missing, malformed, symlinked, or points to a missing/unsafe pack.
Select another valid theme with `theme set` before removing the active one.
Removal does not change state, select another pack, or apply a theme. A
malformed inactive pack can be removed once the active state is sound. A
filesystem deletion failure is reported; deletion is not atomic and may have
removed part of the target before failing.

All lifecycle commands use one installed-pack check. It requires a real theme
library and pack directory, exactly two readable regular non-symlink files,
an ID matching the directory, and successful native manifest and palette
parsing. The parsers reject missing, duplicate, unknown, or malformed fields,
unsupported definition versions, and invalid semantic colors or aliases.
`theme set` checks these invariants before writing active state, and the color
overlay checks them again before using a selected pack. This is structural
validation: it does not authenticate a remote repository, prove artistic
quality, or guarantee that an application can render every palette role.
Downloaded manifests and palettes are parsed as data and never sourced or
executed. The installer copies only the two native files, creates the
destination exclusively, and cleans a partial destination created by that
attempt on failure. The theme library should remain a trusted local directory;
do not let another user modify it concurrently with theme management.
Theme application uses the staged filesystem transaction described in
[transactions and recovery](transactions.md).

## Tests

From the repository root:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_*.py'
PYTHONDONTWRITEBYTECODE=1 bash tests/test_theme_install.sh
PYTHONDONTWRITEBYTECODE=1 bash tests/test_theme_lifecycle.sh
```

The shell tests use temporary theme libraries and local adapter fixtures. They
do not touch the installed themes or active state in your home directory.
