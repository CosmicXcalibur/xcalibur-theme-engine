import importlib.util
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "engine" / "importer" / f"{name}.py")
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


analyzer = module("analyze")
converter = module("convert")


class ImporterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="xcalibur-import-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def report(self):
        source = self.root / "source"
        source.mkdir()
        (source / "kitty.conf").write_text("background #112233\nforeground #EEEEEE\ncolor4 #ABCDEF\n")
        (source / "colors.css").write_text("@define-color accent #445566;\n")
        return analyzer.analyze(source, "Owner/example", "a" * 40)

    def test_analyze_preview_convert(self):
        report = self.report()
        self.assertEqual(len(report["theme_candidates"]), 1)
        self.assertIsNone(report["selected_candidate"])
        self.assertEqual(report["semantic_roles"]["BACKGROUND"]["value"], "#112233")
        self.assertIn("Planned files: theme.conf, palette.conf", converter.preview(report))
        output = self.root / "new pack"
        self.assertEqual(converter.convert(report, output), "owner-example")
        self.assertIn("THEME_ID=owner-example", (output / "theme.conf").read_text())
        self.assertIn("ACCENT=#445566", (output / "palette.conf").read_text())
        metadata = json.loads((output / "source.json").read_text())
        self.assertEqual(metadata["source_url"], "https://github.com/Owner/example")
        self.assertEqual(metadata["revision"], "a" * 40)
        self.assertEqual(metadata["raw_ansi"], [{"path": "kitty.conf", "key": "color4",
                                                 "value": "#ABCDEF"}])
        self.assertEqual(metadata["role_sources"]["ACCENT"]["path"], "colors.css")
        with self.assertRaises(ValueError):
            converter.convert(report, output)

    def test_multiple_kitty_variants_require_exact_selection(self):
        source = self.root / "variants"
        themes = source / "themes"
        themes.mkdir(parents=True)
        variants = {
            "frappe": ("#303446", "#C6D0F5"),
            "latte": ("#EFF1F5", "#4C4F69"),
            "macchiato": ("#24273A", "#CAD3F5"),
            "mocha": ("#1E1E2E", "#CDD6F4"),
        }
        for name, (background, foreground) in variants.items():
            (themes / f"{name}.conf").write_text(
                f"background {background}\nforeground {foreground}\n"
                "cursor #F5E0DC\nselection_background #45475A\ncolor0 #11111B\n")
        (source / "LICENSE").write_text("MIT License. Review upstream terms.\n")
        report = analyzer.analyze(source, "catppuccin/kitty", "a" * 40)
        self.assertEqual([item["path"] for item in report["theme_candidates"]],
                         [f"themes/{name}.conf" for name in sorted(variants)])
        self.assertEqual(report["semantic_roles"], {})
        self.assertEqual(report["raw_ansi"], [])
        preview = converter.preview(report)
        self.assertIn("Theme candidates: 4", preview)
        self.assertIn('"themes/mocha.conf" ("mocha", kitty;', preview)
        self.assertIn("Selection required:", preview)
        self.assertIn("Conversion ready: no; select one candidate", preview)
        with self.assertRaisesRegex(ValueError, "multiple theme candidates"):
            converter.convert(report, self.root / "unselected-pack")
        self.assertFalse((self.root / "unselected-pack").exists())

        selected = analyzer.analyze(source, "catppuccin/kitty", "a" * 40,
                                    selector="themes/mocha.conf")
        self.assertEqual(selected["selected_candidate"]["path"], "themes/mocha.conf")
        self.assertEqual(selected["semantic_roles"]["BACKGROUND"]["value"], "#1E1E2E")
        self.assertEqual(selected["semantic_roles"]["FOREGROUND"]["value"], "#CDD6F4")
        self.assertTrue(all(item["path"] == "themes/mocha.conf" for item in selected["raw_ansi"]))
        self.assertEqual(selected["conflicts"], [])
        self.assertIn('Selected candidate: "themes/mocha.conf"', converter.preview(selected))
        output = self.root / "mocha-pack"
        theme_id = converter.convert(selected, output)
        self.assertTrue(theme_id.startswith("catppuccin-kitty-themes-mocha-"))
        self.assertIn("BACKGROUND=#1E1E2E", (output / "palette.conf").read_text())
        self.assertNotIn("#303446", (output / "palette.conf").read_text())
        metadata = json.loads((output / "source.json").read_text())
        self.assertEqual(metadata["selected_candidate"],
                         {"path": "themes/mocha.conf", "name": "mocha", "format": "kitty",
                          "background": "#1E1E2E", "foreground": "#CDD6F4"})
        self.assertEqual(metadata["detected_formats"], ["kitty"])
        self.assertEqual(metadata["license_status"], "present_unverified")
        self.assertTrue(all(item["path"] == "themes/mocha.conf"
                            for item in metadata["role_sources"].values()))
        self.assertEqual(metadata, converter.source_metadata(metadata, theme_id))
        tampered = json.loads(json.dumps(metadata))
        tampered["selected_candidate"]["path"] = "themes/latte.conf"
        with self.assertRaisesRegex(ValueError, "selected theme candidate"):
            converter.source_metadata(tampered, theme_id)
        tampered = json.loads(json.dumps(metadata))
        tampered["role_sources"]["BACKGROUND"]["path"] = "themes/latte.conf"
        with self.assertRaisesRegex(ValueError, "another source"):
            converter.source_metadata(tampered, theme_id)

    def test_candidate_selector_validation_and_duplicate_names(self):
        source = self.root / "variants"
        for folder in ("light", "dark"):
            target = source / folder
            target.mkdir(parents=True)
            (target / "mocha.conf").write_text(
                "background #112233\nforeground #EEEEEE\ncursor #445566\n")
        (source / "linked.conf").symlink_to(source / "dark/mocha.conf")
        (source / "linked-dir").symlink_to(source / "dark", target_is_directory=True)
        (source / "unsupported.txt").write_text(
            "background #112233\nforeground #EEEEEE\ncursor #445566\n")
        (source / "broken.conf").write_text(
            "background #112233\nbackground #445566\nforeground #EEEEEE\ncursor #445566\n")
        (source / "bad\x1b.conf").write_text(
            "background #112233\nforeground #EEEEEE\ncursor #445566\n")
        report = analyzer.analyze(source, "owner/repo", "a" * 40)
        self.assertEqual(len(report["theme_candidates"]), 2)
        self.assertTrue(any(item["reason"] == "unsafe_candidate_path" for item in report["skipped"]))
        for selector in ("/etc/passwd", "../dark/mocha.conf", "dark/../light/mocha.conf",
                         "dark//mocha.conf", "dark\\mocha.conf", "dark/mocha.conf\n",
                         "missing.conf", "linked.conf", "linked-dir/mocha.conf",
                         "unsupported.txt", "broken.conf"):
            with self.subTest(selector=selector), self.assertRaises(ValueError):
                analyzer.analyze(source, "owner/repo", "a" * 40, selector=selector)
        light = analyzer.analyze(source, "owner/repo", "a" * 40, selector="light/mocha.conf")
        dark = analyzer.analyze(source, "owner/repo", "a" * 40, selector="dark/mocha.conf")
        self.assertNotEqual(converter.plan(light)[0], converter.plan(dark)[0])

    def test_ambiguous_required_role(self):
        report = self.report()
        report["semantic_roles"].pop("BACKGROUND")
        report["conflicts"].append({"role": "BACKGROUND", "sources": [
            {"value": "#112233", "path": "one", "key": "background"},
            {"value": "#445566", "path": "two", "key": "background"}]})
        with self.assertRaisesRegex(ValueError, "unambiguous"):
            converter.plan(report)
        self.assertIn("Conversion ready: no", converter.preview(report))
        self.assertIn("Conflicts: 1", converter.preview(report))

    def test_symlink_and_size_limits(self):
        report = self.report()
        source = self.root / "source"
        (source / "link.css").symlink_to(source / "colors.css")
        (source / "large.css").write_text("x" * (analyzer.MAX_FILE_SIZE + 1))
        result = analyzer.analyze(source, "Owner/example", "a" * 40)
        reasons = {item["reason"] for item in result["skipped"]}
        self.assertIn("not_regular_file", reasons)
        self.assertIn("file_size_limit", reasons)
        (self.root / "alias").symlink_to(source, target_is_directory=True)
        with self.assertRaises(ValueError):
            converter.convert(report, self.root / "alias" / "pack")

    def test_bounded_walk_rejects_excess_entries_and_depth(self):
        source = self.root / "many"
        source.mkdir()
        for number in range(4):
            (source / f"{number}.css").write_text("--background: #112233;")
        old_files, old_directories = analyzer.MAX_FILES, analyzer.MAX_DIRECTORIES
        try:
            analyzer.MAX_FILES, analyzer.MAX_DIRECTORIES = 2, 1
            with self.assertRaisesRegex(ValueError, "entry limit"):
                analyzer.analyze(source, "Owner/example", "a" * 40)
        finally:
            analyzer.MAX_FILES, analyzer.MAX_DIRECTORIES = old_files, old_directories
        deep = self.root / "deep"
        deep.mkdir()
        current = deep
        for number in range(analyzer.MAX_DEPTH + 1):
            current = current / str(number)
            current.mkdir()
        report = analyzer.analyze(deep, "Owner/example", "a" * 40)
        self.assertTrue(any(item["reason"] == "depth_limit" for item in report["skipped"]))

    def test_bad_report_and_empty_repository(self):
        source = self.root / "empty"
        source.mkdir()
        report = analyzer.analyze(source, "Owner/example", "a" * 40)
        with self.assertRaisesRegex(ValueError, "unambiguous"):
            converter.plan(report)
        report["repository"] = "../../bad"
        with self.assertRaisesRegex(ValueError, "malformed"):
            converter.plan(report)

    def test_duplicate_and_invalid_colors_are_reported(self):
        source = self.root / "colors"
        source.mkdir()
        (source / "kitty.conf").write_text(
            "background #112233\nbackground #445566\nforeground #GGGGGG\n")
        report = analyzer.analyze(source, "Owner/example", "a" * 40)
        self.assertNotIn("BACKGROUND", report["semantic_roles"])
        self.assertEqual(report["conflicts"][0]["role"], "BACKGROUND")
        reasons = {item["reason"] for item in report["unsupported_constructs"]}
        self.assertIn("duplicate_color_key", reasons)
        self.assertIn("unsupported_kitty_color_value", reasons)
        with self.assertRaisesRegex(ValueError, "unambiguous"):
            converter.convert(report, self.root / "should-not-exist")
        self.assertFalse((self.root / "should-not-exist").exists())

    def test_simple_palette_indices_remain_raw(self):
        source = self.root / "simple"
        source.mkdir()
        (source / "palette.conf").write_text(
            "BACKGROUND=#112233\nFOREGROUND=#EEEEEE\nCOLOR0=#000000\n"
            "COLOR0=#010101\nCOLOR15=#FFFFFF\n")
        report = analyzer.analyze(source, "Owner/example", "a" * 40)
        output = self.root / "simple-pack"
        converter.convert(report, output)
        metadata = json.loads((output / "source.json").read_text())
        self.assertEqual([item["key"] for item in metadata["raw_ansi"]],
                         ["color0", "color0", "color15"])
        self.assertEqual([item["value"] for item in metadata["raw_ansi"][:2]],
                         ["#000000", "#010101"])
        self.assertNotIn("COLOR0=", (output / "palette.conf").read_text())

    def test_license_evidence_and_uncertain_permissions(self):
        source = self.root / "licensed"
        source.mkdir()
        (source / "kitty.conf").write_text("background #112233\nforeground #eeeeee\n")
        (source / "LICENSE").write_text("All rights reserved. No redistribution.\n")
        report = analyzer.analyze(source, "Owner/example", "a" * 40)
        self.assertEqual(report["license_status"], "restrictive_terms_found")
        self.assertEqual(report["licenses"][0]["sha256"], hashlib.sha256(
            (source / "LICENSE").read_bytes()).hexdigest())
        self.assertIn("License action: inspect upstream terms", converter.preview(report))
        output = self.root / "licensed-pack"
        converter.convert(report, output)
        metadata = json.loads((output / "source.json").read_text())
        self.assertIn("No redistribution", metadata["licenses"][0]["text"])
        self.assertEqual(metadata["license_paths"], ["LICENSE"])
        self.assertEqual(metadata["license_file_count"], 1)
        (source / "COPYING").write_text("Other terms\n")
        self.assertEqual(analyzer.analyze(source, "Owner/example", "a" * 40)[
            "license_status"], "ambiguous_or_incomplete")
        (source / "LICENSE").unlink()
        (source / "COPYING").unlink()
        self.assertEqual(analyzer.analyze(source, "Owner/example", "a" * 40)[
            "license_status"], "missing")
        (source / "LICENSE").write_text("x" * (analyzer.MAX_LICENSE_SIZE + 1))
        self.assertEqual(analyzer.analyze(source, "Owner/example", "a" * 40)[
            "license_status"], "ambiguous_or_incomplete")

    def test_metadata_and_output_paths_reject_malicious_data(self):
        report = self.report()
        report["licenses"] = [{"path": "../escape", "status": "unreadable_or_oversized"}]
        with self.assertRaisesRegex(ValueError, "unsafe license path"):
            converter.plan(report)
        report["licenses"] = []
        with self.assertRaisesRegex(ValueError, "unsafe output parent"):
            converter.convert(report, self.root / "missing" / "pack")
        (self.root / "archive.tar").write_bytes(b"not an archive")
        self.assertEqual(analyzer.analyze(self.root, "Owner/example", "a" * 40)[
            "files_examined"], 3)

    def test_conversion_failure_and_interrupt_clean_stage(self):
        report = self.report()
        output = self.root / "pack"
        with mock.patch.object(converter, "rename_exclusive", side_effect=OSError("blocked")):
            with self.assertRaises(OSError):
                converter.convert(report, output)
        self.assertFalse(output.exists())
        self.assertEqual(list(self.root.glob(".xcalibur-convert-*")), [])
        with mock.patch.object(converter, "validate_native_stage", side_effect=ValueError("invalid")):
            with self.assertRaisesRegex(ValueError, "invalid"):
                converter.convert(report, output)
        self.assertFalse(output.exists())
        self.assertEqual(list(self.root.glob(".xcalibur-convert-*")), [])
        with mock.patch.object(converter, "rename_exclusive", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                converter.convert(report, output)
        self.assertEqual(list(self.root.glob(".xcalibur-convert-*")), [])
        output.mkdir()
        (output / "user-file").write_text("untouched")
        with self.assertRaisesRegex(ValueError, "already exists"):
            converter.convert(report, output)
        self.assertEqual((output / "user-file").read_text(), "untouched")

    def test_termination_during_conversion_cleans_stage(self):
        report_path = self.root / "report.json"
        report_path.write_text(json.dumps(self.report()))
        output = self.root / "interrupted-pack"
        script = """
import importlib.util, os, signal, sys
spec = importlib.util.spec_from_file_location('convert', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.rename_exclusive = lambda *_: os.kill(os.getpid(), signal.SIGTERM)
sys.argv = ['convert.py', 'convert', sys.argv[2], sys.argv[3]]
try:
    module.main()
except InterruptedError:
    sys.exit(143)
"""
        result = subprocess.run([sys.executable, "-c", script,
                                 str(ROOT / "engine/importer/convert.py"),
                                 str(report_path), str(output)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 143, result.stderr)
        self.assertFalse(output.exists())
        self.assertEqual(list(self.root.glob(".xcalibur-convert-*")), [])

    def test_parent_replacement_does_not_redirect_output(self):
        report = self.report()
        parent = self.root / "output-parent"
        moved = self.root / "moved-parent"
        outside = self.root / "outside"
        parent.mkdir()
        outside.mkdir()
        original = converter.validate_native_stage

        def replace_parent(stage_fd, theme_id):
            original(stage_fd, theme_id)
            parent.rename(moved)
            parent.symlink_to(outside, target_is_directory=True)

        with mock.patch.object(converter, "validate_native_stage", side_effect=replace_parent):
            with self.assertRaisesRegex(ValueError, "parent changed"):
                converter.convert(report, parent / "pack")
        self.assertEqual(list(outside.iterdir()), [])
        self.assertEqual(list(moved.iterdir()), [])

    def test_install_pack_is_exclusive_and_cleans_failed_stage(self):
        pack = self.root / "pack"
        converter.convert(self.report(), pack)
        themes = self.root / "themes"
        themes.mkdir()
        destination = themes / "owner-example"
        with mock.patch.object(converter, "copy_stage_file", side_effect=OSError("copy failed")):
            with self.assertRaisesRegex(OSError, "copy failed"):
                converter.install_pack(pack, destination, "owner-example")
        self.assertEqual(list(themes.iterdir()), [])
        with mock.patch.object(converter, "validate_native_stage", side_effect=ValueError("invalid")):
            with self.assertRaisesRegex(ValueError, "invalid"):
                converter.install_pack(pack, destination, "owner-example")
        self.assertEqual(list(themes.iterdir()), [])
        with mock.patch.object(converter, "rename_exclusive", side_effect=OSError("publish failed")):
            with self.assertRaisesRegex(OSError, "publish failed"):
                converter.install_pack(pack, destination, "owner-example")
        self.assertEqual(list(themes.iterdir()), [])
        converter.install_pack(pack, destination, "owner-example")
        (destination / "user-file").write_text("preserve")
        with self.assertRaisesRegex(ValueError, "already exists"):
            converter.install_pack(pack, destination, "owner-example")
        self.assertEqual((destination / "user-file").read_text(), "preserve")

    def test_install_pack_parent_replacement_and_tampered_metadata(self):
        pack = self.root / "pack"
        report = self.report()
        report["retrieval_info"] = {
            "method": "github_api_commit_archive", "revision": "a" * 40,
            "archive_url": "https://codeload.github.com/Owner/example/tar.gz/" + "a" * 40,
            "archive_sha256": "f" * 64, "download_bytes": 100,
        }
        converter.convert(report, pack)
        themes = self.root / "themes"
        themes.mkdir()
        outside = self.root / "outside"
        outside.mkdir()
        moved = self.root / "moved"
        original = converter.validate_native_stage

        def replace_parent(stage_fd, theme_id, metadata_required=True):
            original(stage_fd, theme_id, metadata_required)
            themes.rename(moved)
            themes.symlink_to(outside, target_is_directory=True)

        with mock.patch.object(converter, "validate_native_stage", side_effect=replace_parent):
            with self.assertRaisesRegex(ValueError, "themes directory changed"):
                converter.install_pack(pack, themes / "owner-example", "owner-example")
        self.assertEqual(list(outside.iterdir()), [])
        self.assertEqual(list(moved.iterdir()), [])
        themes.unlink()
        moved.rename(themes)
        metadata = json.loads((pack / "source.json").read_text())
        metadata["revision"] = "b" * 40
        (pack / "source.json").write_text(json.dumps(metadata))
        with self.assertRaisesRegex(ValueError, "provenance"):
            converter.install_pack(pack, themes / "owner-example", "owner-example")
        self.assertEqual(list(themes.iterdir()), [])

    def test_source_root_symlink_is_rejected(self):
        report = self.report()
        alias = self.root / "alias"
        alias.symlink_to(self.root / "source", target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "unsafe"):
            analyzer.analyze(alias, "Owner/example", "a" * 40)

    def test_hyprlock_opaque_colors_only(self):
        source = self.root / "hyprlock.conf"
        source.write_text("background {\n color = rgba(112233ff)\n}\n"
                          "label {\n color = rgba(eeeeeedd)\n}\n")
        kind, colors = analyzer.adapter(source.name, source.read_text())
        self.assertEqual(kind, "hyprlock")
        self.assertEqual(colors, {"background": "#112233"})
        report = analyzer.analyze(self.root, "Owner/example", "a" * 40)
        self.assertTrue(any(item["reason"] == "nonopaque_hyprlock_color"
                            for item in report["unsupported_constructs"]))
        source.write_text("background {\n color = rgba(ZZZZZZff)\n}\n")
        report = analyzer.analyze(self.root, "Owner/example", "a" * 40)
        self.assertTrue(any(item["reason"] == "unsupported_hyprlock_color_value"
                            for item in report["unsupported_constructs"]))

    @unittest.skipUnless(shutil.which("git"), "Git is unavailable")
    def test_committed_local_git_fixture(self):
        repository = self.root / "local-git-fixture"
        repository.mkdir()
        (repository / "kitty.conf").write_text("background #112233\nforeground #eeeeee\n")
        environment = {**os.environ, "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1",
                       "GIT_AUTHOR_DATE": "2000-01-01T00:00:00Z",
                       "GIT_COMMITTER_DATE": "2000-01-01T00:00:00Z"}
        def git(*arguments):
            return subprocess.run(["git", "-C", str(repository), *arguments],
                                  env=environment, check=True, text=True,
                                  capture_output=True).stdout.strip()
        git("init", "-q")
        git("add", "kitty.conf")
        git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
            "-c", "commit.gpgsign=false", "commit", "-q", "-m", "Fixture colors")
        revision = git("rev-parse", "HEAD")
        report = analyzer.analyze(repository, "Owner/example", revision)
        self.assertEqual(report["revision"], revision)
        self.assertEqual(report["files_examined"], 1)
        destination = self.root / "converted-local-fixture"
        converter.convert(report, destination)
        self.assertTrue((destination / "palette.conf").is_file())


if __name__ == "__main__":
    unittest.main()
