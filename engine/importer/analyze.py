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
MAX_DIRECTORIES = 2000
MAX_DEPTH = 8
MAX_FILE_SIZE = 256 * 1024
MAX_TOTAL_BYTES = 4 * 1024 * 1024
MAX_UNSUPPORTED = 2000
MAX_SECONDS = 10
HEX = re.compile(r"^#[0-9a-fA-F]{6}$")
KITTY = re.compile(r"^\s*(background|foreground|cursor|selection_background|selection_foreground|color(?:[0-9]|1[0-5]))\s+(\S+)")
CSS = re.compile(r"(?:^|[;\s])(?:--([a-zA-Z][\w-]*)\s*:|@define-color\s+([a-zA-Z][\w-]*)\s+)([^;\n]+)")
PALETTE = re.compile(r"^\s*([A-Z][A-Z_]*)=(\S+)\s*$")
HYPRLOCK_COLOR = re.compile(r"^[ \t]*([a-z][a-z_-]*)[ \t]*=[ \t]*rgba\(([0-9a-fA-F]{8})\)[ \t]*$", re.MULTILINE)
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
    if "hyprlock" in lower and lower.endswith(".conf"):
        colors = {}
        section = ""
        for line in content.splitlines():
            stripped = line.strip()
            if stripped.endswith("{"):
                section = stripped[:-1].strip().lower().replace("-", "_")
            elif stripped == "}":
                section = ""
            else:
                match = HYPRLOCK_COLOR.fullmatch(line)
                if match and match.group(2)[6:].lower() == "ff":
                    key = match.group(1).lower().replace("-", "_")
                    key = "background" if section == "background" and key == "color" else f"{section}_{key}".strip("_")
                    colors[key] = "#" + match.group(2)[:6].upper()
        return "hyprlock", colors
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


def unsupported_values(path, content, kind):
    if kind == "css":
        for match in CSS.finditer(content):
            if normalize_color(match.group(3)) is None:
                yield {"path": path, "construct": match.group(1) or match.group(2),
                       "reason": "unsupported_css_color_value"}
    elif kind == "hyprlock":
        for match in HYPRLOCK_COLOR.finditer(content):
            if match.group(2)[6:].lower() != "ff":
                yield {"path": path, "construct": match.group(1),
                       "reason": "nonopaque_hyprlock_color"}
    elif kind == "kitty":
        for line in content.splitlines():
            match = KITTY.match(line)
            if match and normalize_color(match.group(2)) is None:
                yield {"path": path, "construct": match.group(1),
                       "reason": "unsupported_kitty_color_value"}


def bounded_walk(root, report, started):
    pending = [root]
    visited = 0
    while pending:
        if time.monotonic() - started > MAX_SECONDS:
            raise ValueError("analysis time limit exceeded")
        current = pending.pop()
        visited += 1
        if visited > MAX_DIRECTORIES:
            raise ValueError("directory count limit exceeded")
        depth = len(current.relative_to(root).parts)
        try:
            with os.scandir(current) as scanner:
                entries = []
                for entry in scanner:
                    if time.monotonic() - started > MAX_SECONDS:
                        raise ValueError("analysis time limit exceeded")
                    entries.append(entry)
                    if len(entries) > MAX_FILES + MAX_DIRECTORIES:
                        raise ValueError("directory entry limit exceeded")
        except OSError as error:
            raise ValueError(f"unable to scan directory: {current}") from error
        directories = []
        names = []
        for entry in sorted(entries, key=lambda item: item.name):
            path = Path(current) / entry.name
            relative = path.relative_to(root).as_posix()
            if entry.name == ".git" and entry.is_dir(follow_symlinks=False):
                continue
            if entry.is_symlink() and entry.is_dir():
                report["skipped"].append({"path": relative, "reason": "symlink_directory"})
            elif entry.is_dir(follow_symlinks=False):
                if depth >= MAX_DEPTH:
                    report["skipped"].append({"path": relative, "reason": "depth_limit"})
                else:
                    directories.append(path)
            else:
                names.append(entry.name)
        pending.extend(reversed(directories))
        yield current, names


def analyze(root, repository, revision):
    started = time.monotonic()
    report = {
        "schema": 1,
        "repository": repository,
        "revision": revision,
        "retrieval": "complete",
        "mode": "analysis_only",
        "limits": {"files": MAX_FILES, "directories": MAX_DIRECTORIES,
                   "depth": MAX_DEPTH, "file_bytes": MAX_FILE_SIZE,
                   "total_bytes": MAX_TOTAL_BYTES, "seconds": MAX_SECONDS},
        "inventory": [], "semantic_roles": {}, "conflicts": [], "skipped": [],
        "unsupported_constructs": [],
        "license_files": [], "application_configs_converted": 0,
        "theme_pack_generated": False, "installed": False, "applied": False,
    }
    candidates = {}
    files = 0
    total_bytes = 0
    for current, names in bounded_walk(root, report, started):
        for name in names:
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
            try:
                descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
                try:
                    opened = os.fstat(descriptor)
                    if not stat.S_ISREG(opened.st_mode) or opened.st_size > MAX_FILE_SIZE:
                        report["skipped"].append({"path": relative, "reason": "changed_or_oversized"})
                        continue
                    chunks = []
                    remaining = MAX_FILE_SIZE + 1
                    while remaining:
                        chunk = os.read(descriptor, min(65536, remaining))
                        if not chunk:
                            break
                        chunks.append(chunk)
                        remaining -= len(chunk)
                    content_bytes = b"".join(chunks)
                finally:
                    os.close(descriptor)
                if len(content_bytes) > MAX_FILE_SIZE:
                    report["skipped"].append({"path": relative, "reason": "file_size_limit"})
                    continue
                total_bytes += len(content_bytes)
                if total_bytes > MAX_TOTAL_BYTES:
                    raise ValueError("total analysis byte limit exceeded")
                content = content_bytes.decode("utf-8")
            except (OSError, UnicodeError):
                report["skipped"].append({"path": relative, "reason": "unreadable_text"})
                continue
            kind, colors = adapter(relative, content)
            for item in unsupported_values(relative, content, kind):
                if len(report["unsupported_constructs"]) < MAX_UNSUPPORTED:
                    report["unsupported_constructs"].append(item)
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
