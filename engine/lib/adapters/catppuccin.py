#!/usr/bin/env python3
"""Convert the official Catppuccin palette.json into a native pack."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from common import AdapterError, MAX_INPUT_BYTES, normalize_hex, read_json, write_pack


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

VERSION_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")


def convert(input_path: Path, variant: str, output_dir: Path) -> None:
    if variant not in VARIANT_NAMES:
        choices = ", ".join(VARIANT_NAMES)
        raise AdapterError(f"unknown variant '{variant}' (expected one of: {choices})")

    palette = read_json(input_path)
    version = palette.get("version")
    if not isinstance(version, str) or len(version) > 64 or not VERSION_RE.fullmatch(version):
        raise AdapterError("source version must be a stable semantic version (MAJOR.MINOR.PATCH)")

    flavor = palette.get(variant)
    if not isinstance(flavor, dict):
        raise AdapterError(f"missing or invalid flavor object: {variant}")
    colors = flavor.get("colors")
    if not isinstance(colors, dict):
        raise AdapterError(f"flavor '{variant}' must contain a colors object")

    selected: dict[str, str] = {}
    for role, color_name in SEMANTIC_COLOR_MAP:
        color = colors.get(color_name)
        if not isinstance(color, dict):
            raise AdapterError(f"flavor '{variant}' is missing required color: {color_name}")
        try:
            selected[role] = normalize_hex(color.get("hex"))
        except AdapterError as error:
            raise AdapterError(
                f"flavor '{variant}' has an invalid hex value for color: {color_name}"
            ) from error

    display_name = f"Catppuccin {VARIANT_NAMES[variant]}"
    write_pack(
        output_dir,
        f"catppuccin-{variant}",
        display_name,
        version,
        "Catppuccin",
        f"{display_name} palette",
        selected,
    )


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
