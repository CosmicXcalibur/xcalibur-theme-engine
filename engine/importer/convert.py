#!/usr/bin/env python3
"""Convert an analyzer report to a reviewable native data-only theme pack."""

import ctypes
import hashlib
import json
import os
import re
import shutil
import signal
import sys
import tempfile
from pathlib import Path

ROLES = (
    "BACKGROUND", "FOREGROUND", "CURSOR", "PRIMARY", "SECONDARY", "ACCENT",
    "SUCCESS", "WARNING", "ERROR", "MUTED", "SURFACE", "SURFACE_ALT",
    "BORDER", "SELECTION", "HIGHLIGHT",
)
COLOR = re.compile(r"#[0-9A-Fa-f]{6}\Z")
REPOSITORY = re.compile(r"[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9][A-Za-z0-9._-]{0,99}\Z")
REVISION = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64}|unversioned)\Z")
LICENSE_STATUSES = {"missing", "ambiguous_or_incomplete", "restrictive_terms_found",
                    "present_unverified"}
RAW_ANSI = re.compile(r"color(?:[0-9]|1[0-5])\Z")


def safe_relative(value):
    return isinstance(value, str) and not value.startswith("/") and all(
        part not in ("", ".", "..") for part in value.split("/")) and not any(
        ord(char) < 32 or ord(char) == 127 for char in value)


def source_metadata(report, theme_id):
    kind = report.get("source_kind", "github")
    repository = report["repository"]
    revision = report.get("revision")
    if not isinstance(repository, str) or not REPOSITORY.fullmatch(repository) or ".." in repository or \
            (kind == "local" and not repository.startswith("local/")):
        raise ValueError("invalid source repository in analysis report")
    if kind not in ("github", "local") or not isinstance(revision, str) or not REVISION.fullmatch(revision):
        raise ValueError("invalid source kind or revision in analysis report")
    url = report.get("source_url", f"https://github.com/{repository}" if kind == "github" else None)
    if (kind == "github" and url != f"https://github.com/{repository}") or (kind == "local" and url is not None):
        raise ValueError("invalid source URL in analysis report")
    status = report.get("license_status", "missing")
    if status not in LICENSE_STATUSES:
        raise ValueError("invalid license status in analysis report")
    licenses = report.get("licenses", [])
    if not isinstance(licenses, list) or len(licenses) > 4:
        raise ValueError("invalid license evidence")
    clean = []
    for item in licenses:
        if not isinstance(item, dict) or item.get("status") not in ("captured", "unreadable_or_oversized"):
            raise ValueError("invalid license evidence")
        path = item.get("path")
        if not safe_relative(path):
            raise ValueError("unsafe license path")
        entry = {"path": path, "status": item["status"]}
        if item["status"] == "captured":
            content = item.get("text")
            digest = item.get("sha256")
            if not isinstance(content, str) or len(content.encode("utf-8")) > 32768 or not isinstance(digest, str) or \
                    hashlib.sha256(content.encode("utf-8")).hexdigest() != digest:
                raise ValueError("invalid license content or digest")
            entry.update(text=content, sha256=digest)
        clean.append(entry)
    if "license_paths" in report:
        license_paths = report["license_paths"]
        license_count = report.get("license_file_count")
    else:
        license_files = report.get("license_files", [])
        if not isinstance(license_files, list) or len(license_files) > 2000:
            raise ValueError("invalid license file inventory")
        license_paths = license_files[:64]
        license_count = len(license_files)
    if not isinstance(license_paths, list) or len(license_paths) > 64 or \
            not isinstance(license_count, int) or license_count < len(license_paths) or license_count > 2000 or \
            any(not safe_relative(path) for path in license_paths):
        raise ValueError("invalid license file inventory")
    role_sources = report.get("role_sources", report.get("semantic_roles", {}))
    if not isinstance(role_sources, dict):
        raise ValueError("invalid role provenance")
    clean_roles = {}
    for role, source in role_sources.items():
        if role not in ROLES or not isinstance(source, dict) or not safe_relative(source.get("path")) or \
                not isinstance(source.get("key"), str) or not re.fullmatch(r"[A-Za-z0-9_-]+", source["key"]) or \
                not isinstance(source.get("value"), str) or not COLOR.fullmatch(source["value"]):
            raise ValueError("invalid role provenance")
        clean_roles[role] = {key: source[key] for key in ("path", "key", "value")}
    raw_ansi = report.get("raw_ansi")
    if raw_ansi is None:
        inventory = report.get("inventory", [])
        if not isinstance(inventory, list):
            raise ValueError("invalid inventory in analysis report")
        raw_ansi = []
        for item in inventory:
            if not isinstance(item, dict) or not isinstance(item.get("colors"), dict):
                raise ValueError("invalid inventory in analysis report")
            for key, value in item["colors"].items():
                if isinstance(key, str) and RAW_ANSI.fullmatch(key):
                    raw_ansi.append({"path": item.get("path"), "key": key, "value": value})
    if not isinstance(raw_ansi, list) or len(raw_ansi) > 2000:
        raise ValueError("invalid raw ANSI palette provenance")
    clean_raw = []
    for item in raw_ansi:
        if not isinstance(item, dict) or not safe_relative(item.get("path")) or \
                not isinstance(item.get("key"), str) or not RAW_ANSI.fullmatch(item["key"]) or \
                not isinstance(item.get("value"), str) or not COLOR.fullmatch(item["value"]):
            raise ValueError("invalid raw ANSI palette provenance")
        clean_raw.append({key: item[key] for key in ("path", "key", "value")})
    return {"schema": 1, "theme_id": theme_id, "source_kind": kind,
            "repository": repository, "source_url": url, "revision": revision,
            "revision_note": ("Local working tree may differ from HEAD" if kind == "local" else
                              "GitHub shallow checkout HEAD"),
            "license_status": status, "licenses": clean,
            "license_paths": license_paths, "license_file_count": license_count,
            "role_sources": clean_roles, "raw_ansi": clean_raw,
            "license_notice": "Review upstream terms before redistribution; no permission is inferred."}


def plan(report, require_complete=True):
    if not isinstance(report, dict) or report.get("schema") != 1 or \
            not isinstance(report.get("repository"), str) or \
            not REPOSITORY.fullmatch(report["repository"]):
        raise ValueError("unsupported or malformed analysis report")
    if not isinstance(report.get("semantic_roles"), dict) or not isinstance(report.get("conflicts"), list):
        raise ValueError("malformed roles or conflicts in analysis report")
    owner, repository = report["repository"].split("/")
    theme_id = re.sub(r"[^a-z0-9]+", "-", f"{owner}-{repository}".lower()).strip("-")
    source_metadata(report, theme_id)
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


def rename_exclusive(source, destination):
    """Linux renameat2 keeps the generated directory atomic and refuses collisions."""
    libc = ctypes.CDLL(None, use_errno=True)
    renameat2 = getattr(libc, "renameat2", None)
    if renameat2 is None:
        raise OSError("atomic exclusive directory rename is unavailable")
    renameat2.argtypes = (ctypes.c_int, ctypes.c_char_p, ctypes.c_int,
                          ctypes.c_char_p, ctypes.c_uint)
    renameat2.restype = ctypes.c_int
    if renameat2(-100, os.fsencode(source), -100, os.fsencode(destination), 1) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), str(destination))


def preview(report, themes_dir=None):
    theme_id, owner, repository, roles = plan(report, require_complete=False)
    lines = [f"Source: {report['repository']} @ {report.get('revision', 'unknown')}",
             f"Source URL: {report.get('source_url') or '(local source; no public URL)'}",
             f"Revision note: {source_metadata(report, theme_id)['revision_note']}",
             f"Planned theme ID: {theme_id}", "Planned files: theme.conf, palette.conf, source.json",
             "Detected files:"]
    if themes_dir is not None:
        destination = Path(themes_dir) / theme_id
        lines.append("Installation conflict: " + ("yes; theme ID already exists" if
                     destination.exists() or destination.is_symlink() else "none detected"))
    for item in report.get("inventory", []):
        lines.append(f"  {json.dumps(item['path'])} [{item['format']}, {item['confidence']}] "
                     f"{len(item['colors'])} colors")
    lines.append("Detected roles:")
    for role in ROLES:
        if role in roles:
            source = report["semantic_roles"][role]
            lines.append(f"  {role}={roles[role]} ({json.dumps(source.get('path', '?'))}:{source.get('key', '?')})")
    lines.append(f"Conflicts: {len(report.get('conflicts', []))}")
    for conflict in report.get("conflicts", []):
        lines.append(f"  {conflict['role']}: " + ", ".join(
            f"{item['value']} from {json.dumps(item['path'])}" for item in conflict["sources"]))
    lines.append(f"Skipped files: {len(report.get('skipped', []))}")
    for item in report.get("skipped", []):
        lines.append(f"  {json.dumps(item['path'])}: {item['reason']}")
    lines.append(f"Unsupported constructs: {len(report.get('unsupported_constructs', []))}")
    for item in report.get("unsupported_constructs", []):
        lines.append(f"  {json.dumps(item['path'])}:{item['construct']}: {item['reason']}")
    lines.append(f"License status: {report.get('license_status', 'missing')}")
    lines.append(f"License files detected: {len(report.get('license_files', []))}")
    for item in report.get("licenses", []):
        lines.append(f"  {json.dumps(item['path'])}: {item['status']}")
    lines.append("License action: inspect upstream terms before use or redistribution")
    lines.append("Missing optional roles: " + (", ".join(role for role in ROLES if role not in roles) or "none"))
    lines.append("Conversion ready: " + (
        "yes" if {"BACKGROUND", "FOREGROUND"} <= roles.keys() else
        "no; unambiguous BACKGROUND and FOREGROUND are required"))
    lines.append("Application settings converted: none")
    lines.append("License review required before redistribution")
    return "\n".join(lines)


def convert(report, output):
    theme_id, owner, repository, roles = plan(report)
    metadata = source_metadata(report, theme_id)
    metadata_bytes = (json.dumps(metadata, indent=2, sort_keys=True) + "\n").encode("utf-8")
    if len(metadata_bytes) > 262144:
        raise ValueError("source metadata exceeds native pack size limit")
    output = Path(output)
    safe_parent(output)
    stage = Path(tempfile.mkdtemp(prefix=".xcalibur-convert-", dir=output.parent))
    try:
        (stage / "theme.conf").write_text(
            f"THEME_ID={theme_id}\nTHEME_NAME={owner}/{repository}\n"
            "THEME_VERSION=1.0.0\n"
            "THEME_AUTHOR=Unverified upstream author\n"
            "THEME_DESCRIPTION=Converted color palette; review source authorship and license\n")
        (stage / "palette.conf").write_text(
            "XCALIBUR_DEFINITION_VERSION=1\n" + "".join(
                f"{role}={roles[role]}\n" for role in ROLES if role in roles))
        (stage / "source.json").write_bytes(metadata_bytes)
        os.chmod(stage / "theme.conf", 0o644)
        os.chmod(stage / "palette.conf", 0o644)
        os.chmod(stage / "source.json", 0o644)
        safe_parent(output)
        rename_exclusive(stage, output)
    finally:
        if stage.exists():
            shutil.rmtree(stage)
    return theme_id


def main():
    def interrupted(signum, _frame):
        raise InterruptedError(f"conversion interrupted by signal {signum}")

    signal.signal(signal.SIGHUP, interrupted)
    signal.signal(signal.SIGTERM, interrupted)
    if len(sys.argv) not in (3, 4) or sys.argv[1] not in ("preview", "convert", "validate-metadata"):
        raise ValueError("usage: convert.py preview <report.json> [themes-dir] | convert <report.json> <absolute-output-dir> | validate-metadata <source.json> <theme-id>")
    if sys.argv[1] == "validate-metadata" and len(sys.argv) == 4:
        metadata = json.loads(Path(sys.argv[2]).read_text())
        if metadata != source_metadata(metadata, sys.argv[3]) or metadata.get("theme_id") != sys.argv[3]:
            raise ValueError("invalid source metadata")
        return
    report = json.loads(Path(sys.argv[2]).read_text())
    if sys.argv[1] == "preview":
        print(preview(report, sys.argv[3] if len(sys.argv) == 4 else None))
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
    except KeyboardInterrupt:
        print("Import conversion interrupted", file=sys.stderr)
        sys.exit(130)
