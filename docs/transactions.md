# Theme application transactions and recovery

`theme set <theme-id>` and `theme wallpaper set <file>` use one transaction.
The engine validates the selected pack and current state, generates cwal output
with `--out-dir` inside a private staging directory, renders every supported
module there, and validates the generated palette and rendered files. It then
snapshots all destinations before replacing any live file. Rendered palette
data and templates are parsed as data; they are never sourced as shell code.

The transaction covers the files Xcalibur writes: top-level cwal cache files,
regular files inside cwal's `schemes/` cache directory, all
`runtime/generated/` outputs, Kitty's theme fragment and main `kitty.conf`,
Waybar, Wofi, GTK 3 and 4, Hyprlock and
SwayNC configuration fragments, legacy Hyprlock and SwayNC backup files when
created, and the active theme or wallpaper state being changed. It records
which files existed, preserves existing file modes and timestamps for rollback,
and removes files and empty directories created by a failed attempt. The
`schemes/` directory itself is a container, not a replaceable file; its
unrelated entries remain untouched. Symlinked or unexpected cache objects are
rejected. A private journal under `runtime/transactions/` authenticates its
path list and snapshots;
the engine accepts only its known destination paths. The persistent `.key`
and `.lock` files in that directory support journal validation and serialized
applications.

After installation, the existing GTK, Kitty, SwayNC, Waybar, and Wofi reload
functions run. Kitty, SwayNC, Waybar, and Wofi report immediate reload errors;
the engine then restores files and state and exits nonzero. GTK's settings hint
is best effort, as before. Waybar and SwayNC launch in the background, so a
later process failure cannot be observed by this command. Hyprlock uses its new
file on its next launch and is not restarted. Wallpaper application
also reloads the wallpaper; if a later step fails, the engine attempts to
reload the previous wallpaper after restoring files. A running application
may already have observed new colors or a process restart. Restoring files
cannot reverse every external effect, and rollback does not kill or restart
applications to attempt that reversal.

Kitty's generated colors are installed as `~/.config/kitty/current-theme.conf`.
The engine stages a copy of the existing `kitty.conf`, preserving its settings
and file mode, and ensures one `include current-theme.conf` appears last so the
colors load on restart. Both files are snapshotted and rolled back together.
For the current Kitty instance, `kitty @ set-colors --all --configured` applies
the fragment to all its windows and its configured colors. The command must
be able to reach a Kitty instance with remote control enabled; a nonzero exit
causes transaction rollback. A live Kitty process may retain colors it saw
before rollback, as with other external reload effects.

The active state is written with an atomic file replacement only after the
required reload calls return successfully. A failed write, copy, directory
creation, rename, state update, or reload triggers rollback. The original
error and any rollback error are both reported. This is a filesystem rollback
contract, not a single atomic update across files or applications. Concurrent
non-Xcalibur writers, abrupt power loss, filesystem failure, and application
process state limit what can be guaranteed. The standalone `theme palette
generate` command retains its palette-only behavior and is outside this
application transaction.

## Incomplete transactions

An interrupted application leaves an authenticated journal under
`runtime/transactions/txn.*`. Another application refuses to start until it
is resolved. The engine never replays such a journal automatically.

```bash
theme recover --list
theme recover                 # recover the only transaction
theme recover txn.EXAMPLE     # select one when several exist
```

`theme recover` validates the private journal, approved paths, and snapshot
hashes before restoring. It rolls back a transaction that was still applying;
an already committed transaction only needs cleanup. If rollback succeeded
but cleanup failed and its journal remains, recovery retries cleanup. If a rollback write fails,
snapshots and the journal remain available for another recovery attempt.
The journal is deleted last during cleanup; interruption in the final unlink
and directory removal can leave an empty transaction directory that requires
manual inspection and removal.

If recovery reports a changed destination, unsafe path, missing snapshot, or
malformed/tampered journal, stop theme application. Inspect the reported
transaction directory and affected paths. Restore the named files from its
`backups/` copies only after confirming the journal's path mapping against
your own configuration; remove transaction-created files only when you have
confirmed they belong to that attempt. Keep the directory until files and
active state agree. A malformed journal is deliberately not repaired or
deleted by `theme recover`.

## Tests

```bash
PYTHONDONTWRITEBYTECODE=1 bash tests/test_theme_transaction.sh
PYTHONDONTWRITEBYTECODE=1 bash tests/test_theme_install.sh
PYTHONDONTWRITEBYTECODE=1 bash tests/test_theme_lifecycle.sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_*.py'
```

The transaction test uses a temporary home, mocked cwal output and reloads,
and injected failures. It does not touch the live desktop or installed themes.
