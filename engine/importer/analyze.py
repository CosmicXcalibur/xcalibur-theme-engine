#!/usr/bin/env python3
"""Bounded, read-only inventory of external theme colors.

Adapters extract data only. No source configuration is executed or copied.
"""

import json
import os
import re
import stat
import sys
import time
from pathlib import Path

MAX_FILES = 2000
MAX_DEPTH = 8
MAX_FILE_SIZE = 256 * 1024
MAX_TOTAL_BYTES = 4 * 1024 * 1024
MAX_SECONDS = 10
HEX = re.compile(r"^#[0-9a-fA-F]{6}$")
KITTY = re.compile(r"^\s*(background|foreground|cursor|selection_background|selection_foreground|color(?:[0-9]|1[0-5]))\s+(\S+)")
CSS = re.compile(r"(?:^|[;\s])(?:--([a-zA-Z][\w-]*)\s*:|@define-color\s+([a-zA-Z][\w-]*)\s+)([^;\n]+)")
PALETTE = re.compile(r"^\s*([A-Z][A-Z_]*)=(\S+)\s*$")
ROLES = {
    "background": "BACKGROUND", "bg": "BACKGROUND", "base": "BACKGROUND",
    "foreground": "FOREGROUND", "fg": "FOREGROUND", "text": "FOREGROUND",
    "cursor": "CURSOR", "primary": "PRIMARY", "secondary": "SECONDARY",
    "accent": "ACCENT", "success": "SUCCESS", "warning": "WARNING",
    "error": "ERROR", "muted": "MUTED", "surface": "SURFACE",
    "surface_alt": "SURFACE_ALT", "border": "BORDER",
    "selection": "SELECTION", "selection_background": "SELECTION",
    "highlight": "HIGHLIGHT",
}


def normalize_color(value):
    value = value.strip().strip("'\"")
    return value.upper() if HEX.fullmatch(value) else None


def application(path):
    parts = path.lower().split("/")
    for name in ("kitty", "waybar", "wofi", "swaync", "hyprlock", "gtk-3.0", "gtk-4.0"):
        if name in parts or name in parts[-1]:
            return "gtk" if name.startswith("gtk-") else name
    return None


def adapter(path, content):
    lower = path.lower()
    if lower.endswith(".css"):
        colors = {}
        for match in CSS.finditer(content):
            name = (match.group(1) or match.group(2)).lower().replace("-", "_")
            color = normalize_color(match.group(3))
            if color:
                colors[name] = color
        return "css", colors
    if lower.endswith(".conf") or lower.endswith(".theme"):
        kitty = {}
        palette = {}
        for line in content.splitlines():
            match = KITTY.match(line)
            if match:
                color = normalize_color(match.group(2))
                if color:
                    kitty[match.group(1)] = color
            match = PALETTE.match(line)
            if match:
                color = normalize_color(match.group(2))
                if color:
                    palette[match.group(1).lower()] = color
        if kitty and ("kitty" in lower or len(kitty) >= 3):
            return "kitty", kitty
        if palette and ("palette" in lower or "colors" in lower):
            return "palette", palette
    return None, {}


def analyze(root, repository, revision):
    started = time.monotonic()
    report = {
        "schema": 1,
        "repository": repository,
        "revision": revision,
        "retrieval": "complete",
        "mode": "analysis_only",
        "limits": {"files": MAX_FILES, "depth": MAX_DEPTH, "file_bytes": MAX_FILE_SIZE,
                   "total_bytes": MAX_TOTAL_BYTES, "seconds": MAX_SECONDS},
        "inventory": [], "semantic_roles": {}, "conflicts": [], "skipped": [],
        "license_files": [], "application_configs_converted": 0,
        "theme_pack_generated": False, "installed": False, "applied": False,
    }
    candidates = {}
    files = 0
    total_bytes = 0
    for current, dirs, names in os.walk(root, followlinks=False):
        relative_dir = Path(current).relative_to(root)
        depth = len(relative_dir.parts)
        safe_dirs = []
        for directory in sorted(dirs):
            if directory == ".git":
                continue
            child = Path(current) / directory
            if child.is_symlink():
                report["skipped"].append({"path": child.relative_to(root).as_posix(),
                                          "reason": "symlink_directory"})
            else:
                safe_dirs.append(directory)
        dirs[:] = safe_dirs
        if depth >= MAX_DEPTH:
            if dirs:
                report["skipped"].append({"path": str(relative_dir), "reason": "depth_limit"})
            dirs.clear()
        for name in sorted(names):
            if time.monotonic() - started > MAX_SECONDS:
                raise ValueError("analysis time limit exceeded")
            files += 1
            if files > MAX_FILES:
                raise ValueError("file count limit exceeded")
            path = Path(current) / name
            relative = path.relative_to(root).as_posix()
            if name.lower().startswith(("license", "copying")):
                report["license_files"].append(relative)
            try:
                info = path.lstat()
            except OSError:
                report["skipped"].append({"path": relative, "reason": "unreadable"})
                continue
            if not stat.S_ISREG(info.st_mode):
                report["skipped"].append({"path": relative, "reason": "not_regular_file"})
                continue
            if info.st_size > MAX_FILE_SIZE:
                report["skipped"].append({"path": relative, "reason": "file_size_limit"})
                continue
            if not name.lower().endswith((".css", ".conf", ".theme")):
                continue
            total_bytes += info.st_size
            if total_bytes > MAX_TOTAL_BYTES:
                raise ValueError("total analysis byte limit exceeded")
            try:
                content = path.read_text(encoding="utf-8")
            except (OSError, UnicodeError):
                report["skipped"].append({"path": relative, "reason": "unreadable_text"})
                continue
            kind, colors = adapter(relative, content)
            if not kind or not colors:
                continue
            roles = {}
            for key, color in colors.items():
                role = ROLES.get(key)
                if role:
                    roles[role] = color
                    candidates.setdefault(role, []).append({"value": color, "path": relative, "key": key})
            report["inventory"].append({
                "path": relative, "format": kind, "application": application(relative),
                "colors": colors, "semantic_roles": roles,
                "confidence": "high" if roles else "raw_colors_only",
            })
    for role, sources in sorted(candidates.items()):
        values = {source["value"] for source in sources}
        if len(values) == 1:
            report["semantic_roles"][role] = sources[0]
        else:
            report["conflicts"].append({"role": role, "sources": sources})
    report["files_examined"] = files
    report["license_status"] = "review_required"
    return report


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit("usage: analyze.py <checkout> <repository> <revision>")
    try:
        print(json.dumps(analyze(Path(sys.argv[1]), sys.argv[2], sys.argv[3]), indent=2, sort_keys=True))
    except ValueError as exc:
        print(f"Import analysis failed: {exc}", file=sys.stderr)
        sys.exit(1)
