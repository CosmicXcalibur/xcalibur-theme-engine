"""Tests for staged, data-only Kitty main-config preparation."""

import importlib.util
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "modules/kitty/prepare_config.py"
SPEC = importlib.util.spec_from_file_location("kitty_prepare_config", MODULE_PATH)
kitty_config = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(kitty_config)


class KittyConfigTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="kitty-config-test.")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.main = self.root / "kitty" / "kitty.conf"
        self.main.parent.mkdir()

    def test_existing_settings_and_include_order(self):
        original = b"allow_remote_control yes\ninclude current-theme.conf\nbackground #ffffff\n"
        self.main.write_bytes(original)
        self.main.chmod(0o600)
        first = self.root / "first.conf"
        kitty_config.prepare(self.main, first)
        self.assertEqual(first.read_bytes(),
                         b"allow_remote_control yes\nbackground #ffffff\ninclude current-theme.conf\n")
        self.assertEqual(first.stat().st_mode & 0o777, 0o600)
        second = self.root / "second.conf"
        kitty_config.prepare(first, second)
        self.assertEqual(second.read_bytes(), first.read_bytes())

    def test_commented_include_moves_after_color_override_and_is_idempotent(self):
        self.main.write_bytes(
            b"allow_remote_control yes\n"
            b"include current-theme.conf # theme colors\n"
            b"# Keep this user comment.\n"
            b"background #ffffff\n"
        )
        first = self.main.parent / "first.conf"
        kitty_config.prepare(self.main, first)
        expected = (
            b"allow_remote_control yes\n"
            b"# Keep this user comment.\n"
            b"background #ffffff\n"
            b"include current-theme.conf # theme colors\n"
        )
        self.assertEqual(first.read_bytes(), expected)
        second = self.main.parent / "second.conf"
        kitty_config.prepare(first, second)
        self.assertEqual(second.read_bytes(), expected)
        self.assertEqual(second.read_bytes().count(b"include current-theme.conf"), 1)

    def test_supported_include_paths_with_trailing_comments(self):
        paths = (
            b"current-theme.conf",
            b"./current-theme.conf",
            str(self.main.parent / "current-theme.conf").encode(),
        )
        for index, path in enumerate(paths):
            with self.subTest(path=path):
                include = b"include " + path + b"\t# theme colors\n"
                self.main.write_bytes(include + b"foreground #ffffff\n")
                output = self.main.parent / f"path-{index}.conf"
                kitty_config.prepare(self.main, output)
                self.assertEqual(output.read_bytes(), b"foreground #ffffff\n" + include)

    def test_missing_config_creates_only_include(self):
        output = self.root / "staged.conf"
        kitty_config.prepare(self.main, output)
        self.assertEqual(output.read_bytes(), b"include current-theme.conf\n")
        self.assertFalse(self.main.exists())

    def test_unsafe_input_and_duplicate_include_leave_no_output(self):
        outside = self.root / "outside.conf"
        outside.write_text("keep me\n")
        self.main.symlink_to(outside)
        with self.assertRaises(ValueError):
            kitty_config.prepare(self.main, self.root / "symlink-output")
        self.assertEqual(outside.read_text(), "keep me\n")
        self.assertFalse((self.root / "symlink-output").exists())
        self.main.unlink()
        self.main.write_text("include current-theme.conf\ninclude ./current-theme.conf\n")
        with self.assertRaises(ValueError):
            kitty_config.prepare(self.main, self.root / "duplicate-output")
        self.assertFalse((self.root / "duplicate-output").exists())

    def test_duplicate_commented_includes_leave_no_output(self):
        original = (
            b"allow_remote_control yes\n"
            b"include current-theme.conf # first\n"
            b"include ./current-theme.conf\t# second\n"
        )
        self.main.write_bytes(original)
        output = self.root / "duplicate-comment-output"
        with self.assertRaisesRegex(ValueError, "duplicate Kitty theme includes"):
            kitty_config.prepare(self.main, output)
        self.assertFalse(output.exists())
        self.assertEqual(self.main.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
