"""Deterministic GitHub API and archive fixtures; no public network access."""

import importlib.util
import hashlib
import io
import json
import os
import tarfile
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("retrieve", ROOT / "engine/importer/retrieve.py")
retriever = importlib.util.module_from_spec(spec)
spec.loader.exec_module(retriever)
analyze_spec = importlib.util.spec_from_file_location("analyze", ROOT / "engine/importer/analyze.py")
analyzer = importlib.util.module_from_spec(analyze_spec)
analyze_spec.loader.exec_module(analyzer)
convert_spec = importlib.util.spec_from_file_location("convert", ROOT / "engine/importer/convert.py")
converter = importlib.util.module_from_spec(convert_spec)
convert_spec.loader.exec_module(converter)
SHA = "a" * 40


class Response(io.BytesIO):
    def __init__(self, data, status=200, length=True):
        super().__init__(data)
        self.status = status
        self.headers = {"Content-Length": str(len(data))} if length else {}


class FakeOpener:
    def __init__(self, archive, api=None, archive_response=None):
        self.archive = archive
        self.api = api if api is not None else json.dumps([{"sha": SHA}]).encode()
        self.archive_response = archive_response
        self.urls = []

    def open(self, request, timeout):
        self.urls.append(request.full_url)
        assert timeout <= 10
        if "/tarball/" in request.full_url:
            url = f"https://codeload.github.com/Owner/repo/tar.gz/{SHA}"
            raise urllib.error.HTTPError(request.full_url, 302, "redirect", {"Location": url}, None)
        if "api.github.com" in request.full_url:
            return Response(self.api)
        if self.archive_response is not None:
            return self.archive_response()
        return Response(self.archive)


def archive(entries):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w:gz") as tar:
        root = tarfile.TarInfo("repo-" + SHA + "/")
        root.type = tarfile.DIRTYPE
        tar.addfile(root)
        for name, payload, kind in entries:
            info = tarfile.TarInfo(name)
            if kind == "link":
                info.type = tarfile.SYMTYPE
                info.linkname = "../../outside"
                tar.addfile(info)
            elif kind == "fifo":
                info.type = tarfile.FIFOTYPE
                tar.addfile(info)
            else:
                info.size = len(payload)
                tar.addfile(info, io.BytesIO(payload))
    return output.getvalue()


class RetrievalTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="xcalibur-retrieve-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.destination = self.root / "repository"
        self.info = self.root / "retrieval.json"
        self.colors = ("repo-" + SHA + "/kitty.conf", b"background #112233\nforeground #eeeeee\n", "file")

    def run_retrieve(self, entries=None, opener=None):
        if opener is None:
            opener = FakeOpener(archive(entries if entries is not None else [self.colors]))
        result = retriever.retrieve("Owner/repo", self.destination, self.info, opener)
        return result, opener

    def test_pinned_archive_and_provenance(self):
        entries = [self.colors,
                   ("repo-" + SHA + "/LICENSE", b"Review terms\n", "file"),
                   ("repo-" + SHA + "/linked.css", b"", "link")]
        result, opener = self.run_retrieve(entries)
        self.assertEqual(result["revision"], SHA)
        self.assertEqual(result["stats"]["skipped_links"], 1)
        self.assertEqual(opener.urls, [
            "https://api.github.com/repos/Owner/repo/commits?per_page=1",
            f"https://api.github.com/repos/Owner/repo/tarball/{SHA}",
            f"https://codeload.github.com/Owner/repo/tar.gz/{SHA}"])
        self.assertEqual((self.destination / "kitty.conf").read_bytes(), self.colors[1])
        self.assertFalse((self.destination / "linked.css").exists())
        self.assertEqual(json.loads(self.info.read_text())["archive_sha256"],
                         result["archive_sha256"])
        self.assertEqual(list(self.root.glob(".download*")), [])

    def test_explicit_sha_skips_moving_default_branch(self):
        body = archive([self.colors])
        result = retriever.retrieve("Owner/repo@" + SHA, self.destination, self.info,
                                    FakeOpener(body, api=b"invalid"))
        self.assertEqual(result["revision"], SHA)
        with self.assertRaises(retriever.RetrievalError):
            retriever.validate_repository("Owner/repo@main")

    def test_invalid_reference_and_api_responses(self):
        for reference in ("../repo", "owner/repo/extra", "owner/repo..bad", "https://evil/repo"):
            with self.subTest(reference=reference), self.assertRaises(retriever.RetrievalError):
                retriever.retrieve(reference, self.destination, self.info, FakeOpener(b""))
        for status, expected in ((302, "redirect"), (403, "rate limit"), (404, "unavailable")):
            class ErrorOpener(FakeOpener):
                def open(self, request, timeout):
                    raise urllib.error.HTTPError(request.full_url, status, "test", {}, None)
            with self.subTest(status=status), self.assertRaisesRegex(retriever.RetrievalError, expected):
                self.run_retrieve(opener=ErrorOpener(b""))
        with self.assertRaisesRegex(retriever.RetrievalError, "no usable"):
            self.run_retrieve(opener=FakeOpener(b"", api=b"[]"))
        self.assertFalse(self.destination.exists())

    def test_unexpected_archive_redirect_is_refused(self):
        class RedirectOpener(FakeOpener):
            def open(self, request, timeout):
                if "/tarball/" in request.full_url:
                    raise urllib.error.HTTPError(request.full_url, 302, "redirect",
                                                 {"Location": "https://evil.invalid/archive.tar.gz"}, None)
                return super().open(request, timeout)
        with self.assertRaisesRegex(retriever.RetrievalError, "unexpected.*redirect"):
            self.run_retrieve(opener=RedirectOpener(b""))
        self.assertFalse(self.destination.exists())

    def test_download_limit_is_checked_during_stream(self):
        body = archive([self.colors])
        with mock.patch.object(retriever, "MAX_DOWNLOAD_BYTES", len(body) - 1):
            with self.assertRaisesRegex(retriever.RetrievalError, "byte limit"):
                self.run_retrieve(opener=FakeOpener(body, archive_response=lambda: Response(body, length=False)))
        self.assertFalse(self.destination.exists())
        self.assertFalse(self.info.exists())
        self.assertEqual(list(self.root.glob(".download*")), [])

    def test_checkout_file_count_size_and_depth_limits(self):
        body = archive([self.colors])
        with mock.patch.object(retriever, "MAX_CHECKOUT_BYTES", len(self.colors[1]) - 1):
            with self.assertRaisesRegex(retriever.RetrievalError, "checkout size"):
                self.run_retrieve(opener=FakeOpener(body))
        with mock.patch.object(retriever, "MAX_CANDIDATE_BYTES", len(self.colors[1]) - 1):
            with self.assertRaisesRegex(retriever.RetrievalError, "candidate theme file"):
                self.run_retrieve(opener=FakeOpener(body))
        two = archive([self.colors, ("repo-" + SHA + "/other.css", b"--accent: #abcdef;", "file")])
        with mock.patch.object(retriever, "MAX_FILES", 1):
            with self.assertRaisesRegex(retriever.RetrievalError, "file count"):
                self.run_retrieve(opener=FakeOpener(two))
        implicit = archive([("repo-" + SHA + "/one/x.css", b"--accent: #abcdef;", "file"),
                            ("repo-" + SHA + "/two/y.css", b"--accent: #abcdef;", "file")])
        with mock.patch.object(retriever, "MAX_DIRECTORIES", 1):
            with self.assertRaisesRegex(retriever.RetrievalError, "directory count"):
                self.run_retrieve(opener=FakeOpener(implicit))
        deep = archive([("repo-" + SHA + "/" + "/".join("d" for _ in range(9)) + "/x.css",
                         b"--accent: #abcdef;", "file")])
        with self.assertRaisesRegex(retriever.RetrievalError, "depth"):
            self.run_retrieve(opener=FakeOpener(deep))
        self.assertFalse(self.destination.exists())

    def test_archive_traversal_special_and_binary_content(self):
        for name, kind, expected in (
                ("repo-" + SHA + "/../escape.css", "file", "traversal"),
                ("repo-" + SHA + "/pipe", "fifo", "special file")):
            with self.subTest(name=name), self.assertRaisesRegex(retriever.RetrievalError, expected):
                self.run_retrieve(opener=FakeOpener(archive([(name, b"x", kind)])))
            self.assertFalse(self.destination.exists())
        mixed = archive([self.colors, ("other-root/x.css", b"x", "file")])
        with self.assertRaisesRegex(retriever.RetrievalError, "multiple root"):
            self.run_retrieve(opener=FakeOpener(mixed))
        self.run_retrieve([("repo-" + SHA + "/binary.css", b"\x00\xff", "file")])
        self.assertEqual((self.destination / "binary.css").read_bytes(), b"\x00\xff")

    def test_interrupted_download_cleans_partial_data(self):
        class Interrupted(Response):
            def read(self, *_args):
                raise KeyboardInterrupt
        opener = FakeOpener(b"", archive_response=lambda: Interrupted(b"abc", length=False))
        with self.assertRaises(KeyboardInterrupt):
            self.run_retrieve(opener=opener)
        self.assertFalse(self.destination.exists())
        self.assertFalse(self.info.exists())
        self.assertEqual(list(self.root.glob(".download*")), [])

    def test_pinned_remote_end_to_end_without_install_side_effect(self):
        license_text = b"All rights reserved. No redistribution.\n"
        info, _ = self.run_retrieve([self.colors,
                                     ("repo-" + SHA + "/LICENSE", license_text, "file")])
        report = analyzer.analyze(self.destination, "Owner/repo", SHA, retrieval_info=info)
        self.assertEqual(report["license_status"], "restrictive_terms_found")
        self.assertIn("Retrieval: github_api_commit_archive", converter.preview(report))
        pack = self.root / "pack"
        self.assertFalse(pack.exists())
        converter.convert(report, pack)
        metadata = json.loads((pack / "source.json").read_text())
        self.assertEqual(metadata["revision"], SHA)
        self.assertEqual(metadata["retrieval"]["archive_sha256"], info["archive_sha256"])
        self.assertEqual(metadata["licenses"][0]["sha256"], hashlib.sha256(license_text).hexdigest())
        themes = self.root / "themes"
        themes.mkdir()
        self.assertEqual(list(themes.iterdir()), [])
        converter.install_pack(pack, themes / "owner-repo", "owner-repo")
        self.assertEqual((themes / "owner-repo/source.json").read_bytes(),
                         (pack / "source.json").read_bytes())
        with self.assertRaisesRegex(ValueError, "already exists"):
            converter.install_pack(pack, themes / "owner-repo", "owner-repo")
        self.assertEqual(list(themes.iterdir()), [themes / "owner-repo"])

    def test_network_timeout_and_api_limit_cleanup(self):
        class TimedOut(FakeOpener):
            def open(self, request, timeout):
                raise TimeoutError("timed out")
        with self.assertRaisesRegex(retriever.RetrievalError, "network request failed"):
            self.run_retrieve(opener=TimedOut(b""))
        with mock.patch.object(retriever, "MAX_API_BYTES", 8):
            with self.assertRaisesRegex(retriever.RetrievalError, "byte limit"):
                self.run_retrieve(opener=FakeOpener(b""))
        self.assertEqual(list(self.root.iterdir()), [])

    def test_member_limit_candidate_total_and_oversized_license(self):
        second = ("repo-" + SHA + "/other.css", b"--accent: #abcdef;", "file")
        body = archive([self.colors, second])
        with mock.patch.object(retriever, "MAX_MEMBERS", 2):
            with self.assertRaisesRegex(retriever.RetrievalError, "member count"):
                self.run_retrieve(opener=FakeOpener(body))
        with mock.patch.object(retriever, "MAX_CANDIDATE_TOTAL", len(self.colors[1])):
            with self.assertRaisesRegex(retriever.RetrievalError, "candidate theme files"):
                self.run_retrieve(opener=FakeOpener(body))
        license_body = archive([self.colors,
                                ("repo-" + SHA + "/LICENSE", b"x" * 32769, "file")])
        self.run_retrieve(opener=FakeOpener(license_body))
        report = analyzer.analyze(self.destination, "Owner/repo", SHA)
        self.assertEqual(report["license_status"], "ambiguous_or_incomplete")

    def test_symlinked_staging_parent_is_rejected(self):
        outside = self.root / "outside"
        outside.mkdir()
        alias = self.root / "alias"
        alias.symlink_to(outside, target_is_directory=True)
        with self.assertRaises(OSError):
            retriever.retrieve("Owner/repo", alias / "repository", alias / "retrieval.json",
                               FakeOpener(archive([self.colors])))
        self.assertEqual(list(outside.iterdir()), [])

    def test_replaced_staging_parent_cannot_redirect_files(self):
        moved = self.root.parent / (self.root.name + "-moved")
        outside = self.root.parent / (self.root.name + "-outside")
        outside.mkdir()
        self.addCleanup(lambda: outside.rmdir())
        self.addCleanup(lambda: moved.rmdir() if moved.exists() else None)

        class ReplacingOpener(FakeOpener):
            def open(inner, request, timeout):
                if "codeload.github.com" in request.full_url:
                    self.root.rename(moved)
                    self.root.symlink_to(outside, target_is_directory=True)
                return super().open(request, timeout)

        with self.assertRaisesRegex(retriever.RetrievalError, "parent changed"):
            self.run_retrieve(opener=ReplacingOpener(archive([self.colors])))
        self.assertEqual(list(outside.iterdir()), [])
        self.assertEqual(list(moved.iterdir()), [])
        self.root.unlink()
        moved.rename(self.root)


if __name__ == "__main__":
    unittest.main()
