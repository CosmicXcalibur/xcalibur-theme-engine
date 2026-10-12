#!/usr/bin/env python3

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
ADAPTER = REPOSITORY_ROOT / "engine/lib/adapters/catppuccin.py"
FIXTURE = REPOSITORY_ROOT / "tests/fixtures/catppuccin/palette.json"
MAX_INPUT_BYTES = 1_048_576


class CatppuccinAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.input_path = self.root / "palette.json"
        self.input_path.write_bytes(FIXTURE.read_bytes())

    def tearDown(self):
        self.temporary_directory.cleanup()

    def run_adapter(self, variant="mocha", input_path=None, output_name="native-pack"):
        output_path = self.root / output_name
        result = subprocess.run(
            [
                "python3",
                str(ADAPTER),
                "--input",
                str(input_path or self.input_path),
                "--variant",
                variant,
                "--output",
                str(output_path),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        return result, output_path

    @staticmethod
    def read_key_values(path):
        values = {}
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line or line.startswith("#"):
                continue
            key, value = line.split("=", 1)
            values[key] = value
        return values

    def test_all_variants_generate_deterministic_metadata_and_exact_files(self):
        display_names = {
            "latte": "Catppuccin Latte",
            "frappe": "Catppuccin Frappé",
            "macchiato": "Catppuccin Macchiato",
            "mocha": "Catppuccin Mocha",
        }

        for variant, display_name in display_names.items():
            with self.subTest(variant=variant):
                result, output_path = self.run_adapter(variant, output_name=f"pack-{variant}")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(
                    sorted(path.name for path in output_path.iterdir()),
                    ["palette.conf", "theme.conf"],
                )
                manifest = self.read_key_values(output_path / "theme.conf")
                self.assertEqual(manifest["THEME_ID"], f"catppuccin-{variant}")
                self.assertEqual(manifest["THEME_NAME"], display_name)
                self.assertEqual(manifest["THEME_VERSION"], "1.8.0")
                self.assertEqual(manifest["THEME_AUTHOR"], "Catppuccin")

    def test_mocha_semantic_mapping_is_exact_and_normalized(self):
        result, output_path = self.run_adapter()
        self.assertEqual(result.returncode, 0, result.stderr)
        palette = self.read_key_values(output_path / "palette.conf")
        self.assertEqual(palette["XCALIBUR_DEFINITION_VERSION"], "1")
        self.assertEqual(
            {key: value for key, value in palette.items() if key != "XCALIBUR_DEFINITION_VERSION"},
            {
                "BACKGROUND": "#1E1E2E",
                "FOREGROUND": "#CDD6F4",
                "CURSOR": "#F5E0DC",
                "PRIMARY": "#89B4FA",
                "SECONDARY": "#CBA6F7",
                "ACCENT": "#B4BEFE",
                "SUCCESS": "#A6E3A1",
                "WARNING": "#F9E2AF",
                "ERROR": "#F38BA8",
                "MUTED": "#BAC2DE",
                "SURFACE": "#181825",
                "SURFACE_ALT": "#313244",
                "BORDER": "#45475A",
                "SELECTION": "#9399B2",
                "HIGHLIGHT": "#B4BEFE",
            },
        )

    def test_missing_fields_and_colors_are_rejected(self):
        source = json.loads(self.input_path.read_text(encoding="utf-8"))
        invalid_palettes = []

        missing_version = dict(source)
        del missing_version["version"]
        invalid_palettes.append(("missing version", missing_version))

        missing_colors = json.loads(json.dumps(source))
        del missing_colors["mocha"]["colors"]
        invalid_palettes.append(("missing colors", missing_colors))

        missing_required_color = json.loads(json.dumps(source))
        del missing_required_color["mocha"]["colors"]["base"]
        invalid_palettes.append(("missing required color", missing_required_color))

        missing_hex = json.loads(json.dumps(source))
        del missing_hex["mocha"]["colors"]["base"]["hex"]
        invalid_palettes.append(("missing hex", missing_hex))

        for name, palette in invalid_palettes:
            with self.subTest(case=name):
                input_path = self.root / f"{name.replace(' ', '-')}.json"
                input_path.write_text(json.dumps(palette), encoding="utf-8")
                result, output_path = self.run_adapter(input_path=input_path)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("catppuccin adapter:", result.stderr)
                self.assertFalse(output_path.exists())

    def test_invalid_hex_and_invalid_input_structures_are_rejected(self):
        source = json.loads(self.input_path.read_text(encoding="utf-8"))
        source["mocha"]["colors"]["base"]["hex"] = "#12345Z"
        self.input_path.write_text(json.dumps(source), encoding="utf-8")
        result, output_path = self.run_adapter()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid hex", result.stderr)
        self.assertFalse(output_path.exists())

        self.input_path.write_text("[]", encoding="utf-8")
        result, output_path = self.run_adapter(output_name="invalid-root")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("root", result.stderr)
        self.assertFalse(output_path.exists())

    def test_malformed_json_and_duplicate_object_keys_are_rejected(self):
        for name, content in (
            ("malformed", '{"version": "1.8.0",'),
            ("duplicate", '{"version":"1.8.0","version":"1.8.1"}'),
            ("non-finite-number", '{"version":"1.8.0","unused":1e99999}'),
        ):
            with self.subTest(case=name):
                self.input_path.write_text(content, encoding="utf-8")
                result, output_path = self.run_adapter(output_name=f"pack-{name}")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("catppuccin adapter:", result.stderr)
                self.assertFalse(output_path.exists())

    def test_unknown_and_incorrectly_cased_variants_are_rejected(self):
        for variant in ("unknown", "Mocha", "MOCHA"):
            with self.subTest(variant=variant):
                result, output_path = self.run_adapter(variant, output_name=f"pack-{variant}")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("unknown variant", result.stderr)
                self.assertFalse(output_path.exists())

    def test_oversized_input_is_rejected_before_json_parsing(self):
        self.input_path.write_bytes(b" " * (MAX_INPUT_BYTES + 1))
        result, output_path = self.run_adapter()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("1048576-byte size limit", result.stderr)
        self.assertFalse(output_path.exists())

    def test_cli_help_documents_the_input_size_limit(self):
        result = subprocess.run(
            ["python3", str(ADAPTER), "--help"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("1048576 bytes (1 MiB)", result.stdout)

    def test_invalid_manifest_version_is_rejected(self):
        source = json.loads(FIXTURE.read_text(encoding="utf-8"))
        source["version"] = "1.8.0$(touch /tmp/unsafe)"
        self.input_path.write_text(json.dumps(source), encoding="utf-8")
        result, output_path = self.run_adapter()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("semantic version", result.stderr)
        self.assertFalse(output_path.exists())


if __name__ == "__main__":
    unittest.main()
