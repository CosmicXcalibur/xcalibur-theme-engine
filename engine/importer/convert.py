#!/usr/bin/env python3
"""Convert an analyzer report to a reviewable native data-only theme pack."""

import ctypes
import hashlib
import json
import os
import re
import secrets
import signal
import stat
import subprocess
import sys
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
    retrieval = report.get("retrieval") if isinstance(report.get("retrieval"), dict) else report.get("retrieval_info")
    if retrieval is None:
        retrieval = {"method": "local_directory" if kind == "local" else "unspecified"}
    if not isinstance(retrieval, dict):
        raise ValueError("invalid retrieval provenance")
    method = retrieval.get("method")
    if kind == "local":
        if method != "local_directory":
            raise ValueError("invalid local retrieval method")
        clean_retrieval = {"method": method}
    elif method == "github_api_commit_archive":
        archive_urls = (f"https://codeload.github.com/{repository}/tar.gz/{revision}",
                        f"https://codeload.github.com/{repository}/legacy.tar.gz/{revision}")
        archive_url = retrieval.get("archive_url")
        digest = retrieval.get("archive_sha256")
        count = retrieval.get("download_bytes")
        if retrieval.get("revision") != revision or archive_url not in archive_urls or \
                not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest) or \
                not isinstance(count, int) or not 0 < count <= 16 * 1024 * 1024:
            raise ValueError("invalid pinned GitHub archive provenance")
        clean_retrieval = {"method": method, "revision": revision,
                           "archive_url": archive_url, "archive_sha256": digest,
                           "download_bytes": count}
    elif method == "unspecified":
        clean_retrieval = {"method": method}
    else:
        raise ValueError("unsupported retrieval method")
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
    formats = report.get("detected_formats")
    if formats is None:
        formats = sorted({item["format"] for item in report.get("inventory", [])})
    if not isinstance(formats, list) or any(item not in ("kitty", "css", "palette", "hyprlock")
                                             for item in formats) or len(formats) > 4:
        raise ValueError("invalid detected source formats")
    warnings = report.get("conversion_warnings")
    if warnings is None:
        warnings = []
        for item in report.get("unsupported_constructs", [])[:100]:
            warnings.append({"path": item["path"], "reason": item["reason"]})
        for item in report.get("conflicts", [])[:100]:
            warnings.append({"path": "", "reason": f"conflicting_{item['role']}"})
    if not isinstance(warnings, list) or len(warnings) > 200 or any(
            not isinstance(item, dict) or
            (item.get("path") != "" and not safe_relative(item.get("path"))) or
            not isinstance(item.get("reason"), str) or
            not re.fullmatch(r"[A-Za-z0-9_]+", item["reason"])
            for item in warnings):
        raise ValueError("invalid conversion warnings")
    clean_warnings = [{"path": item["path"], "reason": item["reason"]} for item in warnings]
    return {"schema": 1, "theme_id": theme_id, "source_kind": kind,
            "repository": repository, "source_url": url, "revision": revision,
            "retrieval": clean_retrieval,
            "revision_note": ("Local working tree may differ from HEAD" if kind == "local" else
                              "GitHub archive requested by exact commit SHA" if
                              method == "github_api_commit_archive" else
                              "GitHub revision supplied without bounded retrieval evidence"),
            "license_status": status, "licenses": clean,
            "license_paths": license_paths, "license_file_count": license_count,
            "role_sources": clean_roles, "raw_ansi": clean_raw,
            "detected_formats": formats, "conversion_warnings": clean_warnings,
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


def open_safe_directory(path):
    if not path.is_absolute():
        raise ValueError("directory path must be absolute")
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        current = Path("/")
        for component in path.parts[1:]:
            if component in ("", ".", ".."):
                raise ValueError("unsafe output path")
            current /= component
            try:
                next_fd = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                                  dir_fd=fd)
            except OSError as error:
                raise ValueError(f"unsafe output parent: {current}") from error
            os.close(fd)
            fd = next_fd
        return fd
    except BaseException:
        os.close(fd)
        raise


def open_safe_parent(path):
    if not path.is_absolute() or path == path.parent:
        raise ValueError("output must be an absolute new directory")
    fd = open_safe_directory(path.parent)
    try:
        if path.name in ("", ".", ".."):
            raise ValueError("unsafe output path")
        try:
            os.stat(path.name, dir_fd=fd, follow_symlinks=False)
        except FileNotFoundError:
            return fd
        raise ValueError("output directory already exists or is unsafe")
    except BaseException:
        os.close(fd)
        raise


def safe_parent(path):
    fd = open_safe_parent(path)
    os.close(fd)


def rename_exclusive(parent_fd, source_name, destination_name):
    """Linux renameat2 keeps the generated directory atomic and refuses collisions."""
    libc = ctypes.CDLL(None, use_errno=True)
    renameat2 = getattr(libc, "renameat2", None)
    if renameat2 is None:
        raise OSError("atomic exclusive directory rename is unavailable")
    renameat2.argtypes = (ctypes.c_int, ctypes.c_char_p, ctypes.c_int,
                          ctypes.c_char_p, ctypes.c_uint)
    renameat2.restype = ctypes.c_int
    if renameat2(parent_fd, os.fsencode(source_name), parent_fd, os.fsencode(destination_name), 1) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), destination_name)


def stage_directory(parent_fd, prefix=".xcalibur-convert-"):
    for _ in range(10):
        name = prefix + secrets.token_hex(12)
        try:
            os.mkdir(name, 0o700, dir_fd=parent_fd)
        except FileExistsError:
            continue
        try:
            return name, os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                                 dir_fd=parent_fd)
        except BaseException:
            os.rmdir(name, dir_fd=parent_fd)
            raise
    raise OSError("unable to allocate private conversion stage")


def parent_identity_matches(parent_fd, parent_path):
    opened = os.fstat(parent_fd)
    current = os.lstat(parent_path)
    return (opened.st_dev, opened.st_ino) == (current.st_dev, current.st_ino)


def write_stage_file(stage_fd, name, data):
    fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                 0o600, dir_fd=stage_fd)
    try:
        view = memoryview(data)
        while view:
            view = view[os.write(fd, view):]
        os.fchmod(fd, 0o644)
        os.fsync(fd)
    finally:
        os.close(fd)


def validate_native_stage(stage_fd, theme_id, metadata_required=True):
    """Use the engine's authoritative Bash data parsers before publication."""
    engine_lib = Path(__file__).resolve().parents[1] / "lib"
    script = ('source "$1"; source "$2"; '
              'theme_manifest_load "$3/theme.conf" "" && '
              '[[ "$THEME_ID" == "$4" ]] && '
              'theme_definition_load "$3/palette.conf" ""')
    result = subprocess.run(
        ["bash", "-c", script, "validate-native-stage",
         str(engine_lib / "theme_manifest.sh"), str(engine_lib / "theme_definition.sh"),
         f"/proc/self/fd/{stage_fd}", theme_id], pass_fds=(stage_fd,),
        capture_output=True, text=True, timeout=10, check=False)
    if result.returncode != 0:
        raise ValueError("generated pack failed native theme validation")
    try:
        fd = os.open("source.json", os.O_RDONLY | os.O_NOFOLLOW, dir_fd=stage_fd)
    except FileNotFoundError:
        if metadata_required:
            raise ValueError("generated source metadata is missing")
        return
    try:
        metadata = json.loads(os.read(fd, 262145))
    finally:
        os.close(fd)
    if not isinstance(metadata, dict):
        raise ValueError("generated source metadata must be an object")
    if metadata.get("theme_id") != theme_id or metadata != source_metadata(metadata, theme_id):
        raise ValueError("generated source metadata failed validation")


def copy_stage_file(source_fd, stage_fd, name):
    fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=source_fd)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size > 262144:
            raise ValueError(f"unsafe or oversized pack file: {name}")
        data = bytearray()
        while len(data) <= 262144:
            chunk = os.read(fd, min(65536, 262145 - len(data)))
            if not chunk:
                break
            data.extend(chunk)
        if len(data) != info.st_size:
            raise ValueError(f"pack file changed while copying: {name}")
        write_stage_file(stage_fd, name, data)
    finally:
        os.close(fd)


def install_pack(source, destination, theme_id):
    if not re.fullmatch(r"[a-z0-9]+(?:[a-z0-9-]*[a-z0-9])?", theme_id):
        raise ValueError("invalid native theme ID")
    source_fd = open_safe_directory(Path(source))
    try:
        destination = Path(destination)
        parent_fd = open_safe_parent(destination)
        stage_name = None
        stage_fd = None
        published = False
        try:
            stage_name, stage_fd = stage_directory(parent_fd, ".xcalibur-install-")
            for name in ("theme.conf", "palette.conf"):
                copy_stage_file(source_fd, stage_fd, name)
            try:
                os.stat("source.json", dir_fd=source_fd, follow_symlinks=False)
            except FileNotFoundError:
                metadata_present = False
            else:
                metadata_present = True
                copy_stage_file(source_fd, stage_fd, "source.json")
            validate_native_stage(stage_fd, theme_id, metadata_present)
            os.fsync(stage_fd)
            if not parent_identity_matches(parent_fd, destination.parent):
                raise ValueError("themes directory changed during installation")
            rename_exclusive(parent_fd, stage_name, destination.name)
            published = True
        finally:
            if stage_fd is not None:
                if not published:
                    for name in ("theme.conf", "palette.conf", "source.json"):
                        try:
                            os.unlink(name, dir_fd=stage_fd)
                        except FileNotFoundError:
                            pass
                os.close(stage_fd)
            if stage_name is not None and not published:
                os.rmdir(stage_name, dir_fd=parent_fd)
            os.close(parent_fd)
    finally:
        os.close(source_fd)


def preview(report, themes_dir=None):
    theme_id, owner, repository, roles = plan(report, require_complete=False)
    metadata = source_metadata(report, theme_id)
    lines = [f"Source: {report['repository']} @ {report.get('revision', 'unknown')}",
             f"Source URL: {report.get('source_url') or '(local source; no public URL)'}",
             f"Retrieval: {metadata['retrieval']['method']}",
             f"Revision note: {metadata['revision_note']}",
             f"Planned theme ID: {theme_id}", "Planned files: theme.conf, palette.conf, source.json",
             "Detected files:"]
    if metadata["source_kind"] == "github" and re.fullmatch(r"[0-9a-f]{40}", metadata["revision"]):
        lines.insert(4, f"Pinned source for next command: {metadata['repository']}@{metadata['revision']}")
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
    parent_fd = open_safe_parent(output)
    stage_name = None
    stage_fd = None
    published = False
    try:
        stage_name, stage_fd = stage_directory(parent_fd)
        manifest = (
            f"THEME_ID={theme_id}\nTHEME_NAME={owner}/{repository}\n"
            "THEME_VERSION=1.0.0\n"
            "THEME_AUTHOR=Unverified upstream author\n"
            "THEME_DESCRIPTION=Converted color palette; review source authorship and license\n")
        palette = (
            "XCALIBUR_DEFINITION_VERSION=1\n" + "".join(
                f"{role}={roles[role]}\n" for role in ROLES if role in roles))
        write_stage_file(stage_fd, "theme.conf", manifest.encode("utf-8"))
        write_stage_file(stage_fd, "palette.conf", palette.encode("utf-8"))
        write_stage_file(stage_fd, "source.json", metadata_bytes)
        validate_native_stage(stage_fd, theme_id)
        os.fsync(stage_fd)
        if not parent_identity_matches(parent_fd, output.parent):
            raise ValueError("output parent changed during conversion")
        rename_exclusive(parent_fd, stage_name, output.name)
        published = True
    finally:
        if stage_fd is not None:
            if not published:
                for name in ("theme.conf", "palette.conf", "source.json"):
                    try:
                        os.unlink(name, dir_fd=stage_fd)
                    except FileNotFoundError:
                        pass
            os.close(stage_fd)
        if stage_name is not None and not published:
            try:
                os.rmdir(stage_name, dir_fd=parent_fd)
            except FileNotFoundError:
                pass
        os.close(parent_fd)
    return theme_id


def main():
    def interrupted(signum, _frame):
        raise InterruptedError(f"conversion interrupted by signal {signum}")

    signal.signal(signal.SIGHUP, interrupted)
    signal.signal(signal.SIGTERM, interrupted)
    if len(sys.argv) not in (3, 4, 5) or sys.argv[1] not in (
            "preview", "convert", "validate-metadata", "install-pack"):
        raise ValueError("usage: convert.py preview <report.json> [themes-dir] | convert <report.json> <absolute-output-dir> | validate-metadata <source.json> <theme-id> | install-pack <source-dir> <destination-dir> <theme-id>")
    if sys.argv[1] == "install-pack" and len(sys.argv) == 5:
        install_pack(sys.argv[2], sys.argv[3], sys.argv[4])
        return
    if sys.argv[1] == "validate-metadata" and len(sys.argv) == 4:
        metadata = json.loads(Path(sys.argv[2]).read_text())
        if not isinstance(metadata, dict):
            raise ValueError("source metadata must be an object")
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
