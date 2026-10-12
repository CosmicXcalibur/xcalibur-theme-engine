#!/usr/bin/env python3
"""Convert the official Nord src/nord.css color variables to a native pack."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from common import AdapterError, MAX_INPUT_BYTES, normalize_hex, read_source, write_pack


SEMANTIC_COLOR_MAP = (
    ("BACKGROUND", "0"),
    ("FOREGROUND", "6"),
    ("CURSOR", "6"),
    ("PRIMARY", "8"),
    ("SECONDARY", "10"),
    ("ACCENT", "7"),
    ("SUCCESS", "14"),
    ("WARNING", "13"),
    ("ERROR", "11"),
    ("MUTED", "4"),
    ("SURFACE", "1"),
    ("SURFACE_ALT", "2"),
    ("BORDER", "3"),
    ("SELECTION", "2"),
    ("HIGHLIGHT", "9"),
)


def convert(input_path: Path, output_dir: Path) -> None:
    source = read_source(input_path)
    # Nord publishes one :root rule of literal hex variables plus CSS comments.
    without_comments = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    root = re.fullmatch(r"\s*:root\s*\{(.*?)\}\s*", without_comments, flags=re.DOTALL)
    if root is None:
        raise AdapterError("invalid Nord CSS: expected one :root color block")

    declarations = root.group(1).split(";")
    if declarations[-1].strip():
        raise AdapterError("invalid Nord CSS: unterminated declaration")

    source_colors: dict[str, str] = {}
    for declaration in declarations[:-1]:
        match = re.fullmatch(r"\s*--nord(1[0-5]|[0-9])\s*:\s*(\S+)\s*", declaration)
        if match is None:
            raise AdapterError("invalid Nord CSS color declaration")
        number, value = match.groups()
        if number in source_colors:
            raise AdapterError(f"duplicate Nord color: nord{number}")
        try:
            source_colors[number] = normalize_hex(value)
        except AdapterError as error:
            raise AdapterError(f"invalid hex value for Nord color: nord{number}") from error

    expected = {str(number) for number in range(16)}
    if set(source_colors) != expected:
        missing = ", ".join(f"nord{number}" for number in range(16) if str(number) not in source_colors)
        raise AdapterError(f"missing required Nord colors: {missing}")

    selected = {role: source_colors[number] for role, number in SEMANTIC_COLOR_MAP}
    write_pack(
        output_dir,
        "nord",
        "Nord",
        "1.0.0",
        "Nord",
        "Nord color palette",
        selected,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Convert the official Nord src/nord.css to an Xcalibur theme pack."
    )
    parser.add_argument("--input", required=True, type=Path, help="src/nord.css path")
    parser.add_argument("--output", required=True, type=Path, help="new output directory")
    parser.epilog = f"Input size limit: {MAX_INPUT_BYTES} bytes (1 MiB)."
    arguments = parser.parse_args(argv)

    try:
        convert(arguments.input, arguments.output)
    except AdapterError as error:
        print(f"nord adapter: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
