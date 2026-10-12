#!/usr/bin/env python3
"""Stage an idempotent Kitty theme include without executing config data."""

import os
import stat
import sys
import tempfile
from pathlib import Path


INCLUDE = b"include current-theme.conf"
MAX_CONFIG_SIZE = 1024 * 1024


def is_theme_include(line: bytes, include_paths: set[bytes]) -> bool:
    parts = line.strip().split(None, 1)
    if len(parts) != 2 or parts[0] != b"include":
        return False
    argument = parts[1]
    for path in include_paths:
        if argument == path:
            return True
        if argument.startswith(path):
            suffix = argument[len(path):]
            if suffix[:1] in (b" ", b"\t") and suffix.lstrip(b" \t").startswith(b"#"):
                return True
    return False


def check_parents(path: Path) -> None:
    for parent in reversed(path.parents):
        try:
            mode = parent.lstat().st_mode
        except FileNotFoundError:
            continue
        if not stat.S_ISDIR(mode):
            raise ValueError(f"unsafe Kitty config directory: {parent}")


def prepare(main_config: Path, staged_config: Path) -> None:
    check_parents(main_config)
    check_parents(staged_config)
    try:
        info = main_config.lstat()
    except FileNotFoundError:
        contents = b""
        mode = 0o644
    else:
        if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_CONFIG_SIZE:
            raise ValueError(f"unsafe or oversized Kitty config: {main_config}")
        contents = main_config.read_bytes()
        mode = stat.S_IMODE(info.st_mode)
    if b"\0" in contents:
        raise ValueError(f"invalid NUL byte in Kitty config: {main_config}")

    include_paths = {
        b"current-theme.conf",
        b"./current-theme.conf",
        os.fsencode(main_config.parent / "current-theme.conf"),
    }
    lines = contents.splitlines(keepends=True)
    included_at = []
    for index, line in enumerate(lines):
        if is_theme_include(line, include_paths):
            included_at.append(index)
    if len(included_at) > 1:
        raise ValueError(f"duplicate Kitty theme includes: {main_config}")
    # Keep an existing final include byte-for-byte. If other settings follow
    # it, move the include to the end so those settings cannot override colors.
    if not included_at or included_at[0] != len(lines) - 1:
        if included_at:
            include_line = lines[included_at[0]]
            contents = b"".join(line for index, line in enumerate(lines) if index != included_at[0])
        else:
            include_line = INCLUDE + b"\n"
        if contents and not contents.endswith(b"\n"):
            contents += b"\n"
        contents += include_line
        if not contents.endswith(b"\n"):
            contents += b"\n"

    if os.path.lexists(staged_config):
        raise ValueError(f"Kitty staged config already exists: {staged_config}")
    fd, temporary = tempfile.mkstemp(prefix=".kitty-config.", dir=staged_config.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(contents)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, staged_config)
    finally:
        if os.path.lexists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    try:
        if len(sys.argv) != 3:
            raise ValueError("usage: prepare_config.py MAIN_CONFIG STAGED_CONFIG")
        prepare(Path(sys.argv[1]), Path(sys.argv[2]))
    except (OSError, ValueError) as error:
        print(f"Kitty config preparation: {error}", file=sys.stderr)
        raise SystemExit(1)
