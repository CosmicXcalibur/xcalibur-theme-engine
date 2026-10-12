"""Shared boundaries for data-only external palette converters."""

from __future__ import annotations

import json
import math
import os
import re
import stat
from pathlib import Path
from typing import Any


MAX_INPUT_BYTES = 1_048_576
MAX_JSON_DEPTH = 128
HEX_COLOR_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")
THEME_ID_RE = re.compile(r"^[a-z0-9]+(?:[a-z0-9-]*[a-z0-9])?$")
ROLES = (
    "BACKGROUND", "FOREGROUND", "CURSOR", "PRIMARY", "SECONDARY", "ACCENT",
    "SUCCESS", "WARNING", "ERROR", "MUTED", "SURFACE", "SURFACE_ALT",
    "BORDER", "SELECTION", "HIGHLIGHT",
)


class AdapterError(Exception):
    """Invalid source data or an unsafe output request."""


def read_source(path: Path) -> str:
    """Read one bounded regular file without following its final symlink."""
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise AdapterError(f"cannot open {path.name}: {error.strerror or error}") from error

    try:
        with os.fdopen(descriptor, "rb") as source_file:
            file_info = os.fstat(source_file.fileno())
            if not stat.S_ISREG(file_info.st_mode):
                raise AdapterError(f"{path.name} must be a regular file")
            if file_info.st_size > MAX_INPUT_BYTES:
                raise AdapterError(f"{path.name} exceeds the {MAX_INPUT_BYTES}-byte size limit")
            raw_data = source_file.read(MAX_INPUT_BYTES + 1)
            if len(raw_data) > MAX_INPUT_BYTES:
                raise AdapterError(f"{path.name} exceeds the {MAX_INPUT_BYTES}-byte size limit")
    except AdapterError:
        raise
    except OSError as error:
        raise AdapterError(f"cannot read {path.name}: {error.strerror or error}") from error

    try:
        return raw_data.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        raise AdapterError(f"invalid UTF-8 in {path.name}: {error}") from error


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise AdapterError(f"duplicate JSON object key: {key!r}")
        result[key] = value
    return result


def _reject_constant(value: str) -> None:
    raise AdapterError(f"unsupported JSON value: {value}")


def _finite_float(value: str) -> float:
    parsed = float(value)
    if not math.isfinite(parsed):
        raise AdapterError("unsupported non-finite JSON number")
    return parsed


def _check_json_depth(source: str, filename: str) -> None:
    depth = 0
    in_string = False
    escaped = False
    for character in source:
        if in_string:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
        elif character == '"':
            in_string = True
        elif character in "[{":
            depth += 1
            if depth > MAX_JSON_DEPTH:
                raise AdapterError(f"invalid {filename}: JSON nesting exceeds the supported depth")
        elif character in "]}":
            depth -= 1


def read_json(path: Path) -> dict[str, Any]:
    source = read_source(path)
    _check_json_depth(source, path.name)
    try:
        data = json.loads(
            source,
            object_pairs_hook=_unique_object,
            parse_constant=_reject_constant,
            parse_float=_finite_float,
        )
    except AdapterError:
        raise
    except (json.JSONDecodeError, ValueError) as error:
        raise AdapterError(f"invalid {path.name}: {error}") from error
    except RecursionError as error:
        raise AdapterError(f"invalid {path.name}: JSON nesting exceeds the supported depth") from error

    if not isinstance(data, dict):
        raise AdapterError(f"{path.name} must contain a JSON object at its root")
    return data


def normalize_hex(value: object) -> str:
    if not isinstance(value, str) or not HEX_COLOR_RE.fullmatch(value):
        raise AdapterError(f"invalid hex color: {value!r}")
    return value.upper()


def write_pack(
    output_dir: Path,
    theme_id: str,
    name: str,
    version: str,
    author: str,
    description: str,
    colors: dict[str, str],
) -> None:
    if not THEME_ID_RE.fullmatch(theme_id):
        raise AdapterError("invalid generated theme ID")
    for field in (name, version, author, description):
        if not field or any(ord(char) < 32 or ord(char) == 127 for char in field):
            raise AdapterError("invalid generated theme metadata")
    if set(colors) != set(ROLES):
        raise AdapterError("generated palette has missing or unknown semantic roles")
    normalized = {role: normalize_hex(colors[role]) for role in ROLES}

    manifest = (
        f"THEME_ID={theme_id}\n"
        f"THEME_NAME={name}\n"
        f"THEME_VERSION={version}\n"
        f"THEME_AUTHOR={author}\n"
        f"THEME_DESCRIPTION={description}\n"
    )
    definition = "\n".join(
        ["# Xcalibur normalized theme definition", "XCALIBUR_DEFINITION_VERSION=1"]
        + [f"{role}={normalized[role]}" for role in ROLES]
    ) + "\n"

    created_files: list[Path] = []
    created_directory = False
    try:
        output_dir.mkdir(mode=0o700)
        created_directory = True
        for filename, contents in (("theme.conf", manifest), ("palette.conf", definition)):
            destination = output_dir / filename
            with destination.open("x", encoding="utf-8", newline="\n") as output_file:
                created_files.append(destination)
                output_file.write(contents)
    except OSError as error:
        for created_file in created_files:
            try:
                created_file.unlink()
            except OSError:
                pass
        if created_directory:
            try:
                output_dir.rmdir()
            except OSError:
                pass
        raise AdapterError(f"cannot write native theme pack: {error.strerror or error}") from error
