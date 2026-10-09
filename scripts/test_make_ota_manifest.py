#!/usr/bin/env python3
"""Tests for make_ota_manifest.py and the direct-install part of make_release_metadata.py (fixtures only, no network):
python3 -m unittest discover -s scripts -p 'test_*.py'"""
import contextlib
import datetime
import io
import json
import os
import plistlib
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_ota_manifest as mom  # noqa: E402

BASE = "https://github.com/Jecuro1/KLIMATICKET-APP/releases/download/v1.2.3"
UDIDS = ["00008110-001A2B3C4D5E801E", "00008030-000000000000AB01"]


def png(width, height):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + b"\x00\x00\x00" * width for _ in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def profile(devices=UDIDS, get_task_allow=False, all_devices=False, expires=None):
    plist = {"Name": "XC Ad Hoc: com.knitelarlberg.klimabilanz",
             "ExpirationDate": expires or datetime.datetime(2027, 10, 1, 12, 0, 0),
             "Entitlements": {"get-task-allow": get_task_allow}}
    if devices:
        plist["ProvisionedDevices"] = list(devices)
    if all_devices:
        plist["ProvisionsAllDevices"] = True
    return b"\x30\x80cms" + plistlib.dumps(plist) + b"\x00\x00sig"


def info(version="1.2.3", build="245", bundle="com.knitelarlberg.klimabilanz"):
    return plistlib.dumps({"CFBundleIdentifier": bundle, "CFBundleShortVersionString": version,
                           "CFBundleVersion": build, "CFBundleExecutable": "KlimaBilanz",
                           "MinimumOSVersion": "26.0", "NSCameraUsageDescription": "Für Tickets"})


def write_ipa(path, app_profile=None, widget_profile=None, plist=None, with_profiles=True):
    with zipfile.ZipFile(path, "w") as zf:
        zf.writestr("Payload/KlimaBilanz.app/Info.plist", plist or info())
        zf.writestr("Payload/KlimaBilanz.app/KlimaBilanz", b"\xcf\xfa\xed\xfe")
        zf.writestr("Payload/KlimaBilanz.app/PlugIns/KlimaBilanzWidgets.appex/Info.plist",
                    plistlib.dumps({"CFBundleExecutable": "KlimaBilanzWidgets", "CFBundleShortVersionString": "1.2.3",
                                    "CFBundleVersion": "245"}))
        zf.writestr("Payload/KlimaBilanz.app/PlugIns/KlimaBilanzWidgets.appex/KlimaBilanzWidgets", b"\xcf\xfa\xed\xfe")
        if with_profiles:
            zf.writestr("Payload/KlimaBilanz.app/embedded.mobileprovision", app_profile or profile())
            zf.writestr("Payload/KlimaBilanz.app/PlugIns/KlimaBilanzWidgets.appex/embedded.mobileprovision",
                        widget_profile or profile())


class Fixture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = os.path.join(self.tmp.name, "ota")
        os.makedirs(self.dir)
        self.ipa = os.path.join(self.dir, "KlimaBilanz-1.2.3-adhoc.ipa")
        with open(os.path.join(self.dir, "AppIcon-57.png"), "wb") as f:
            f.write(png(57, 57))
        with open(os.path.join(self.dir, "AppIcon-512.png"), "wb") as f:
            f.write(png(512, 512))
        self.env = dict(os.environ)
        for key in ("VERSION", "BUILD"):
            os.environ.pop(key, None)

    def tearDown(self):
        os.environ.clear()
        os.environ.update(self.env)
        self.tmp.cleanup()

    def run_main(self, *extra):
        out, err = io.StringIO(), io.StringIO()
        code = 0
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                mom.main(["--ipa", self.ipa, "--base-url", BASE + "/", *extra])
            except SystemExit as exit_:
                code = exit_.code
        return code, out.getvalue(), err.getvalue()


class ManifestTests(Fixture):
    def test_manifest_for_an_adhoc_build(self):
        write_ipa(self.ipa)
        code, out, err = self.run_main()
        self.assertEqual(code, 0, err)
        with open(os.path.join(self.dir, "manifest.plist"), "rb") as f:
            manifest = plistlib.load(f)
        item = manifest["items"][0]
        self.assertEqual(item["assets"], [
            {"kind": "software-package", "url": f"{BASE}/KlimaBilanz-1.2.3-adhoc.ipa"},
            {"kind": "display-image", "url": f"{BASE}/AppIcon-57.png", "needs-shine": False},
            {"kind": "full-size-image", "url": f"{BASE}/AppIcon-512.png", "needs-shine": False},
        ])
        self.assertEqual(item["metadata"], {"bundle-identifier": "com.knitelarlberg.klimabilanz", "bundle-version": "1.2.3",
                                            "kind": "software", "platform-identifier": "com.apple.platform.iphoneos",
                                            "title": "KlimaBilanz"})
        self.assertIn("2 Gerät(e) im Ad-hoc-Profil", out)
        self.assertIn("gültig bis 2027-10-01", out)
        for udid in UDIDS:
            self.assertNotIn(udid, out + err)
        # Plain XML plist, as iOS expects it.
        with open(os.path.join(self.dir, "manifest.plist"), "rb") as f:
            self.assertTrue(f.read().startswith(b"<?xml"))

    def test_version_cross_check(self):
        write_ipa(self.ipa)
        os.environ["VERSION"] = "1.2.4"
        code, _, err = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("VERSION=1.2.4", err)

    def test_rejects_non_adhoc_builds(self):
        cases = {
            "development": dict(app_profile=profile(get_task_allow=True)),
            "app store": dict(app_profile=profile(devices=[])),
            "enterprise": dict(widget_profile=profile(devices=[], all_devices=True)),
            "unsigned": dict(with_profiles=False),
            "foreign bundle": dict(plist=info(bundle="com.example.other")),
        }
        for name, kwargs in cases.items():
            with self.subTest(name):
                write_ipa(self.ipa, **kwargs)
                code, _, err = self.run_main()
                self.assertEqual(code, 1, err)
                self.assertIn("::error::", err)

    def test_widget_with_fewer_devices_warns(self):
        write_ipa(self.ipa, widget_profile=profile(devices=UDIDS[:1]))
        code, _, err = self.run_main()
        self.assertEqual(code, 0)
        self.assertIn("lists 1 devices", err)

    def test_soon_expiring_profile_warns(self):
        soon = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=5)).replace(tzinfo=None, microsecond=0)
        write_ipa(self.ipa, app_profile=profile(expires=soon))
        code, _, err = self.run_main()
        self.assertEqual(code, 0)
        self.assertIn("expires on", err)

    def test_icons_and_https_are_required(self):
        write_ipa(self.ipa)
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err), self.assertRaises(SystemExit):
            mom.main(["--ipa", self.ipa, "--base-url", "http://example.com"])
        self.assertIn("https", err.getvalue())
        os.remove(os.path.join(self.dir, "AppIcon-512.png"))
        code, _, err2 = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("AppIcon-512.png", err2)
        with open(os.path.join(self.dir, "AppIcon-512.png"), "wb") as f:
            f.write(png(256, 256))
        code, _, err3 = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("512×512", err3)


class ReleaseMetadataTests(Fixture):
    """make_release_metadata.py: otaManifestURL only together with an ad-hoc manifest of the same release."""

    def run_metadata(self, *extra):
        dist = os.path.join(self.tmp.name, "dist")
        os.makedirs(dist, exist_ok=True)
        unsigned = os.path.join(dist, "KlimaBilanz-1.2.3.ipa")
        write_ipa(unsigned, with_profiles=False)
        ents = os.path.join(self.tmp.name, "ents.plist")
        with open(ents, "wb") as f:
            plistlib.dump({"com.apple.security.application-groups": ["group.com.knitelarlberg.klimabilanz"]}, f)
        env = dict(os.environ, DOWNLOAD_BASE="https://github.com/Jecuro1/KLIMATICKET-APP/releases/latest/download",
                   IPA_DOWNLOAD_BASE=BASE, VERSION="1.2.3", BUILD="245")
        proc = subprocess.run([sys.executable, os.path.join(HERE, "make_release_metadata.py"), dist, "--strict",
                               "--entitlements", ents, *extra], capture_output=True, text=True, env=env)
        update = None
        if proc.returncode == 0:
            with open(os.path.join(dist, "update.json")) as f:
                update = json.load(f)
        return proc, update, dist

    def test_without_adhoc_build_nothing_changes(self):
        proc, update, dist = self.run_metadata()
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertNotIn("otaManifestURL", update)
        self.assertEqual(update["downloadURL"], f"{BASE}/KlimaBilanz-1.2.3.ipa")
        with open(os.path.join(dist, "RELEASE_NOTES.md")) as f:
            self.assertNotIn("Direkt installieren", f.read())

    def test_with_adhoc_build(self):
        write_ipa(self.ipa)
        self.assertEqual(self.run_main()[0], 0)
        manifest = os.path.join(self.dir, "manifest.plist")
        proc, update, dist = self.run_metadata("--ota-manifest", manifest, "--ota-manifest-url", f"{BASE}/manifest.plist")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(update["otaManifestURL"], f"{BASE}/manifest.plist")
        # The sideload path stays exactly as before.
        self.assertEqual(update["downloadURL"], f"{BASE}/KlimaBilanz-1.2.3.ipa")
        with open(os.path.join(dist, "altstore-source.json")) as f:
            self.assertNotIn("adhoc", f.read())
        with open(os.path.join(dist, "RELEASE_NOTES.md")) as f:
            self.assertIn("Direkt installieren", f.read())

    def test_mismatching_or_incomplete_arguments_fail(self):
        write_ipa(self.ipa, plist=info(version="1.2.2"))
        self.assertEqual(self.run_main()[0], 0)
        manifest = os.path.join(self.dir, "manifest.plist")
        proc, _, _ = self.run_metadata("--ota-manifest", manifest, "--ota-manifest-url", f"{BASE}/manifest.plist")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("the release is com.knitelarlberg.klimabilanz 1.2.3", proc.stderr)
        proc, _, _ = self.run_metadata("--ota-manifest", manifest)
        self.assertIn("belong together", proc.stderr)
        proc, _, _ = self.run_metadata("--ota-manifest", manifest, "--ota-manifest-url", "http://x/manifest.plist")
        self.assertIn("https URL", proc.stderr)


if __name__ == "__main__":
    unittest.main()
