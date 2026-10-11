import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import unittest
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
        self.assertEqual(report["semantic_roles"]["BACKGROUND"]["value"], "#112233")
        self.assertIn("Planned files: theme.conf, palette.conf", converter.preview(report))
        output = self.root / "new pack"
        self.assertEqual(converter.convert(report, output), "owner-example")
        self.assertIn("THEME_ID=owner-example", (output / "theme.conf").read_text())
        self.assertIn("ACCENT=#445566", (output / "palette.conf").read_text())
        with self.assertRaises(ValueError):
            converter.convert(report, output)

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
