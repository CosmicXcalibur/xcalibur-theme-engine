import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("xcalibur_package", ROOT / "scripts/package.py")
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="xcalibur-package-test-")
        self.addCleanup(self.temp.cleanup)
        self.prefix = Path(self.temp.name) / "prefix with spaces"
        self.prefix.mkdir()

    def test_install_cli_and_uninstall(self):
        target = package.install(self.prefix)
        result = subprocess.run([str(self.prefix / "bin/theme"), "version"],
                                text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("0.1.0", result.stdout)
        self.assertTrue((target / "engine/bin/theme").is_file())
        self.assertEqual(package.uninstall(self.prefix), target)
        self.assertFalse(target.exists())
        self.assertFalse((self.prefix / "bin/theme").is_symlink())

    def test_uninstall_preserves_changed_or_extra_files(self):
        target = package.install(self.prefix)
        path = target / "README.md"
        old = path.read_text()
        path.write_text("user edit")
        with self.assertRaisesRegex(ValueError, "changed"):
            package.uninstall(self.prefix)
        self.assertTrue(path.exists())
        path.write_text(old)
        extra = target / "user-empty-directory"
        extra.mkdir()
        with self.assertRaisesRegex(ValueError, "changed"):
            package.uninstall(self.prefix)
        extra.rmdir()
        package.uninstall(self.prefix)

    def test_collision_and_symlinked_prefix(self):
        package.install(self.prefix)
        with self.assertRaisesRegex(ValueError, "already exists"):
            package.install(self.prefix)
        alias = Path(self.temp.name) / "alias"
        alias.symlink_to(self.prefix, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "unsafe"):
            package.uninstall(alias)


if __name__ == "__main__":
    unittest.main()
