#!/usr/bin/env python3
"""Bounded, read-only inventory of external theme colors.

Adapters extract data only. No source configuration is executed or copied.
"""

import hashlib
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
MAX_LICENSE_SIZE = 32768
MAX_LICENSE_FILES = 4
HEX = re.compile(r"^#[0-9a-fA-F]{6}$")
KITTY = re.compile(r"^\s*(background|foreground|cursor|selection_background|selection_foreground|color(?:[0-9]|1[0-5]))\s+(\S+)")
CSS = re.compile(r"(?:^|[;\s])(?:--([a-zA-Z][\w-]*)\s*:|@define-color\s+([a-zA-Z][\w-]*)\s+)([^;\n]+)")
PALETTE = re.compile(r"^\s*([A-Z][A-Z0-9_]*)=(\S+)\s*$")
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
def validate_selector(selector):
    """A selector is one exact, repository-relative source file path."""
    if not isinstance(selector, str) or not selector or len(selector) > 1024 or \
            selector.startswith("/") or "\\" in selector or any(
                part in ("", ".", "..") for part in selector.split("/")) or any(
                ord(char) < 32 or ord(char) == 127 for char in selector) or \
            len(selector.split("/")) > MAX_DEPTH + 1 or \
            not selector.lower().endswith((".conf", ".css", ".theme")):
        raise ValueError("invalid theme selector; use an exact relative .conf, .css, or .theme file path")
    return selector


def normalize_color(value):
    value = value.strip().strip("'\"")
    return value.upper() if HEX.fullmatch(value) else None


def application(path):
    parts = path.lower().split("/")
    for name in ("kitty", "waybar", "wofi", "swaync", "hyprlock", "gtk-3.0", "gtk-4.0"):
        if name in parts or name in parts[-1]:
            return "gtk" if name.startswith("gtk-") else name
    return None


def adapter_detailed(path, content):
    lower = path.lower()
    occurrences = []
    diagnostics = []
    def record(colors, key, raw, kind):
        color = normalize_color(raw)
        if color is None:
            diagnostics.append({"path": path, "construct": key,
                                "reason": f"unsupported_{kind}_color_value"})
            return
        if key in colors:
            diagnostics.append({"path": path, "construct": key, "reason": "duplicate_color_key"})
        colors[key] = color
        occurrences.append((key, color))
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
                    record(colors, key, "#" + match.group(2)[:6], "hyprlock")
                elif match:
                    diagnostics.append({"path": path, "construct": match.group(1),
                                        "reason": "nonopaque_hyprlock_color"})
                elif "rgba(" in line and "=" in line:
                    diagnostics.append({"path": path, "construct": section or "hyprlock",
                                        "reason": "unsupported_hyprlock_color_value"})
        return "hyprlock", colors, occurrences, diagnostics
    if lower.endswith(".css"):
        colors = {}
        for match in CSS.finditer(content):
            name = (match.group(1) or match.group(2)).lower().replace("-", "_")
            record(colors, name, match.group(3), "css")
        return "css", colors, occurrences, diagnostics
    if lower.endswith(".conf") or lower.endswith(".theme"):
        kitty = {}
        palette = {}
        for line in content.splitlines():
            match = KITTY.match(line)
            if match:
                record(kitty, match.group(1), match.group(2), "kitty")
            match = PALETTE.match(line)
            if match:
                record(palette, match.group(1).lower(), match.group(2), "palette")
        if kitty and ("kitty" in lower or len(kitty) >= 3):
            return "kitty", kitty, [(key, value) for key, value in occurrences if key in kitty], diagnostics
        if palette and ("palette" in lower or "colors" in lower):
            return "palette", palette, [(key, value) for key, value in occurrences if key in palette], diagnostics
        if "kitty" in lower and ("kitty" in lower or "colors" in lower):
            return "kitty", kitty, occurrences, diagnostics
        if "palette" in lower or "colors" in lower:
            return "palette", palette, occurrences, diagnostics
    return None, {}, [], []


def adapter(path, content):
    kind, colors, _, _ = adapter_detailed(path, content)
    return kind, colors


def license_evidence(path, relative):
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        try:
            info = os.fstat(descriptor)
            if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_LICENSE_SIZE:
                return {"path": relative, "status": "unreadable_or_oversized"}
            chunks = []
            remaining = MAX_LICENSE_SIZE + 1
            while remaining:
                chunk = os.read(descriptor, min(65536, remaining))
                if not chunk:
                    break
                chunks.append(chunk)
                remaining -= len(chunk)
            data = b"".join(chunks)
        finally:
            os.close(descriptor)
        if len(data) > MAX_LICENSE_SIZE or len(data) != info.st_size:
            return {"path": relative, "status": "unreadable_or_oversized"}
        content = data.decode("utf-8")
        return {"path": relative, "status": "captured", "sha256": hashlib.sha256(data).hexdigest(),
                "text": content}
    except (OSError, UnicodeError):
        return {"path": relative, "status": "unreadable_or_oversized"}


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


def analyze(root, repository, revision, source_kind="github", source_url=None,
            retrieval_info=None, selector=None):
    started = time.monotonic()
    if selector is not None:
        validate_selector(selector)
    if not root.is_absolute() or not root.is_dir() or any(
            parent.is_symlink() for parent in (root, *root.parents)):
        raise ValueError("unsafe or missing source directory")
    if retrieval_info is not None and (not isinstance(retrieval_info, dict) or
            retrieval_info.get("method") != "github_api_commit_archive" or
            retrieval_info.get("revision") != revision):
        raise ValueError("retrieval revision does not match analyzed source")
    report = {
        "schema": 1,
        "repository": repository,
        "revision": revision,
        "source_kind": source_kind,
        "source_url": source_url or (f"https://github.com/{repository}" if source_kind == "github" else None),
        "retrieval_info": retrieval_info,
        "retrieval": "complete",
        "mode": "analysis_only",
        "limits": {"files": MAX_FILES, "directories": MAX_DIRECTORIES,
                   "depth": MAX_DEPTH, "file_bytes": MAX_FILE_SIZE,
                   "total_bytes": MAX_TOTAL_BYTES, "seconds": MAX_SECONDS},
        "inventory": [], "theme_candidates": [], "selected_candidate": None,
        "semantic_roles": {}, "conflicts": [], "skipped": [],
        "raw_ansi": [],
        "unsupported_constructs": [],
        "license_files": [], "licenses": [], "application_configs_converted": 0,
        "theme_pack_generated": False, "installed": False, "applied": False,
    }
    role_candidates = {}
    file_role_candidates = {}
    file_raw_ansi = {}
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
            if relative in report["license_files"] and len(report["licenses"]) < MAX_LICENSE_FILES:
                report["licenses"].append(license_evidence(path, relative))
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
                if len(content_bytes) > MAX_FILE_SIZE or len(content_bytes) != opened.st_size:
                    report["skipped"].append({"path": relative, "reason": "changed_or_oversized"})
                    continue
                total_bytes += len(content_bytes)
                if total_bytes > MAX_TOTAL_BYTES:
                    raise ValueError("total analysis byte limit exceeded")
                content = content_bytes.decode("utf-8")
            except (OSError, UnicodeError):
                report["skipped"].append({"path": relative, "reason": "unreadable_text"})
                continue
            kind, colors, occurrences, diagnostics = adapter_detailed(relative, content)
            for item in diagnostics:
                if len(report["unsupported_constructs"]) < MAX_UNSUPPORTED:
                    report["unsupported_constructs"].append(item)
            if not kind or not colors:
                continue
            roles = {}
            local_sources = {}
            local_raw = []
            for key, color in occurrences:
                if re.fullmatch(r"color(?:[0-9]|1[0-5])", key):
                    entry = {"path": relative, "key": key, "value": color}
                    report["raw_ansi"].append(entry)
                    local_raw.append(entry)
                role = ROLES.get(key)
                if role:
                    source = {"value": color, "path": relative, "key": key}
                    local_sources.setdefault(role, []).append(source)
                    role_candidates.setdefault(role, []).append(source)
            for role, sources in local_sources.items():
                if len({source["value"] for source in sources}) == 1:
                    roles[role] = sources[0]["value"]
            file_role_candidates[relative] = local_sources
            file_raw_ansi[relative] = local_raw
            report["inventory"].append({
                "path": relative, "format": kind, "application": application(relative),
                "colors": colors, "semantic_roles": roles,
                "confidence": "high" if roles else "raw_colors_only",
            })
            if {"BACKGROUND", "FOREGROUND"} <= roles.keys():
                try:
                    validate_selector(relative)
                except ValueError:
                    report["skipped"].append({"path": relative, "reason": "unsafe_candidate_path"})
                else:
                    report["theme_candidates"].append({
                        "path": relative, "name": Path(relative).stem,
                        "format": kind, "background": roles["BACKGROUND"],
                        "foreground": roles["FOREGROUND"],
                    })
    if selector is not None:
        matches = [item for item in report["theme_candidates"] if item["path"] == selector]
        if len(matches) != 1:
            raise ValueError(f"selector is not a valid theme candidate: {selector}; use a listed exact file path")
        report["selected_candidate"] = matches[0]
        role_candidates = file_role_candidates[selector]
        report["raw_ansi"] = file_raw_ansi[selector]
        report["unsupported_constructs"] = [item for item in report["unsupported_constructs"]
                                             if item["path"] == selector]
    elif len(report["theme_candidates"]) > 1:
        # Independent complete palettes require a choice; do not merge them.
        role_candidates = {}
        report["raw_ansi"] = []
    for role, sources in sorted(role_candidates.items()):
        values = {source["value"] for source in sources}
        if len(values) == 1:
            report["semantic_roles"][role] = sources[0]
        else:
            report["conflicts"].append({"role": role, "sources": sources})
    report["files_examined"] = files
    license_text = "\n".join(item.get("text", "") for item in report["licenses"]).lower()
    if not report["license_files"]:
        report["license_status"] = "missing"
    elif len(report["license_files"]) > 1 or len(report["licenses"]) < len(report["license_files"]) or \
            any(item["status"] != "captured" for item in report["licenses"]):
        report["license_status"] = "ambiguous_or_incomplete"
    elif any(term in license_text for term in ("all rights reserved", "non-commercial", "no redistribution")):
        report["license_status"] = "restrictive_terms_found"
    else:
        report["license_status"] = "present_unverified"
    return report


if __name__ == "__main__":
    if len(sys.argv) not in (4, 5, 6, 7):
        sys.exit("usage: analyze.py <checkout> <repository> <revision> [github|local] [retrieval.json|-] [selector|-]")
    try:
        source_kind = sys.argv[4] if len(sys.argv) == 5 else "github"
        if len(sys.argv) >= 6:
            source_kind = sys.argv[4]
        if source_kind not in ("github", "local"):
            raise ValueError("unsupported source kind")
        info = None
        if len(sys.argv) >= 6 and sys.argv[5] != "-":
            path = Path(sys.argv[5])
            if path.is_symlink() or path.stat().st_size > 65536:
                raise ValueError("unsafe retrieval metadata")
            info = json.loads(path.read_text())
        print(json.dumps(analyze(Path(sys.argv[1]), sys.argv[2], sys.argv[3], source_kind,
                                 retrieval_info=info,
                                 selector=sys.argv[6] if len(sys.argv) == 7 and sys.argv[6] != "-" else None),
                         indent=2, sort_keys=True))
    except (ValueError, OSError) as exc:
        print(f"Import analysis failed: {exc}", file=sys.stderr)
        sys.exit(1)
