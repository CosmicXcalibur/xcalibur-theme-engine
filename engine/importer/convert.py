#!/usr/bin/env python3
"""Convert an analyzer report to a reviewable native data-only theme pack."""

import json
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

ROLES = (
    "BACKGROUND", "FOREGROUND", "CURSOR", "PRIMARY", "SECONDARY", "ACCENT",
    "SUCCESS", "WARNING", "ERROR", "MUTED", "SURFACE", "SURFACE_ALT",
    "BORDER", "SELECTION", "HIGHLIGHT",
)
COLOR = re.compile(r"#[0-9A-Fa-f]{6}\Z")
REPOSITORY = re.compile(r"[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9][A-Za-z0-9._-]*\Z")


def plan(report, require_complete=True):
    if report.get("schema") != 1 or not REPOSITORY.fullmatch(report.get("repository", "")):
        raise ValueError("unsupported or malformed analysis report")
    owner, repository = report["repository"].split("/")
    theme_id = re.sub(r"[^a-z0-9]+", "-", f"{owner}-{repository}".lower()).strip("-")
    roles = {}
    conflicts = {item["role"] for item in report.get("conflicts", [])}
    for role, source in report.get("semantic_roles", {}).items():
        if role not in ROLES or role in conflicts:
            continue
        value = source.get("value") if isinstance(source, dict) else None
        if not isinstance(value, str) or not COLOR.fullmatch(value):
            raise ValueError(f"invalid {role} color in analysis report")
        roles[role] = value.upper()
    if require_complete and not {"BACKGROUND", "FOREGROUND"} <= roles.keys():
        raise ValueError("conversion requires unambiguous BACKGROUND and FOREGROUND colors")
    return theme_id, owner, repository, roles


def safe_parent(path):
    if not path.is_absolute() or path == path.parent:
        raise ValueError("output must be an absolute new directory")
    current = Path("/")
    for component in path.parent.parts[1:]:
        if component in ("", ".", ".."):
            raise ValueError("unsafe output path")
        current /= component
        if current.is_symlink() or not current.is_dir():
            raise ValueError(f"unsafe output parent: {current}")
    if path.name in ("", ".", "..") or path.exists() or path.is_symlink():
        raise ValueError("output directory already exists or is unsafe")


def preview(report):
    theme_id, owner, repository, roles = plan(report, require_complete=False)
    lines = [f"Source: {report['repository']} @ {report.get('revision', 'unknown')}",
             f"Planned theme ID: {theme_id}", "Planned files: theme.conf, palette.conf",
             "Detected files:"]
    for item in report.get("inventory", []):
        lines.append(f"  {item['path']} [{item['format']}, {item['confidence']}] "
                     f"{len(item['colors'])} colors")
    lines.append("Detected roles:")
    for role in ROLES:
        if role in roles:
            source = report["semantic_roles"][role]
            lines.append(f"  {role}={roles[role]} ({source.get('path', '?')}:{source.get('key', '?')})")
    lines.append(f"Conflicts: {len(report.get('conflicts', []))}")
    for conflict in report.get("conflicts", []):
        lines.append(f"  {conflict['role']}: " + ", ".join(
            f"{item['value']} from {item['path']}" for item in conflict["sources"]))
    lines.append(f"Skipped files: {len(report.get('skipped', []))}")
    for item in report.get("skipped", []):
        lines.append(f"  {item['path']}: {item['reason']}")
    lines.append(f"Unsupported constructs: {len(report.get('unsupported_constructs', []))}")
    for item in report.get("unsupported_constructs", []):
        lines.append(f"  {item['path']}:{item['construct']}: {item['reason']}")
    lines.append("Conversion ready: " + (
        "yes" if {"BACKGROUND", "FOREGROUND"} <= roles.keys() else
        "no; unambiguous BACKGROUND and FOREGROUND are required"))
    lines.append("Application settings converted: none")
    lines.append("License review required before redistribution")
    return "\n".join(lines)


def convert(report, output):
    theme_id, owner, repository, roles = plan(report)
    output = Path(output)
    safe_parent(output)
    stage = Path(tempfile.mkdtemp(prefix=".xcalibur-convert-", dir=output.parent))
    try:
        (stage / "theme.conf").write_text(
            f"THEME_ID={theme_id}\nTHEME_NAME={owner}/{repository}\n"
            "THEME_VERSION=1.0.0\n"
            f"THEME_AUTHOR={owner}\n"
            "THEME_DESCRIPTION=Converted color palette; review source license\n")
        (stage / "palette.conf").write_text(
            "XCALIBUR_DEFINITION_VERSION=1\n" + "".join(
                f"{role}={roles[role]}\n" for role in ROLES if role in roles))
        os.chmod(stage / "theme.conf", 0o644)
        os.chmod(stage / "palette.conf", 0o644)
        safe_parent(output)
        stage.rename(output)
    finally:
        if stage.exists():
            shutil.rmtree(stage)
    return theme_id


def main():
    if len(sys.argv) not in (3, 4) or sys.argv[1] not in ("preview", "convert"):
        raise ValueError("usage: convert.py preview <report.json> | convert <report.json> <absolute-output-dir>")
    report = json.loads(Path(sys.argv[2]).read_text())
    if sys.argv[1] == "preview" and len(sys.argv) == 3:
        print(preview(report))
    elif sys.argv[1] == "convert" and len(sys.argv) == 4:
        print(f"Converted theme pack: {convert(report, sys.argv[3])}")
    else:
        raise ValueError("invalid conversion arguments")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, json.JSONDecodeError) as error:
        print(f"Import conversion failed: {error}", file=sys.stderr)
        sys.exit(1)
