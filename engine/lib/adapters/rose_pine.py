#!/usr/bin/env python3
"""Convert the official Rosé Pine palette.json into a native pack."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from common import AdapterError, MAX_INPUT_BYTES, normalize_hex, read_json, write_pack


VARIANT_NAMES = {
    "main": "Rosé Pine",
    "moon": "Rosé Pine Moon",
    "dawn": "Rosé Pine Dawn",
}

SEMANTIC_COLOR_MAP = (
    ("BACKGROUND", "base"),
    ("FOREGROUND", "text"),
    ("CURSOR", "rose"),
    ("PRIMARY", "foam"),
    ("SECONDARY", "iris"),
    ("ACCENT", "rose"),
    ("SUCCESS", "pine"),
    ("WARNING", "gold"),
    ("ERROR", "love"),
    ("MUTED", "muted"),
    ("SURFACE", "surface"),
    ("SURFACE_ALT", "overlay"),
    ("BORDER", "subtle"),
    ("SELECTION", "overlay"),
    ("HIGHLIGHT", "iris"),
)
BARE_HEX_RE = re.compile(r"^[0-9A-Fa-f]{6}$")


def convert(input_path: Path, variant: str, output_dir: Path) -> None:
    if variant not in VARIANT_NAMES:
        choices = ", ".join(VARIANT_NAMES)
        raise AdapterError(f"unknown variant '{variant}' (expected one of: {choices})")

    palette = read_json(input_path)
    entries = palette.get(variant)
    if not isinstance(entries, list):
        raise AdapterError(f"missing or invalid variant array: {variant}")

    source_colors: dict[str, str] = {}
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("role"), str):
            raise AdapterError(f"invalid color entry in variant: {variant}")
        role = entry["role"]
        if role in source_colors:
            raise AdapterError(f"duplicate color role: {role!r}")
        value = entry.get("hex")
        if not isinstance(value, str) or not BARE_HEX_RE.fullmatch(value):
            raise AdapterError(f"invalid hex value for color: {role!r}")
        source_colors[role] = normalize_hex(f"#{value}")

    selected: dict[str, str] = {}
    for role, source_role in SEMANTIC_COLOR_MAP:
        if source_role not in source_colors:
            raise AdapterError(f"variant '{variant}' is missing required color: {source_role}")
        selected[role] = source_colors[source_role]

    theme_id = "rose-pine" if variant == "main" else f"rose-pine-{variant}"
    write_pack(
        output_dir,
        theme_id,
        VARIANT_NAMES[variant],
        "1.0.0",
        "Rosé Pine",
        f"{VARIANT_NAMES[variant]} palette",
        selected,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Convert the official Rosé Pine palette.json to an Xcalibur theme pack."
    )
    parser.add_argument("--input", required=True, type=Path, help="root palette.json path")
    parser.add_argument("--variant", required=True, help="main, moon, or dawn")
    parser.add_argument("--output", required=True, type=Path, help="new output directory")
    parser.epilog = f"Input size limit: {MAX_INPUT_BYTES} bytes (1 MiB)."
    arguments = parser.parse_args(argv)

    try:
        convert(arguments.input, arguments.variant, arguments.output)
    except AdapterError as error:
        print(f"rose-pine adapter: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
