#!/usr/bin/env python3

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ADAPTERS = ROOT / "engine/lib/adapters"
FIXTURES = {
    "catppuccin": ROOT / "tests/fixtures/catppuccin/palette.json",
    "rose_pine": ROOT / "tests/fixtures/rose_pine/palette.json",
    "nord": ROOT / "tests/fixtures/nord/src/nord.css",
}
ROLES = {
    "BACKGROUND", "FOREGROUND", "CURSOR", "PRIMARY", "SECONDARY", "ACCENT",
    "SUCCESS", "WARNING", "ERROR", "MUTED", "SURFACE", "SURFACE_ALT",
    "BORDER", "SELECTION", "HIGHLIGHT",
}


def read_fields(path):
    return dict(
        line.split("=", 1)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line and not line.startswith("#")
    )


class ExternalAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)

    def tearDown(self):
        self.temporary_directory.cleanup()

    def convert(self, adapter, variant=None, input_path=None, output_name="pack"):
        output = self.root / output_name
        command = [
            "python3", str(ADAPTERS / f"{adapter}.py"),
            "--input", str(input_path or FIXTURES[adapter]),
            "--output", str(output),
        ]
        if variant is not None:
            command.extend(("--variant", variant))
        result = subprocess.run(command, capture_output=True, text=True, check=False)
        return result, output

    def assert_pack(self, output, theme_id, name, author):
        self.assertEqual(sorted(path.name for path in output.iterdir()), ["palette.conf", "theme.conf"])
        manifest = read_fields(output / "theme.conf")
        self.assertEqual(manifest["THEME_ID"], theme_id)
        self.assertEqual(manifest["THEME_NAME"], name)
        self.assertEqual(manifest["THEME_AUTHOR"], author)
        self.assertEqual(manifest["THEME_VERSION"], "1.0.0")
        self.assertTrue(manifest["THEME_DESCRIPTION"])
        palette = read_fields(output / "palette.conf")
        self.assertEqual(palette.pop("XCALIBUR_DEFINITION_VERSION"), "1")
        self.assertEqual(set(palette), ROLES)
        for color in palette.values():
            self.assertRegex(color, r"^#[0-9A-F]{6}$")
        return palette

    def test_rose_pine_variants_and_exact_main_mapping(self):
        variants = {
            "main": ("rose-pine", "Rosé Pine", "#191724", "#EBBCBA"),
            "moon": ("rose-pine-moon", "Rosé Pine Moon", "#232136", "#EA9A97"),
            "dawn": ("rose-pine-dawn", "Rosé Pine Dawn", "#FAF4ED", "#D7827E"),
        }
        for variant, (theme_id, name, background, accent) in variants.items():
            with self.subTest(variant=variant):
                result, output = self.convert("rose_pine", variant, output_name=variant)
                self.assertEqual(result.returncode, 0, result.stderr)
                palette = self.assert_pack(output, theme_id, name, "Rosé Pine")
                self.assertEqual(palette["BACKGROUND"], background)
                self.assertEqual(palette["ACCENT"], accent)

        self.assertEqual(read_fields(self.root / "main/palette.conf"), {
            "XCALIBUR_DEFINITION_VERSION": "1",
            "BACKGROUND": "#191724",
            "FOREGROUND": "#E0DEF4",
            "CURSOR": "#EBBCBA",
            "PRIMARY": "#9CCFD8",
            "SECONDARY": "#C4A7E7",
            "ACCENT": "#EBBCBA",
            "SUCCESS": "#31748F",
            "WARNING": "#F6C177",
            "ERROR": "#EB6F92",
            "MUTED": "#6E6A86",
            "SURFACE": "#1F1D2E",
            "SURFACE_ALT": "#26233A",
            "BORDER": "#908CAA",
            "SELECTION": "#26233A",
            "HIGHLIGHT": "#C4A7E7",
        })

    def test_nord_exact_mapping(self):
        result, output = self.convert("nord")
        self.assertEqual(result.returncode, 0, result.stderr)
        palette = self.assert_pack(output, "nord", "Nord", "Nord")
        self.assertEqual(palette, {
            "BACKGROUND": "#2E3440",
            "FOREGROUND": "#ECEFF4",
            "CURSOR": "#ECEFF4",
            "PRIMARY": "#88C0D0",
            "SECONDARY": "#5E81AC",
            "ACCENT": "#8FBCBB",
            "SUCCESS": "#A3BE8C",
            "WARNING": "#EBCB8B",
            "ERROR": "#BF616A",
            "MUTED": "#D8DEE9",
            "SURFACE": "#3B4252",
            "SURFACE_ALT": "#434C5E",
            "BORDER": "#4C566A",
            "SELECTION": "#434C5E",
            "HIGHLIGHT": "#81A1C1",
        })

    def test_rose_pine_rejects_invalid_data_without_output(self):
        original = json.loads(FIXTURES["rose_pine"].read_text(encoding="utf-8"))
        bad_cases = {
            "missing-variant": {"moon": original["moon"]},
            "missing-role": {**original, "main": original["main"][:-1]},
            "duplicate-role": {**original, "main": original["main"] + [original["main"][0]]},
            "invalid-hex": {**original, "main": [{"role": "base", "hex": "not-a-color"}] + original["main"][1:]},
            "invalid-entry": {**original, "main": [42] + original["main"][1:]},
        }
        for name, data in bad_cases.items():
            with self.subTest(case=name):
                source = self.root / f"{name}.json"
                source.write_text(json.dumps(data), encoding="utf-8")
                result, output = self.convert("rose_pine", "main", source, name)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(output.exists())

    def test_nord_rejects_missing_duplicate_invalid_and_unsafe_css(self):
        original = FIXTURES["nord"].read_text(encoding="utf-8")
        bad_cases = {
            "missing": original.replace("  --nord15: #b48ead;\n", ""),
            "duplicate": original.replace("  --nord15: #b48ead;", "  --nord15: #b48ead; --nord15: #ffffff;"),
            "invalid-hex": original.replace("#2e3440", "#ZZZZZZ"),
            "reference": original.replace("#2e3440", "var(--other)"),
            "import": original + "@import url('evil.css');\n",
            "malformed": ":root { --nord0: #2e3440;",
        }
        for name, content in bad_cases.items():
            with self.subTest(case=name):
                source = self.root / f"{name}.css"
                source.write_text(content, encoding="utf-8")
                result, output = self.convert("nord", input_path=source, output_name=name)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(output.exists())

    def test_all_adapters_reject_symlinks_oversized_inputs_and_output_collisions(self):
        for adapter, variant in (("catppuccin", "mocha"), ("rose_pine", "main"), ("nord", None)):
            with self.subTest(adapter=adapter):
                link = self.root / f"{adapter}-link"
                link.symlink_to(FIXTURES[adapter])
                result, output = self.convert(adapter, variant, link, f"{adapter}-link-out")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("cannot open", result.stderr)
                self.assertFalse(output.exists())

                oversized = self.root / f"{adapter}-large"
                oversized.write_bytes(b" " * 1_048_577)
                result, output = self.convert(adapter, variant, oversized, f"{adapter}-large-out")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("size limit", result.stderr)
                self.assertFalse(output.exists())

                collision = self.root / f"{adapter}-existing"
                collision.mkdir()
                (collision / "marker").write_text("untouched", encoding="utf-8")
                result, output = self.convert(adapter, variant, output_name=collision.name)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("cannot write native theme pack", result.stderr)
                self.assertEqual(sorted(path.name for path in output.iterdir()), ["marker"])
                self.assertEqual((output / "marker").read_text(encoding="utf-8"), "untouched")

    def test_json_adapters_reject_malformed_duplicate_and_nested_input(self):
        for adapter, variant in (("catppuccin", "mocha"), ("rose_pine", "main")):
            for name, content in (
                ("malformed", '{"broken":'),
                ("duplicate", '{"main":[],"main":[]}'),
                ("nested", "[" * 1200 + "0" + "]" * 1200),
            ):
                with self.subTest(adapter=adapter, case=name):
                    source = self.root / f"{adapter}-{name}.json"
                    source.write_text(content, encoding="utf-8")
                    result, output = self.convert(adapter, variant, source, f"{adapter}-{name}-out")
                    self.assertNotEqual(result.returncode, 0)
                    if name == "duplicate":
                        self.assertIn("duplicate JSON object key", result.stderr)
                    elif name == "nested":
                        self.assertIn("nesting exceeds", result.stderr)
                    self.assertFalse(output.exists())

    def test_json_depth_check_ignores_brackets_inside_strings(self):
        for adapter, variant in (("catppuccin", "mocha"), ("rose_pine", "main")):
            with self.subTest(adapter=adapter):
                data = json.loads(FIXTURES[adapter].read_text(encoding="utf-8"))
                data["ignored"] = "[" * 200 + '\\"' + "]" * 200
                source = self.root / f"{adapter}-quoted-brackets.json"
                source.write_text(json.dumps(data), encoding="utf-8")
                result, output = self.convert(adapter, variant, source, f"{adapter}-quoted-out")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(sorted(path.name for path in output.iterdir()), ["palette.conf", "theme.conf"])

    def test_invalid_variant_selection(self):
        result, output = self.convert("rose_pine", "invalid")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())
        result, output = self.convert("nord", "dark")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
