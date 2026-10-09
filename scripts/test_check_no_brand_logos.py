"""Unit tests for tools/check_no_brand_logos.py (run by CI: python3 -m unittest discover -s scripts -p 'test_*.py')."""
import hashlib
import importlib.util
import os
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_spec = importlib.util.spec_from_file_location("check_no_brand_logos", os.path.join(ROOT, "tools", "check_no_brand_logos.py"))
guard = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(guard)


class CheckNoBrandLogosTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = self.tmp.name
        self.logo = b"\x89PNG\r\n\x1a\n synthetic stand-in for a brand logo"
        self.hashes = os.path.join(self.repo, "hashes.txt")
        with open(self.hashes, "w", encoding="utf-8") as f:
            f.write("# test list\n" + hashlib.sha256(self.logo).hexdigest() + "  brands\n\n")
        os.makedirs(os.path.join(self.repo, "App", "Assets"))
        with open(os.path.join(self.repo, "App", "Assets", "own.png"), "wb") as f:
            f.write(b"own badge, not a logo")

    def tearDown(self):
        self.tmp.cleanup()

    def run_guard(self):
        return guard.main([self.repo, "--hashes", self.hashes])

    def test_clean_checkout_passes(self):
        self.assertEqual(self.run_guard(), 0)

    def test_known_logo_fails_under_any_name(self):
        with open(os.path.join(self.repo, "App", "Assets", "renamed.webp"), "wb") as f:
            f.write(self.logo)
        self.assertEqual(self.run_guard(), 1)

    def test_logo_pack_artefacts_fail_by_name(self):
        for name in ("x.logopack.zip", "pack-2026100901.zip"):
            p = os.path.join(self.repo, name)
            with open(p, "wb") as f:
                f.write(b"zip")
            self.assertEqual(self.run_guard(), 1, name)
            os.remove(p)
        os.makedirs(os.path.join(self.repo, "logo-pack", "v1"))
        self.assertEqual(self.run_guard(), 1)

    def test_skipped_build_dirs(self):
        os.makedirs(os.path.join(self.repo, ".build"))
        with open(os.path.join(self.repo, ".build", "cached.png"), "wb") as f:
            f.write(self.logo)
        self.assertEqual(self.run_guard(), 0)

    def test_shipped_hash_list_is_hashes_only(self):
        hashes = guard.load_hashes(os.path.join(ROOT, "tools", "brand_logo_hashes.txt"))
        self.assertGreaterEqual(len(hashes), 700)
        self.assertTrue(all(len(h) == 64 for h in hashes))


if __name__ == "__main__":
    unittest.main()
