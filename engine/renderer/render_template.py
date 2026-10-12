#!/usr/bin/env python3
"""Render Xcalibur templates from validated palette data, without sourcing it."""

import os
import re
import stat
import sys
import tempfile
from pathlib import Path


COLORS = {"BACKGROUND", "FOREGROUND", "CURSOR", *(f"COLOR{n}" for n in range(16)),
          "PRIMARY", "SECONDARY", "ACCENT", "SUCCESS", "WARNING", "ERROR", "MUTED",
          "SURFACE", "SURFACE_ALT", "BORDER", "SELECTION", "HIGHLIGHT"}
KEYS = COLORS | {"WALLPAPER"}
ASSIGNMENT = re.compile(r'^([A-Z][A-Z0-9_]*)="([^"]*)"$')
PLACEHOLDER = re.compile(r"\{\{([A-Z][A-Z0-9_]*)\}\}")
HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")


def regular(path: Path, limit: int) -> None:
    mode = path.lstat().st_mode
    if not stat.S_ISREG(mode) or path.stat().st_size > limit:
        raise ValueError(f"expected a bounded regular file: {path}")


def palette(path: Path) -> dict[str, str]:
    regular(path, 65536)
    values = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        match = ASSIGNMENT.fullmatch(line)
        if not match:
            raise ValueError(f"malformed generated palette line: {path}")
        key, value = match.groups()
        if key not in KEYS or key in values:
            raise ValueError(f"unknown or duplicate generated palette key: {key}")
        if key == "WALLPAPER":
            if not value.startswith("/") or any(char in value for char in ('\\', '$', '`', '\r', '\n')):
                raise ValueError("unsafe wallpaper path in generated palette")
        elif not HEX.fullmatch(value):
            raise ValueError(f"invalid generated color: {key}")
        values[key] = value
    if values.keys() != KEYS:
        raise ValueError("generated palette is missing required values")
    return values


def render(template: Path, colors: Path, output: Path) -> None:
    regular(template, 1024 * 1024)
    values = palette(colors)
    source = template.read_text(encoding="utf-8")

    def replacement(match: re.Match) -> str:
        key = match.group(1)
        if key not in values:
            raise ValueError(f"unknown template placeholder: {key}")
        return values[key]

    rendered = PLACEHOLDER.sub(replacement, source)
    if "{{" in rendered or "}}" in rendered:
        raise ValueError(f"unresolved template placeholder: {template}")
    if output.is_symlink() or not output.parent.is_dir():
        raise ValueError(f"unsafe render destination: {output}")
    fd, temporary = tempfile.mkstemp(prefix=".xcalibur-render.", dir=output.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(rendered)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, output)
    finally:
        if os.path.lexists(temporary):
            os.unlink(temporary)


def validate_outputs(directory: Path) -> None:
    if not directory.is_dir() or directory.is_symlink():
        raise ValueError(f"unsafe preparation directory: {directory}")
    palette(directory / "colors.sh")
    for output in directory.iterdir():
        regular(output, 1024 * 1024)
        if output.name == "colors.sh":
            continue
        content = output.read_text(encoding="utf-8")
        if not content or "{{" in content or "}}" in content or "\x00" in content:
            raise ValueError(f"invalid prepared output: {output}")


if __name__ == "__main__":
    try:
        if len(sys.argv) == 3 and sys.argv[1] == "validate":
            validate_outputs(Path(sys.argv[2]))
        elif len(sys.argv) == 4:
            render(*(Path(argument) for argument in sys.argv[1:]))
        else:
            raise ValueError("usage: render_template.py TEMPLATE COLORS OUTPUT | validate DIRECTORY")
    except (OSError, ValueError, UnicodeError) as error:
        print(f"theme renderer: {error}", file=sys.stderr)
        raise SystemExit(1)
