#!/usr/bin/env python3
"""Install a self-contained checkout under an explicit user-writable prefix."""

import hashlib
import json
import os
import shutil
import stat
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OWNED = ("engine", "modules", "config", "themes", "docs", "README.md", "CHANGELOG.md")
MARKER = ".xcalibur-install.json"


def safe_existing_directory(path):
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError("prefix must be an absolute existing directory without '..'")
    current = Path("/")
    for part in path.parts[1:]:
        current /= part
        if current.is_symlink() or not current.is_dir():
            raise ValueError(f"unsafe or missing directory: {current}")


def digest(path):
    hasher = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(65536):
            hasher.update(chunk)
    return hasher.hexdigest()


def regular_files(root):
    result = {}
    directory_names = []
    for current, directories, files in os.walk(root, followlinks=False):
        for name in directories:
            path = Path(current) / name
            if path.is_symlink():
                raise ValueError(f"symlinked directory: {path}")
            directory_names.append(path.relative_to(root).as_posix())
        for name in files:
            path = Path(current) / name
            details = path.lstat()
            if not stat.S_ISREG(details.st_mode):
                raise ValueError(f"nonregular package file: {path}")
            relative = path.relative_to(root).as_posix()
            result[relative] = {"sha256": digest(path), "mode": stat.S_IMODE(details.st_mode)}
    return {"files": result, "directories": sorted(directory_names)}


def install(prefix):
    safe_existing_directory(prefix)
    share = prefix / "share"
    binary = prefix / "bin"
    for directory in (share, binary):
        if directory.exists():
            safe_existing_directory(directory)
        else:
            directory.mkdir()
    target = share / "xcalibur-theme-engine"
    link = binary / "theme"
    if target.exists() or target.is_symlink() or link.exists() or link.is_symlink():
        raise ValueError("installation destination or theme command already exists")
    stage = Path(tempfile.mkdtemp(prefix=".xcalibur-install-", dir=share))
    installed = False
    try:
        for entry in OWNED:
            source = ROOT / entry
            destination = stage / entry
            if source.is_dir():
                regular_files(source)
                shutil.copytree(source, destination, symlinks=False,
                                ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
            elif source.is_file() and not source.is_symlink():
                shutil.copy2(source, destination)
            else:
                raise ValueError(f"missing or unsafe package input: {source}")
        inventory = regular_files(stage)
        (stage / MARKER).write_text(json.dumps({"schema": 1, **inventory}, sort_keys=True))
        os.chmod(stage / MARKER, 0o644)
        if target.exists() or target.is_symlink():
            raise ValueError("installation destination appeared during staging")
        stage.rename(target)
        installed = True
        link.symlink_to(target / "engine/bin/theme")
    except Exception:
        if installed and target.is_dir() and not target.is_symlink() and not link.exists():
            shutil.rmtree(target)
        raise
    finally:
        if stage.exists():
            shutil.rmtree(stage)
    return target


def uninstall(prefix):
    safe_existing_directory(prefix)
    target = prefix / "share/xcalibur-theme-engine"
    link = prefix / "bin/theme"
    safe_existing_directory(prefix / "share")
    safe_existing_directory(prefix / "bin")
    if target.is_symlink() or not target.is_dir() or not link.is_symlink() or \
            os.readlink(link) != str(target / "engine/bin/theme"):
        raise ValueError("installation is absent or the command link is not engine-owned")
    marker = target / MARKER
    if marker.is_symlink() or not marker.is_file():
        raise ValueError("installation marker is missing or unsafe")
    manifest = json.loads(marker.read_text())
    if manifest.get("schema") != 1 or not isinstance(manifest.get("files"), dict) or \
            not isinstance(manifest.get("directories"), list):
        raise ValueError("invalid installation marker")
    current = regular_files(target)
    current["files"].pop(MARKER, None)
    if current != {"files": manifest["files"], "directories": manifest["directories"]}:
        raise ValueError("installed files changed or runtime data exists; uninstall refused")
    link.unlink()
    shutil.rmtree(target)
    return target


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("install", "uninstall"):
        raise ValueError("usage: package.py install|uninstall <absolute-existing-prefix>")
    prefix = Path(sys.argv[2])
    target = install(prefix) if sys.argv[1] == "install" else uninstall(prefix)
    print(f"{sys.argv[1].capitalize()}ed: {target}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, json.JSONDecodeError) as error:
        print(f"Packaging failed: {error}", file=sys.stderr)
        sys.exit(1)
