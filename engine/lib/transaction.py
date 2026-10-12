#!/usr/bin/env python3
"""Private, stdlib-only filesystem journal for theme application.

The Bash apply service owns the desktop workflow and holds an exclusive flock.
This helper owns snapshots, file replacement, rollback, and journal validation.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import shutil
import stat
import sys
import tempfile
from pathlib import Path


VERSION = 1
MAX_JOURNAL = 1_000_000
APP_PATHS = (
    "kitty/current-theme.conf",
    "kitty/kitty.conf",
    "waybar/styles/colors/xcalibur.css",
    "wofi/style.css",
    "gtk-3.0/gtk.css",
    "gtk-4.0/gtk.css",
    "hypr/hyprlock.conf",
    "hypr/hyprlock.conf.xcalibur-backup",
    "swaync/style.css",
    "swaync/style.css.xcalibur-backup",
)
ACTIVE = {"installing", "reloading", "committing", "rollback_failed"}
QUIET = {"preparing", "ready", "committed", "rolledback"}


class TransactionError(Exception):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise TransactionError(message)


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def bytes_digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def regular_or_absent(path: Path) -> bool:
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError:
        return False
    require(stat.S_ISREG(mode), f"unsafe filesystem object: {path}")
    return True


def real_directories(path: Path) -> None:
    """Reject existing symlinks and non-directories in every parent component."""
    parts = list(path.parents)
    for part in reversed(parts):
        if part == Path("/"):
            continue
        try:
            mode = part.lstat().st_mode
        except FileNotFoundError:
            continue
        require(stat.S_ISDIR(mode), f"unsafe directory component: {part}")


def root_check(root: Path, create: bool = False) -> None:
    require(root.is_absolute(), "transaction root must be absolute")
    real_directories(root)
    if create and not root.exists():
        root.mkdir(mode=0o700)
    require(root.exists() and stat.S_ISDIR(root.lstat().st_mode), f"unsafe transaction root: {root}")
    require(stat.S_IMODE(root.stat().st_mode) & 0o077 == 0, f"transaction root is not private: {root}")


def key_read(root: Path, create: bool = False) -> bytes:
    key_path = root / ".key"
    if create and not key_path.exists():
        try:
            fd = os.open(key_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        except FileExistsError:
            pass
        else:
            with os.fdopen(fd, "wb") as stream:
                stream.write(os.urandom(32))
                stream.flush()
                os.fsync(stream.fileno())
    require(regular_or_absent(key_path), f"missing transaction key: {key_path}")
    require(stat.S_IMODE(key_path.stat().st_mode) & 0o077 == 0, f"transaction key is not private: {key_path}")
    key = key_path.read_bytes()
    require(len(key) == 32, f"invalid transaction key: {key_path}")
    return key


def canonical(payload: dict) -> bytes:
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("ascii")


def journal_write(txn: Path, payload: dict) -> None:
    key = key_read(txn.parent)
    body = canonical(payload)
    envelope = {"payload": payload, "hmac": hmac.new(key, body, hashlib.sha256).hexdigest()}
    fd, temporary = tempfile.mkstemp(prefix=".journal.", dir=txn)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(canonical(envelope))
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, txn / "journal.json")
        directory_fd = os.open(txn, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if os.path.lexists(temporary):
            os.unlink(temporary)


def no_duplicate_keys(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        require(key not in result, f"duplicate journal key: {key}")
        result[key] = value
    return result


def allowed_dest(payload: dict, dest: str) -> bool:
    home = Path(payload["home"])
    generated = Path(payload["generated"])
    cwal = Path(payload["cwal"])
    target = Path(dest)
    if not target.is_absolute() or os.path.normpath(dest) != dest:
        return False
    states = {payload["theme_state"], payload["wallpaper_state"]}
    return dest in states or dest in {str(home / ".config" / name) for name in APP_PATHS} or (
        target.parent in {generated, cwal, cwal / "schemes"}
        and target != cwal / "schemes"
        and target.name != ""
        and all(char.isascii() and (char.isalnum() or char in "._-") for char in target.name)
    )


def validate_roots(payload: dict, txn: Path) -> None:
    runtime = txn.parent.parent
    home = Path(payload["home"])
    require(home.is_absolute() and os.path.normpath(str(home)) == str(home), "invalid home path in journal")
    require(payload["generated"] == str(runtime / "generated") and
            payload["theme_state"] == str(runtime / "state" / "current_theme") and
            payload["wallpaper_state"] == str(runtime / "state" / "current_wallpaper") and
            payload["cwal"] == str(home / ".cache" / "cwal"),
            "journal roots do not match Xcalibur destinations")


def journal_read(txn: Path, verify_snapshots: bool = True) -> dict:
    root = txn.parent
    root_check(root)
    require(txn.name.startswith("txn.") and txn.parent == root, f"invalid transaction path: {txn}")
    require(stat.S_ISDIR(txn.lstat().st_mode) and stat.S_IMODE(txn.stat().st_mode) & 0o077 == 0,
            f"unsafe transaction directory: {txn}")
    journal = txn / "journal.json"
    require(regular_or_absent(journal), f"missing journal: {journal}")
    require(journal.stat().st_size <= MAX_JOURNAL, f"oversized journal: {journal}")
    try:
        envelope = json.loads(journal.read_text(encoding="utf-8"), object_pairs_hook=no_duplicate_keys)
    except (ValueError, UnicodeError) as error:
        raise TransactionError(f"malformed or tampered journal: {journal}: {error}") from error
    require(isinstance(envelope, dict) and set(envelope) == {"payload", "hmac"}, "malformed journal envelope")
    payload = envelope["payload"]
    require(isinstance(payload, dict), "malformed journal payload")
    expected = hmac.new(key_read(root), canonical(payload), hashlib.sha256).hexdigest()
    require(isinstance(envelope["hmac"], str) and hmac.compare_digest(envelope["hmac"], expected),
            f"tampered journal: {journal}")
    require(set(payload) == {"version", "status", "home", "generated", "cwal", "theme_state",
                              "wallpaper_state", "entries", "created_dirs"}, "unexpected journal fields")
    require(payload["version"] == VERSION and payload["status"] in ACTIVE | QUIET, "unsupported journal state")
    for field in ("home", "generated", "cwal", "theme_state", "wallpaper_state"):
        require(isinstance(payload[field], str) and Path(payload[field]).is_absolute(), f"invalid journal {field}")
    validate_roots(payload, txn)
    require(isinstance(payload["entries"], list) and len(payload["entries"]) <= 100, "invalid journal entries")
    require(isinstance(payload["created_dirs"], list) and len(payload["created_dirs"]) <= 100, "invalid directory list")
    seen = set()
    for index, entry in enumerate(payload["entries"]):
        require(isinstance(entry, dict) and set(entry) == {"src", "dest", "original", "old_hash", "new_hash", "state_text"},
                "malformed journal entry")
        dest = entry["dest"]
        require(isinstance(dest, str) and allowed_dest(payload, dest) and dest not in seen, f"unsafe journal destination: {dest}")
        seen.add(dest)
        require(type(entry["original"]) is bool and isinstance(entry["new_hash"], str), "malformed journal hashes")
        require(entry["old_hash"] is None or isinstance(entry["old_hash"], str), "malformed old hash")
        require((entry["old_hash"] is not None) == entry["original"], "journal existence mismatch")
        if entry["src"] is None:
            require(dest in {payload["theme_state"], payload["wallpaper_state"]} and
                    isinstance(entry["state_text"], str), "invalid state entry")
            require(bytes_digest(entry["state_text"].encode()) == entry["new_hash"], "tampered state entry")
        else:
            require(isinstance(entry["src"], str) and entry["state_text"] is None,
                    "invalid file entry")
            require(entry["src"] == str(txn / "inputs" / str(index)), "invalid input path")
        if verify_snapshots and entry["original"] and payload["status"] not in {"preparing", "committed", "rolledback"}:
            backup = txn / "backups" / str(index)
            require(regular_or_absent(backup) and digest(backup) == entry["old_hash"],
                    f"missing or changed recovery snapshot: {backup}")
    for directory in payload["created_dirs"]:
        require(isinstance(directory, str) and Path(directory).is_absolute(), "invalid created directory")
        require(any(directory == str(Path(e["dest"]).parent) or Path(directory) in Path(e["dest"]).parents
                    for e in payload["entries"]), f"unowned directory: {directory}")
    return payload


def transactions(root: Path) -> list[Path]:
    if not root.exists():
        return []
    root_check(root)
    found = []
    for child in root.iterdir():
        if child.name in {".key", ".lock"}:
            require(regular_or_absent(child), f"unsafe transaction root entry: {child}")
        elif child.name.startswith("txn."):
            require(stat.S_ISDIR(child.lstat().st_mode), f"unsafe transaction entry: {child}")
            found.append(child)
        else:
            raise TransactionError(f"unexpected transaction root entry: {child}")
    return found


def create(root: Path, home: Path, generated: Path, cwal: Path, theme_state: Path, wallpaper_state: Path) -> Path:
    root_check(root, create=True)
    key_read(root, create=True)
    require(not transactions(root), "incomplete transaction exists; run theme recover")
    proposed = {"home": str(home), "generated": str(generated), "cwal": str(cwal),
                "theme_state": str(theme_state), "wallpaper_state": str(wallpaper_state)}
    validate_roots(proposed, root / "txn.validation")
    txn = Path(tempfile.mkdtemp(prefix="txn.", dir=root))
    os.chmod(txn, 0o700)
    (txn / "stage").mkdir(mode=0o700)
    (txn / "inputs").mkdir(mode=0o700)
    (txn / "backups").mkdir(mode=0o700)
    payload = {"version": VERSION, "status": "preparing", "home": str(home), "generated": str(generated),
               "cwal": str(cwal), "theme_state": str(theme_state), "wallpaper_state": str(wallpaper_state),
               "entries": [], "created_dirs": []}
    journal_write(txn, payload)
    return txn


def prepare(txn: Path, plan_file: Path, theme_id: str, wallpaper: str) -> None:
    payload = journal_read(txn)
    require(payload["status"] == "preparing", "transaction is not preparing")
    require(plan_file == txn / "plan.nul" and regular_or_absent(plan_file), "invalid plan file")
    chunks = plan_file.read_bytes().split(b"\0")
    require(chunks[-1] == b"" and len(chunks) % 2 == 1, "malformed transaction plan")
    pairs = list(zip(chunks[0:-1:2], chunks[1:-1:2]))
    require(len(pairs) <= 98, "too many transaction destinations")
    specs = [(os.fsdecode(source), os.fsdecode(dest), None) for source, dest in pairs]
    if theme_id != "-":
        require(theme_id.isascii() and theme_id.replace("-", "").isalnum(), "invalid theme state value")
        specs.append((None, payload["theme_state"], theme_id + "\n"))
    if wallpaper != "-":
        require("\n" not in wallpaper and "\0" not in wallpaper, "invalid wallpaper state value")
        specs.append((None, payload["wallpaper_state"], wallpaper + "\n"))
    seen = set()
    entries = []
    created = set()
    for index, (source, dest_text, state_text) in enumerate(specs):
        dest = Path(dest_text)
        require(dest.is_absolute() and os.path.normpath(dest_text) == dest_text and allowed_dest(payload, dest_text)
                and dest_text not in seen, f"unapproved destination: {dest_text}")
        seen.add(dest_text)
        real_directories(dest)
        original = regular_or_absent(dest)
        old_hash = None
        if original:
            backup = txn / "backups" / str(index)
            shutil.copy2(dest, backup, follow_symlinks=False)
            old_hash = digest(backup)
        parent = dest.parent
        while not parent.exists():
            created.add(str(parent))
            parent = parent.parent
        if source is None:
            require(dest_text in {payload["theme_state"], payload["wallpaper_state"]}, "unapproved state entry")
            new_hash = bytes_digest(state_text.encode())
            stored_source = None
        else:
            source_path = Path(source)
            require(source_path.is_absolute() and os.path.normpath(source) == source and
                    regular_or_absent(source_path), f"unsafe source: {source}")
            require(source_path.stat().st_size <= 16 * 1024 * 1024, f"oversized prepared source: {source}")
            real_directories(source_path)
            require(source_path.is_relative_to(txn / "stage") or
                    source in {str(Path(payload["home"]) / ".config" / name) for name in APP_PATHS},
                    f"source outside transaction stage: {source}")
            stored = txn / "inputs" / str(index)
            shutil.copy2(source_path, stored, follow_symlinks=False)
            new_hash = digest(stored)
            stored_source = str(stored)
        entries.append({"src": stored_source, "dest": dest_text, "original": original,
                        "old_hash": old_hash, "new_hash": new_hash, "state_text": state_text})
    payload["entries"] = entries
    payload["created_dirs"] = sorted(created, key=lambda item: (item.count("/"), item))
    payload["status"] = "ready"
    journal_write(txn, payload)


def ensure_parents(payload: dict) -> None:
    cache_root = Path(payload["home"]) / ".cache"
    for name in payload["created_dirs"]:
        directory = Path(name)
        real_directories(directory)
        if not directory.exists():
            mode = 0o700 if directory == cache_root or cache_root in directory.parents else 0o755
            directory.mkdir(mode=mode)
        require(stat.S_ISDIR(directory.lstat().st_mode), f"unsafe destination directory: {directory}")


def atomic_file(dest: Path, source: Path | None = None, data: bytes | None = None) -> None:
    real_directories(dest)
    require(not dest.is_symlink(), f"destination became a symlink: {dest}")
    fd, temporary = tempfile.mkstemp(prefix=".xcalibur-txn.", dir=dest.parent)
    try:
        if source is not None:
            os.close(fd)
            shutil.copy2(source, temporary, follow_symlinks=False)
            with open(temporary, "rb") as stream:
                os.fsync(stream.fileno())
        else:
            with os.fdopen(fd, "wb") as stream:
                stream.write(data if data is not None else b"")
                stream.flush()
                os.fsync(stream.fileno())
            os.chmod(temporary, 0o644)
        os.replace(temporary, dest)
    finally:
        if os.path.lexists(temporary):
            os.unlink(temporary)


def install(txn: Path) -> None:
    payload = journal_read(txn)
    require(payload["status"] == "ready", "transaction is not ready")
    payload["status"] = "installing"
    journal_write(txn, payload)
    ensure_parents(payload)
    for entry in payload["entries"]:
        if entry["src"] is None:
            continue
        dest = Path(entry["dest"])
        present = regular_or_absent(dest)
        require(present == entry["original"] and (not present or digest(dest) == entry["old_hash"]),
                f"destination changed before install: {dest}")
        source = Path(entry["src"])
        require(regular_or_absent(source) and digest(source) == entry["new_hash"], f"prepared input changed: {source}")
        atomic_file(dest, source=source)


def phase(txn: Path, status: str) -> None:
    payload = journal_read(txn)
    require(status == "reloading" and payload["status"] == "installing", "invalid transaction phase")
    payload["status"] = status
    journal_write(txn, payload)


def commit(txn: Path) -> None:
    payload = journal_read(txn)
    require(payload["status"] == "reloading", "transaction is not ready to commit")
    payload["status"] = "committing"
    journal_write(txn, payload)
    for entry in payload["entries"]:
        if entry["src"] is not None:
            continue
        dest = Path(entry["dest"])
        present = regular_or_absent(dest)
        require(present == entry["original"] and (not present or digest(dest) == entry["old_hash"]),
                f"state changed before commit: {dest}")
        atomic_file(dest, data=entry["state_text"].encode())


def cleanup(txn: Path) -> None:
    # Keep the authenticated journal until all other artifacts are gone. If a
    # snapshot or staged-file deletion fails, explicit recovery can retry.
    for name in ("stage", "inputs", "backups"):
        directory = txn / name
        if os.path.lexists(directory):
            require(stat.S_ISDIR(directory.lstat().st_mode), f"unsafe cleanup directory: {directory}")
            shutil.rmtree(directory)
    plan = txn / "plan.nul"
    if os.path.lexists(plan):
        require(regular_or_absent(plan), f"unsafe cleanup plan: {plan}")
        plan.unlink()
    journal = txn / "journal.json"
    require(regular_or_absent(journal), f"missing cleanup journal: {journal}")
    journal.unlink()
    txn.rmdir()


def finish(txn: Path) -> None:
    payload = journal_read(txn)
    require(payload["status"] == "committing", "transaction has not committed")
    payload["status"] = "committed"
    journal_write(txn, payload)
    cleanup(txn)


def rollback(txn: Path) -> None:
    payload = journal_read(txn)
    require(payload["status"] in ACTIVE | QUIET - {"committed", "rolledback"}, "transaction cannot be rolled back")
    errors = []
    if payload["status"] in ACTIVE:
        for index in reversed(range(len(payload["entries"]))):
            entry = payload["entries"][index]
            dest = Path(entry["dest"])
            try:
                real_directories(dest)
                present = regular_or_absent(dest)
                if present:
                    current_hash = digest(dest)
                    require(current_hash in {entry["new_hash"], entry["old_hash"]},
                            f"destination changed outside transaction: {dest}")
                elif entry["original"]:
                    raise TransactionError(f"original destination disappeared: {dest}")
                else:
                    continue
                if entry["original"]:
                    backup = txn / "backups" / str(index)
                    require(regular_or_absent(backup) and digest(backup) == entry["old_hash"],
                            f"snapshot missing or changed: {backup}")
                    atomic_file(dest, source=backup)
                else:
                    dest.unlink()
            except (OSError, TransactionError) as error:
                errors.append(f"{dest}: {error}")
        for name in reversed(payload["created_dirs"]):
            directory = Path(name)
            try:
                if directory.exists():
                    directory.rmdir()
            except OSError as error:
                errors.append(f"{directory}: {error}")
    if errors:
        payload["status"] = "rollback_failed"
        journal_write(txn, payload)
        raise TransactionError("rollback incomplete; recovery retained at " + str(txn) + ": " + "; ".join(errors))
    payload["status"] = "rolledback"
    journal_write(txn, payload)
    cleanup(txn)


def recover(root: Path, requested: str | None) -> None:
    found = transactions(root)
    if requested is None:
        require(len(found) == 1, "specify one transaction ID; use theme recover --list")
        txn = found[0]
    else:
        require(requested.startswith("txn.") and "/" not in requested and requested not in {".", ".."},
                "invalid transaction ID")
        txn = root / requested
        require(txn in found, f"transaction not found: {requested}")
    payload = journal_read(txn)
    if payload["status"] in {"committed", "rolledback"}:
        cleanup(txn)
    else:
        rollback(txn)


def main(argv: list[str]) -> int:
    try:
        command = argv[1]
        if command == "create" and len(argv) == 8:
            print(create(*(Path(item).absolute() for item in argv[2:8])))
        elif command == "prepare" and len(argv) == 6:
            prepare(Path(argv[2]), Path(argv[3]), argv[4], argv[5])
        elif command == "install" and len(argv) == 3:
            install(Path(argv[2]))
        elif command == "phase" and len(argv) == 4:
            phase(Path(argv[2]), argv[3])
        elif command == "commit" and len(argv) == 3:
            commit(Path(argv[2]))
        elif command == "finish" and len(argv) == 3:
            finish(Path(argv[2]))
        elif command == "rollback" and len(argv) == 3:
            rollback(Path(argv[2]))
        elif command == "check" and len(argv) == 3:
            found = transactions(Path(argv[2]))
            require(not found, "incomplete transaction exists: " + ", ".join(str(item) for item in found))
        elif command == "list" and len(argv) == 3:
            for txn in transactions(Path(argv[2])):
                payload = journal_read(txn, verify_snapshots=False)
                print(f"{txn.name}: {payload['status']}")
        elif command == "recover" and len(argv) in {3, 4}:
            recover(Path(argv[2]), argv[3] if len(argv) == 4 else None)
        else:
            raise TransactionError("invalid transaction helper arguments")
        return 0
    except (TransactionError, OSError, ValueError, KeyError, IndexError, json.JSONDecodeError) as error:
        print(f"theme transaction: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
