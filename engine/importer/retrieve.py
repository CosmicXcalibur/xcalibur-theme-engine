#!/usr/bin/env python3
"""Bounded, data-only retrieval of a GitHub commit archive.

The GitHub API selects one SHA. The archive request names that SHA, never a
moving branch. No repository code, Git hook, or archive link is executed.
"""

import hashlib
import http.client
import json
import os
import re
import signal
import sys
import tarfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPOSITORY = re.compile(r"[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9][A-Za-z0-9._-]{0,99}\Z")
SHA = re.compile(r"[0-9a-f]{40}\Z")
MAX_SECONDS = 60
MAX_API_BYTES = 65536
MAX_DOWNLOAD_BYTES = 16 * 1024 * 1024
MAX_CHECKOUT_BYTES = 32 * 1024 * 1024
MAX_MEMBER_BYTES = 8 * 1024 * 1024
MAX_CANDIDATE_BYTES = 256 * 1024
MAX_CANDIDATE_TOTAL = 4 * 1024 * 1024
MAX_FILES = 2000
MAX_DIRECTORIES = 2000
MAX_MEMBERS = 4000
MAX_DEPTH = 8
CHUNK = 65536


class RetrievalError(ValueError):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, _request, _file, _code, _message, _headers, _new_url):
        return None


def validate_repository(repository):
    if "@" in repository:
        repository, revision = repository.rsplit("@", 1)
        if not SHA.fullmatch(revision):
            raise RetrievalError("invalid pinned GitHub commit SHA")
    else:
        revision = None
    if not REPOSITORY.fullmatch(repository) or ".." in repository:
        raise RetrievalError("invalid GitHub owner/repository reference")
    return repository, revision


def deadline_check(deadline):
    if time.monotonic() >= deadline:
        raise RetrievalError("GitHub retrieval exceeded the 60 second limit")


def open_response(opener, url, deadline):
    deadline_check(deadline)
    request = urllib.request.Request(url, headers={
        "Accept": "application/vnd.github+json",
        "User-Agent": "Xcalibur-Theme-Importer/0.1",
    })
    try:
        response = opener.open(request, timeout=min(10, max(1, deadline - time.monotonic())))
    except urllib.error.HTTPError as error:
        error.close()
        if 300 <= error.code < 400:
            raise RetrievalError("unexpected GitHub redirect refused") from error
        if error.code in (401, 403, 429):
            raise RetrievalError("GitHub denied retrieval (authentication or rate limit); retry later or use a local directory") from error
        if error.code == 404:
            raise RetrievalError("GitHub repository or commit is unavailable (404)") from error
        raise RetrievalError(f"GitHub returned HTTP {error.code}") from error
    except (urllib.error.URLError, http.client.HTTPException, TimeoutError, OSError) as error:
        raise RetrievalError(f"GitHub network request failed: {error}") from error
    status = getattr(response, "status", 200)
    if 300 <= status < 400:
        response.close()
        raise RetrievalError("unexpected GitHub redirect refused")
    if status != 200:
        response.close()
        raise RetrievalError(f"GitHub returned HTTP {status}")
    return response


def stream_limited(response, output, limit, deadline):
    header = response.headers.get("Content-Length")
    if header is not None:
        try:
            declared = int(header)
        except ValueError as error:
            raise RetrievalError("invalid GitHub Content-Length") from error
        if declared < 0 or declared > limit:
            raise RetrievalError(f"GitHub response exceeds {limit} byte limit")
    total = 0
    digest = hashlib.sha256()
    while True:
        deadline_check(deadline)
        try:
            chunk = response.read(min(CHUNK, limit - total + 1))
        except (http.client.HTTPException, TimeoutError, OSError) as error:
            raise RetrievalError(f"GitHub response interrupted: {error}") from error
        deadline_check(deadline)
        if not chunk:
            break
        total += len(chunk)
        if total > limit:
            raise RetrievalError(f"GitHub response exceeds {limit} byte limit")
        output.write(chunk)
        digest.update(chunk)
    return total, digest.hexdigest()


def commit_sha(repository, opener, deadline):
    url = f"https://api.github.com/repos/{repository}/commits?per_page=1"
    with open_response(opener, url, deadline) as response:
        from io import BytesIO
        data = BytesIO()
        stream_limited(response, data, MAX_API_BYTES, deadline)
    try:
        commits = json.loads(data.getvalue())
        sha = commits[0]["sha"]
    except (ValueError, IndexError, KeyError, TypeError) as error:
        raise RetrievalError("GitHub returned no usable default-branch commit") from error
    if not isinstance(sha, str) or not SHA.fullmatch(sha):
        raise RetrievalError("GitHub returned an invalid commit SHA")
    return sha


def archive_location(repository, revision, opener, deadline):
    """Follow the one documented GitHub archive redirect after validating it."""
    deadline_check(deadline)
    endpoint = f"https://api.github.com/repos/{repository}/tarball/{revision}"
    request = urllib.request.Request(endpoint, headers={
        "Accept": "application/vnd.github+json", "User-Agent": "Xcalibur-Theme-Importer/0.1"})
    try:
        response = opener.open(request, timeout=min(10, max(1, deadline - time.monotonic())))
    except urllib.error.HTTPError as error:
        location = error.headers.get("Location") if error.headers else None
        code = error.code
        error.close()
        if code != 302:
            if code in (401, 403, 429):
                raise RetrievalError("GitHub denied archive access (authentication or rate limit)") from error
            if code == 404:
                raise RetrievalError("GitHub commit archive is unavailable (404)") from error
            raise RetrievalError(f"GitHub archive request returned HTTP {code}") from error
    except (urllib.error.URLError, http.client.HTTPException, TimeoutError, OSError) as error:
        raise RetrievalError(f"GitHub archive request failed: {error}") from error
    else:
        location = response.headers.get("Location")
        code = response.status
        response.close()
        if code != 302:
            raise RetrievalError(f"GitHub archive request returned unexpected HTTP {code}")
    if not isinstance(location, str):
        raise RetrievalError("GitHub archive redirect is missing")
    parsed = urllib.parse.urlsplit(location)
    if parsed.scheme != "https" or parsed.hostname != "codeload.github.com" or \
            parsed.username is not None or parsed.password is not None or parsed.port is not None or \
            parsed.query or parsed.fragment or parsed.path not in (
                f"/{repository}/tar.gz/{revision}",
                f"/{repository}/legacy.tar.gz/{revision}"):
        raise RetrievalError("unexpected GitHub archive redirect refused")
    return location


def archive_parts(name, expected_root):
    if not isinstance(name, str) or not name or name.startswith("/") or "\\" in name or \
            any(ord(char) < 32 or ord(char) == 127 for char in name):
        raise RetrievalError("unsafe archive member path")
    parts = name.rstrip("/").split("/")
    if any(part in ("", ".", "..") for part in parts):
        raise RetrievalError("archive traversal or malformed path refused")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,199}", parts[0]):
        raise RetrievalError("unsafe archive root")
    if expected_root is not None and parts[0] != expected_root:
        raise RetrievalError("archive contains multiple root directories")
    relative = parts[1:]
    if len(relative) > MAX_DEPTH:
        raise RetrievalError("archive directory depth limit exceeded")
    return relative


def candidate(parts):
    name = parts[-1].lower()
    return name.endswith((".css", ".conf", ".theme")) or name.startswith(("license", "copying"))


def directory_fd(root_fd, parts):
    fd = os.dup(root_fd)
    try:
        for part in parts:
            try:
                os.mkdir(part, 0o700, dir_fd=fd)
            except FileExistsError:
                pass
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
        return fd
    except BaseException:
        os.close(fd)
        raise


def open_private_parent(path):
    if not path.is_absolute() or any(part in ("", ".", "..") for part in path.parts[1:]):
        raise RetrievalError("retrieval staging parent must be absolute")
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path.parts[1:]:
            next_fd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                              dir_fd=fd)
            os.close(fd)
            fd = next_fd
        if os.fstat(fd).st_mode & 0o077:
            raise RetrievalError("retrieval staging parent must be private")
        return fd
    except BaseException:
        os.close(fd)
        raise


def extract_archive(archive_fd, parent_fd, destination_name, deadline):
    root_fd = os.open(destination_name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                      dir_fd=parent_fd)
    seen = set()
    seen_directories = set()
    archive_root = None
    files = directories = members = total_bytes = candidate_bytes = extracted = skipped_links = 0
    try:
        with os.fdopen(os.dup(archive_fd), "rb") as archive_input, \
                tarfile.open(fileobj=archive_input, mode="r|gz") as stream:
            for member in stream:
                deadline_check(deadline)
                members += 1
                if members > MAX_MEMBERS:
                    raise RetrievalError("archive member count limit exceeded")
                parts = archive_parts(member.name, archive_root)
                if archive_root is None:
                    archive_root = member.name.rstrip("/").split("/")[0]
                if not parts:
                    if not member.isdir():
                        raise RetrievalError("archive root is not a directory")
                    continue
                path = "/".join(parts)
                if path in seen:
                    raise RetrievalError("duplicate archive member path")
                seen.add(path)
                directory_depth = len(parts) if member.isdir() else len(parts) - 1
                for index in range(1, directory_depth + 1):
                    seen_directories.add(tuple(parts[:index]))
                    if len(seen_directories) > MAX_DIRECTORIES:
                        raise RetrievalError("archive directory count limit exceeded")
                directories = len(seen_directories)
                if member.isdir():
                    continue
                if member.issym() or member.islnk():
                    skipped_links += 1
                    continue
                if not member.isfile():
                    raise RetrievalError("archive special file refused")
                files += 1
                total_bytes += member.size
                if files > MAX_FILES or member.size > MAX_MEMBER_BYTES or total_bytes > MAX_CHECKOUT_BYTES:
                    raise RetrievalError("archive file count, member size, or checkout size limit exceeded")
                if not candidate(parts):
                    continue
                if member.size > MAX_CANDIDATE_BYTES:
                    raise RetrievalError("candidate theme file exceeds 256 KiB")
                candidate_bytes += member.size
                if candidate_bytes > MAX_CANDIDATE_TOTAL:
                    raise RetrievalError("candidate theme files exceed 4 MiB total")
                parent_fd = directory_fd(root_fd, parts[:-1])
                try:
                    fd = os.open(parts[-1], os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                                 0o600, dir_fd=parent_fd)
                    try:
                        source = stream.extractfile(member)
                        if source is None:
                            raise RetrievalError("archive member could not be read")
                        with source:
                            remaining = member.size
                            while remaining:
                                deadline_check(deadline)
                                chunk = source.read(min(CHUNK, remaining))
                                if not chunk:
                                    raise RetrievalError("truncated archive member")
                                view = memoryview(chunk)
                                while view:
                                    view = view[os.write(fd, view):]
                                remaining -= len(chunk)
                        extracted += 1
                    finally:
                        os.close(fd)
                finally:
                    os.close(parent_fd)
    except (tarfile.TarError, EOFError) as error:
        raise RetrievalError(f"invalid or truncated GitHub archive: {error}") from error
    finally:
        os.close(root_fd)
    return {"members": members, "files": files, "directories": directories,
            "checkout_bytes": total_bytes, "candidate_bytes": candidate_bytes,
            "extracted_files": extracted, "skipped_links": skipped_links}


def retrieve(repository, destination, info_file, opener=None):
    repository, pinned_revision = validate_repository(repository)
    destination = Path(destination)
    info_file = Path(info_file)
    if not destination.is_absolute() or not info_file.is_absolute() or \
            destination.parent != info_file.parent or \
            destination.name in ("", ".", "..") or info_file.name in ("", ".", "..") or \
            destination.name == info_file.name:
        raise RetrievalError("unsafe or existing retrieval destination")
    parent = destination.parent
    parent_fd = open_private_parent(parent)
    opener = opener or urllib.request.build_opener(NoRedirect())
    deadline = time.monotonic() + MAX_SECONDS
    archive_name = ".download.tar.gz"
    created_archive = False
    created_destination = False
    created_info = False
    try:
        for name in (destination.name, info_file.name, archive_name):
            try:
                os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
            except FileNotFoundError:
                continue
            raise RetrievalError("retrieval staging output already exists")
        revision = pinned_revision or commit_sha(repository, opener, deadline)
        url = archive_location(repository, revision, opener, deadline)
        fd = os.open(archive_name, os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                     0o600, dir_fd=parent_fd)
        created_archive = True
        try:
            with os.fdopen(os.dup(fd), "wb") as output, open_response(opener, url, deadline) as response:
                download_bytes, digest = stream_limited(response, output, MAX_DOWNLOAD_BYTES, deadline)
            os.lseek(fd, 0, os.SEEK_SET)
            os.mkdir(destination.name, 0o700, dir_fd=parent_fd)
            created_destination = True
            stats = extract_archive(fd, parent_fd, destination.name, deadline)
        finally:
            os.close(fd)
        info = {"method": "github_api_commit_archive", "revision": revision,
                "archive_url": url, "archive_sha256": digest,
                "download_bytes": download_bytes, "limits": {
                    "seconds": MAX_SECONDS, "api_bytes": MAX_API_BYTES,
                    "download_bytes": MAX_DOWNLOAD_BYTES, "checkout_bytes": MAX_CHECKOUT_BYTES,
                    "member_bytes": MAX_MEMBER_BYTES, "candidate_bytes": MAX_CANDIDATE_BYTES,
                    "candidate_total_bytes": MAX_CANDIDATE_TOTAL, "files": MAX_FILES,
                    "directories": MAX_DIRECTORIES, "members": MAX_MEMBERS, "depth": MAX_DEPTH},
                "stats": stats}
        info_fd = os.open(info_file.name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                          0o600, dir_fd=parent_fd)
        created_info = True
        with os.fdopen(info_fd, "w", encoding="utf-8") as output:
            json.dump(info, output, indent=2, sort_keys=True)
            output.write("\n")
        current_parent = os.lstat(parent)
        opened_parent = os.fstat(parent_fd)
        if (current_parent.st_dev, current_parent.st_ino) != (opened_parent.st_dev, opened_parent.st_ino):
            raise RetrievalError("retrieval staging parent changed during download")
        return info
    except BaseException:
        if created_destination:
            import shutil
            shutil.rmtree(destination.name, dir_fd=parent_fd)
        if created_info:
            os.unlink(info_file.name, dir_fd=parent_fd)
        raise
    finally:
        if created_archive:
            os.unlink(archive_name, dir_fd=parent_fd)
        os.close(parent_fd)


def main():
    if len(sys.argv) != 4:
        raise RetrievalError("usage: retrieve.py <owner/repository> <new-output-dir> <new-info-json>")
    info = retrieve(*sys.argv[1:])
    print(info["revision"])


if __name__ == "__main__":
    def interrupted(signum, _frame):
        raise RetrievalError(f"retrieval interrupted by signal {signum}")

    signal.signal(signal.SIGHUP, interrupted)
    signal.signal(signal.SIGTERM, interrupted)
    try:
        main()
    except (RetrievalError, OSError, KeyboardInterrupt) as error:
        print(f"GitHub retrieval failed: {error}", file=sys.stderr)
        sys.exit(1)
