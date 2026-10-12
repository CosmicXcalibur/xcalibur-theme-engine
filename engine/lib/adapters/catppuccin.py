#!/usr/bin/env python3
"""Convert one official Catppuccin palette.json flavor to a native pack."""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import stat
import sys
from pathlib import Path
from typing import Any


# The official palette currently fits well below this limit. The bound is
# checked against both stat() and the bytes actually read.
MAX_INPUT_BYTES = 1_048_576

VARIANT_NAMES = {
    "latte": "Latte",
    "frappe": "Frappé",
    "macchiato": "Macchiato",
    "mocha": "Mocha",
}

SEMANTIC_COLOR_MAP = (
    ("BACKGROUND", "base"),
    ("FOREGROUND", "text"),
    ("CURSOR", "rosewater"),
    ("PRIMARY", "blue"),
    ("SECONDARY", "mauve"),
    ("ACCENT", "lavender"),
    ("SUCCESS", "green"),
    ("WARNING", "yellow"),
    ("ERROR", "red"),
    ("MUTED", "subtext1"),
    ("SURFACE", "mantle"),
    ("SURFACE_ALT", "surface0"),
    ("BORDER", "surface1"),
    ("SELECTION", "overlay2"),
    ("HIGHLIGHT", "lavender"),
)

HEX_COLOR_RE = re.compile(r"^#[0-9A-Fa-f]{6}$")
VERSION_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")


class AdapterError(Exception):
    """An invalid source palette or output request."""


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise AdapterError(f"duplicate JSON object key: {key}")
        result[key] = value
    return result


def _reject_json_constant(value: str) -> None:
    raise AdapterError(f"unsupported JSON value: {value}")


def _finite_json_float(value: str) -> float:
    parsed = float(value)
    if not math.isfinite(parsed):
        raise AdapterError("unsupported non-finite JSON number")
    return parsed


def _read_source(path: Path) -> dict[str, Any]:
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        file_descriptor = os.open(path, flags)
    except OSError as error:
        raise AdapterError(f"cannot open palette.json: {error.strerror or error}") from error

    try:
        with os.fdopen(file_descriptor, "rb") as source_file:
            file_info = os.fstat(source_file.fileno())
            if not stat.S_ISREG(file_info.st_mode):
                raise AdapterError("palette.json must be a regular file")
            if file_info.st_size > MAX_INPUT_BYTES:
                raise AdapterError(
                    f"palette.json exceeds the {MAX_INPUT_BYTES}-byte size limit"
                )

            raw_data = source_file.read(MAX_INPUT_BYTES + 1)
            if len(raw_data) > MAX_INPUT_BYTES:
                raise AdapterError(
                    f"palette.json exceeds the {MAX_INPUT_BYTES}-byte size limit"
                )
    except AdapterError:
        raise
    except OSError as error:
        raise AdapterError(f"cannot read palette.json: {error.strerror or error}") from error

    try:
        decoded = raw_data.decode("utf-8", errors="strict")
        palette = json.loads(
            decoded,
            object_pairs_hook=_unique_object,
            parse_constant=_reject_json_constant,
            parse_float=_finite_json_float,
        )
    except AdapterError:
        raise
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise AdapterError(f"invalid palette.json: {error}") from error
    except ValueError as error:
        raise AdapterError(f"invalid palette.json: {error}") from error
    except RecursionError as error:
        raise AdapterError("invalid palette.json: JSON nesting exceeds the supported depth") from error

    if not isinstance(palette, dict):
        raise AdapterError("palette.json must contain a JSON object at its root")
    return palette


def _validated_version(palette: dict[str, Any]) -> str:
    version = palette.get("version")
    if not isinstance(version, str) or len(version) > 64 or not VERSION_RE.fullmatch(version):
        raise AdapterError("source version must be a stable semantic version (MAJOR.MINOR.PATCH)")
    return version


def _selected_colors(palette: dict[str, Any], variant: str) -> dict[str, str]:
    if variant not in VARIANT_NAMES:
        choices = ", ".join(VARIANT_NAMES)
        raise AdapterError(f"unknown variant '{variant}' (expected one of: {choices})")

    flavor = palette.get(variant)
    if not isinstance(flavor, dict):
        raise AdapterError(f"missing or invalid flavor object: {variant}")

    colors = flavor.get("colors")
    if not isinstance(colors, dict):
        raise AdapterError(f"flavor '{variant}' must contain a colors object")

    selected: dict[str, str] = {}
    for _, color_name in SEMANTIC_COLOR_MAP:
        color = colors.get(color_name)
        if not isinstance(color, dict):
            raise AdapterError(f"flavor '{variant}' is missing required color: {color_name}")

        value = color.get("hex")
        if not isinstance(value, str) or not HEX_COLOR_RE.fullmatch(value):
            raise AdapterError(
                f"flavor '{variant}' has an invalid hex value for color: {color_name}"
            )
        selected[color_name] = value.upper()

    return selected


def _write_pack(output_dir: Path, variant: str, version: str, colors: dict[str, str]) -> None:
    display_name = f"Catppuccin {VARIANT_NAMES[variant]}"
    theme_id = f"catppuccin-{variant}"

    manifest = (
        f"THEME_ID={theme_id}\n"
        f"THEME_NAME={display_name}\n"
        f"THEME_VERSION={version}\n"
        "THEME_AUTHOR=Catppuccin\n"
        f"THEME_DESCRIPTION=Catppuccin {VARIANT_NAMES[variant]} palette\n"
    )
    definition_lines = [
        "# Xcalibur normalized theme definition",
        "XCALIBUR_DEFINITION_VERSION=1",
    ]
    definition_lines.extend(
        f"{role}={colors[color_name]}" for role, color_name in SEMANTIC_COLOR_MAP
    )
    definition = "\n".join(definition_lines) + "\n"

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


def convert(input_path: Path, variant: str, output_dir: Path) -> None:
    if variant not in VARIANT_NAMES:
        choices = ", ".join(VARIANT_NAMES)
        raise AdapterError(f"unknown variant '{variant}' (expected one of: {choices})")

    palette = _read_source(input_path)
    version = _validated_version(palette)
    colors = _selected_colors(palette, variant)
    _write_pack(output_dir, variant, version, colors)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Convert an official Catppuccin palette.json flavor to an Xcalibur theme pack."
    )
    parser.add_argument("--input", required=True, type=Path, help="root palette.json path")
    parser.add_argument("--variant", required=True, help="latte, frappe, macchiato, or mocha")
    parser.add_argument("--output", required=True, type=Path, help="new output directory")
    parser.epilog = f"Input size limit: {MAX_INPUT_BYTES} bytes (1 MiB)."
    arguments = parser.parse_args(argv)

    try:
        convert(arguments.input, arguments.variant, arguments.output)
    except AdapterError as error:
        print(f"catppuccin adapter: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
