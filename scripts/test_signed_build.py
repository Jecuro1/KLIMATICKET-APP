#!/usr/bin/env python3
"""Control-flow tests for signed_build.sh with stubbed xcodebuild / sips / asc_api.py (no Apple account needed):
python3 -m unittest discover -s scripts -p 'test_*.py'

What only Apple can answer (cloud signing, the real profiles) is out of reach here; these tests pin down what the
script does around it: which exports run, that a failure never fails the job, and what lands in dist/ota."""
import os
import plistlib
import shutil
import stat
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
BASH = shutil.which("bash")

XCODEBUILD = r"""#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG"
if [ "$1" = "archive" ]; then
  [ "${STUB_ARCHIVE_FAIL:-0}" = 1 ] && { echo "error: archive failed"; exit 65; }
  mkdir -p build/KlimaBilanz.xcarchive; exit 0
fi
OPTS=""; OUT=""
while [ $# -gt 0 ]; do
  case "$1" in -exportOptionsPlist) OPTS="$2"; shift;; -exportPath) OUT="$2"; shift;; esac; shift
done
cp "$OPTS" "$STUB_DIR/$(basename "$OPTS")"
if grep -q "release-testing" "$OPTS"; then
  [ "${STUB_ADHOC_FAIL:-0}" = 1 ] && { echo "error: No profiles for 'com.knitelarlberg.klimabilanz' were found"; exit 70; }
  mkdir -p "$OUT"; echo ipa > "$OUT/KlimaBilanz.ipa"; exit 0
fi
[ "${STUB_TF_FAIL:-0}" = 1 ] && { echo "error: No suitable application records were found"; exit 70; }
exit 0
"""

SIPS = r"""#!/usr/bin/env bash
echo "sips $*" >> "$STUB_LOG"
while [ $# -gt 0 ]; do [ "$1" = "--out" ] && { echo png > "$2"; exit 0; }; shift; done
exit 1
"""

ASC = r"""#!/usr/bin/env python3
import os, sys
cmd = sys.argv[1]
with open(os.environ["STUB_LOG"], "a") as f:
    f.write("asc " + " ".join(sys.argv[1:]) + "\n")
if cmd == "key":
    if os.environ.get("STUB_KEY_FAIL") == "1":
        sys.exit(1)
    open(sys.argv[sys.argv.index("--out") + 1], "w").write("KEY")
elif cmd == "devices":
    print(os.environ.get("STUB_DEVICES", "1"))
elif cmd == "check-ipa":
    print("KlimaBilanz.app: 1 Gerät(e) im Profil, alle registrierten iPhones enthalten")
    sys.exit(int(os.environ.get("STUB_CHECK", "0")))
"""


@unittest.skipUnless(BASH, "bash not installed")
class SignedBuildTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = self.tmp.name
        self.repo = os.path.join(root, "repo")
        self.bin = os.path.join(root, "bin")
        self.stub_dir = os.path.join(root, "stub")
        for d in (self.bin, self.stub_dir, os.path.join(self.repo, "scripts"),
                  os.path.join(self.repo, "App/Resources/Assets.xcassets/AppIcon.appiconset")):
            os.makedirs(d)
        shutil.copy(os.path.join(HERE, "signed_build.sh"), os.path.join(self.repo, "scripts"))
        self.write(os.path.join(self.repo, "scripts/asc_api.py"), ASC)
        self.write(os.path.join(self.bin, "xcodebuild"), XCODEBUILD, executable=True)
        self.write(os.path.join(self.bin, "sips"), SIPS, executable=True)
        self.write(os.path.join(self.repo, "App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"), "png")
        self.log = os.path.join(root, "calls.log")
        self.summary = os.path.join(root, "summary.md")
        open(self.log, "w").close()

    def tearDown(self):
        self.tmp.cleanup()

    @staticmethod
    def write(path, text, executable=False):
        with open(path, "w") as f:
            f.write(text)
        if executable:
            os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)

    def run_build(self, **env):
        full = dict(os.environ, PATH=self.bin + os.pathsep + os.environ["PATH"], STUB_LOG=self.log, STUB_DIR=self.stub_dir,
                    RUNNER_TEMP=self.tmp.name, GITHUB_STEP_SUMMARY=self.summary, APPLE_TEAM_ID="ABCDE12345",
                    ASC_KEY_ID="KEYID", ASC_ISSUER_ID="issuer", VERSION="1.2.3", BUILD="245")
        full.update(env)
        proc = subprocess.run([BASH, "scripts/signed_build.sh"], cwd=self.repo, env=full, capture_output=True, text=True)
        with open(self.log) as f:
            calls = f.read()
        with open(self.summary) as f:
            summary = f.read()
        return proc, calls, summary

    def ota_files(self):
        ota = os.path.join(self.repo, "dist/ota")
        return sorted(os.listdir(ota)) if os.path.isdir(ota) else []

    def options(self, name):
        with open(os.path.join(self.stub_dir, name), "rb") as f:
            return plistlib.load(f)

    def test_release_builds_testflight_and_adhoc(self):
        proc, calls, summary = self.run_build(ADHOC="true")
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertEqual(self.ota_files(), ["AppIcon-512.png", "AppIcon-57.png", "KlimaBilanz-1.2.3-adhoc.ipa"])
        lines = calls.splitlines()
        self.assertEqual(sum(line.startswith("archive ") for line in lines), 1, "one archive for both exports")
        self.assertEqual(sum(line.startswith("-exportArchive ") for line in lines), 2)
        for line in calls.splitlines():
            if line.startswith(("archive", "-exportArchive")):
                self.assertIn("-allowProvisioningUpdates -authenticationKeyPath", line)
                self.assertIn("-authenticationKeyID KEYID -authenticationKeyIssuerID issuer", line)
        self.assertIn("asc refresh-adhoc --bundle-id com.knitelarlberg.klimabilanz --bundle-id com.knitelarlberg.klimabilanz.widgets",
                      calls)
        self.assertLess(calls.index("refresh-adhoc"), calls.index("ExportOptions-AdHoc"))
        adhoc = self.options("ExportOptions-AdHoc.plist")
        self.assertEqual((adhoc["method"], adhoc["destination"], adhoc["signingStyle"], adhoc["teamID"]),
                         ("release-testing", "export", "automatic", "ABCDE12345"))
        testflight = self.options("ExportOptions-TestFlight.plist")
        self.assertEqual((testflight["method"], testflight["destination"]), ("app-store-connect", "upload"))
        self.assertIn("sips -s format png -z 57 57", calls)
        self.assertIn("✅ Ad-hoc-.ipa für 1 registrierte(s) iPhone(s)", summary)
        # The key file is removed when the script ends.
        self.assertFalse(os.path.exists(os.path.join(self.tmp.name, "AuthKey_KEYID.p8")))

    def test_non_release_runs_skip_adhoc(self):
        proc, calls, _ = self.run_build()
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(sum(line.startswith("-exportArchive ") for line in calls.splitlines()), 1)
        self.assertEqual(self.ota_files(), [])

    def test_testflight_can_be_switched_off(self):
        proc, calls, summary = self.run_build(ADHOC="true", TESTFLIGHT="false")
        self.assertEqual(proc.returncode, 0)
        self.assertNotIn("ExportOptions-TestFlight", calls)
        self.assertIn("übersprungen", summary)
        self.assertEqual(len(self.ota_files()), 3)

    def test_failures_never_fail_the_job(self):
        for env, expected in (({"STUB_KEY_FAIL": "1"}, "API-Schlüssel"),
                              ({"STUB_ARCHIVE_FAIL": "1"}, "Archiv"),
                              ({"STUB_TF_FAIL": "1"}, "TestFlight"),
                              ({"STUB_ADHOC_FAIL": "1"}, "Direkt installieren")):
            with self.subTest(expected):
                open(self.log, "w").close()
                open(self.summary, "w").close()
                proc, _, summary = self.run_build(ADHOC="true", **env)
                self.assertEqual(proc.returncode, 0, proc.stderr)
                self.assertIn(f"::error title={expected}::", proc.stdout)
                self.assertIn(f"| {expected} | ❌", summary)
        # A failed TestFlight upload still produces the ad-hoc build (the last run above failed the ad-hoc export).
        open(self.log, "w").close()
        self.run_build(ADHOC="true", STUB_TF_FAIL="1")
        self.assertEqual(len(self.ota_files()), 3)
        self.run_build(ADHOC="true", STUB_ADHOC_FAIL="1")
        self.assertEqual(self.ota_files(), [], "a failed export leaves no stale ad-hoc files behind")

    def test_no_registered_iphone_yet(self):
        proc, calls, summary = self.run_build(ADHOC="true", STUB_DEVICES="0")
        self.assertEqual(proc.returncode, 0)
        self.assertNotIn("ExportOptions-AdHoc", calls)
        self.assertIn("noch kein iPhone registriert", summary)
        self.assertEqual(self.ota_files(), [])

    def test_incomplete_profile_is_published_with_a_warning(self):
        proc, _, summary = self.run_build(ADHOC="true", STUB_CHECK="2")
        self.assertEqual(proc.returncode, 0)
        self.assertIn("::warning title=Direkt installieren::", proc.stdout)
        self.assertIn("⚠️", summary)
        self.assertEqual(len(self.ota_files()), 3)


if __name__ == "__main__":
    unittest.main()
