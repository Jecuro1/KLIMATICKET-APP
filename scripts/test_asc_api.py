#!/usr/bin/env python3
"""Tests for asc_api.py (no network, throwaway keys): python3 -m unittest discover -s scripts -p 'test_*.py'"""
import base64
import contextlib
import io
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import urllib.error
import urllib.parse
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc_api  # noqa: E402

OPENSSL = shutil.which("openssl")
UDID_NEW = "00008110-001A2B3C4D5E801E"
UDID_OLD = "0123456789abcdef0123456789abcdef01234567"


def make_ec_key(folder):
    path = os.path.join(folder, "AuthKey_TEST.p8")
    ec = subprocess.run([OPENSSL, "ecparam", "-name", "prime256v1", "-genkey", "-noout"], capture_output=True, check=True)
    pk8 = subprocess.run([OPENSSL, "pkcs8", "-topk8", "-nocrypt"], input=ec.stdout, capture_output=True, check=True)
    with open(path, "wb") as f:
        f.write(pk8.stdout)
    return path


class FakeResponse:
    def __init__(self, status, payload):
        self.status = status
        self._body = json.dumps(payload).encode() if payload is not None else b""

    def read(self):
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class FakeAsc:
    """A tiny in-memory App Store Connect: devices, bundle ids, profiles (with device lists)."""

    def __init__(self):
        self.devices = []
        self.bundles = []
        self.profiles = {}   # id -> {"attributes": …, "bundle": id, "devices": [device ids]}
        self.calls = []
        self.page_size = 200
        self.fail_with = None
        self.next_id = 100

    def add_device(self, udid, status="ENABLED", platform="IOS"):
        self.next_id += 1
        device = {"type": "devices", "id": f"D{self.next_id}",
                  "attributes": {"udid": udid, "status": status, "platform": platform, "name": "x"}}
        self.devices.append(device)
        return device

    def __call__(self, request, timeout=None):
        url = urllib.parse.urlsplit(request.full_url)
        query = dict(urllib.parse.parse_qsl(url.query))
        body = json.loads(request.data) if request.data else None
        method = request.get_method()
        self.calls.append((method, url.path, query, body, dict(request.header_items())))
        if self.fail_with:
            status, payload = self.fail_with
            raise urllib.error.HTTPError(request.full_url, status, "err", {}, io.BytesIO(json.dumps(payload).encode()))
        path = url.path
        if method == "GET" and path == "/v1/devices":
            items = [d for d in self.devices if d["attributes"]["platform"] == query.get("filter[platform]", "IOS")]
            offset = int(query.get("cursor", "0"))
            page = items[offset:offset + self.page_size]
            links = {}
            if offset + self.page_size < len(items):
                links["next"] = f"https://api.appstoreconnect.apple.com/v1/devices?filter[platform]=IOS&cursor={offset + self.page_size}"
            return FakeResponse(200, {"data": page, "links": links})
        if method == "POST" and path == "/v1/devices":
            attrs = body["data"]["attributes"]
            if any(d["attributes"]["udid"].upper() == attrs["udid"].upper() for d in self.devices):
                return self._error(409, f"A device with number '{attrs['udid']}' already exists on this team.")
            device = self.add_device(attrs["udid"])
            device["attributes"]["name"] = attrs["name"]
            return FakeResponse(201, {"data": device})
        if method == "PATCH" and path.startswith("/v1/devices/"):
            device = next(d for d in self.devices if d["id"] == path.rsplit("/", 1)[1])
            device["attributes"].update(body["data"]["attributes"])
            return FakeResponse(200, {"data": device})
        if method == "GET" and path == "/v1/bundleIds":
            # Like Apple: filter[identifier] also matches longer identifiers.
            return FakeResponse(200, {"data": [b for b in self.bundles
                                               if b["attributes"]["identifier"].startswith(query["filter[identifier]"])]})
        if method == "GET" and path.startswith("/v1/bundleIds/") and path.endswith("/profiles"):
            bundle = path.split("/")[3]
            return FakeResponse(200, {"data": [{"type": "profiles", "id": pid, "attributes": p["attributes"]}
                                               for pid, p in self.profiles.items() if p["bundle"] == bundle]})
        if method == "GET" and path.startswith("/v1/profiles/") and path.endswith("/devices"):
            profile = self.profiles[path.split("/")[3]]
            return FakeResponse(200, {"data": [d for d in self.devices if d["id"] in profile["devices"]]})
        if method == "DELETE" and path.startswith("/v1/profiles/"):
            del self.profiles[path.rsplit("/", 1)[1]]
            return FakeResponse(204, None)
        return self._error(404, "not found")

    def _error(self, status, detail):
        raise urllib.error.HTTPError("https://api", status, "err", {},
                                     io.BytesIO(json.dumps({"errors": [{"title": "Error", "detail": detail}]}).encode()))


def fake_client(fake, redact=()):
    return asc_api.Client(lambda: "TOKEN", opener=fake, redact=redact)


class KeyTests(unittest.TestCase):
    def setUp(self):
        self.der = bytes([0x30, 0x81, 0x87]) + bytes(range(0x87))
        body = base64.b64encode(self.der).decode()
        self.pem = ("-----BEGIN PRIVATE KEY-----\n" + "\n".join(body[i:i + 64] for i in range(0, len(body), 64))
                    + "\n-----END PRIVATE KEY-----\n")

    def test_clean_pem_is_kept(self):
        self.assertEqual(asc_api.normalize_p8(self.pem), self.pem)

    def test_pasted_on_iphone_without_line_breaks(self):
        flat = self.pem.replace("\n", " ")
        self.assertEqual(asc_api.normalize_p8(flat), self.pem)

    def test_crlf_bom_and_smart_dashes(self):
        smart = "﻿" + self.pem.replace("-----BEGIN", "——BEGIN").replace("KEY-----\n", "KEY——\r\n", 1)
        self.assertEqual(asc_api.normalize_p8(smart), self.pem)

    def test_base64_of_the_file(self):
        self.assertEqual(asc_api.normalize_p8(base64.b64encode(self.pem.encode()).decode()), self.pem)
        wrapped = base64.encodebytes(self.pem.encode()).decode()   # with newlines every 76 characters
        self.assertEqual(asc_api.normalize_p8(wrapped), self.pem)

    def test_only_the_body_was_copied(self):
        body = "".join(self.pem.splitlines()[1:-1])
        self.assertEqual(asc_api.normalize_p8(body), self.pem)

    def test_garbage_is_rejected(self):
        for bad in ("", "   ", "hallo welt", "-----BEGIN PRIVATE KEY-----\n!!!\n-----END PRIVATE KEY-----"):
            with self.assertRaises(asc_api.AscError):
                asc_api.normalize_p8(bad)

    def test_env_prefers_raw_text(self):
        env = {"ASC_KEY_P8": self.pem.replace("\n", " "), "ASC_KEY_BASE64": "bm9wZQ=="}
        self.assertEqual(asc_api.key_from_env(env), self.pem)
        self.assertEqual(asc_api.key_from_env({"ASC_KEY_BASE64": base64.b64encode(self.pem.encode()).decode()}), self.pem)
        with self.assertRaises(asc_api.AscError):
            asc_api.key_from_env({})


@unittest.skipUnless(OPENSSL, "openssl not installed")
class JwtTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.key = make_ec_key(self.tmp)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def test_key_command_writes_private_file_openssl_can_read(self):
        with open(self.key) as f:
            pasted = f.read().replace("\n", " ")
        out = os.path.join(self.tmp, "out.p8")
        os.environ["ASC_KEY_P8"] = pasted
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(asc_api.main(["key", "--out", out]), 0)
        finally:
            del os.environ["ASC_KEY_P8"]
        self.assertEqual(os.stat(out).st_mode & 0o777, 0o600)
        subprocess.run([OPENSSL, "pkey", "-in", out, "-noout"], check=True)

    def test_es256_token_verifies_with_the_public_key(self):
        token = asc_api.make_token(self.key, "KEY123", "issuer-uuid", now=1_800_000_000)
        header_b64, payload_b64, sig_b64 = token.split(".")
        pad = lambda s: s + "=" * (-len(s) % 4)  # noqa: E731
        header = json.loads(base64.urlsafe_b64decode(pad(header_b64)))
        payload = json.loads(base64.urlsafe_b64decode(pad(payload_b64)))
        self.assertEqual(header, {"alg": "ES256", "kid": "KEY123", "typ": "JWT"})
        self.assertEqual(payload, {"iss": "issuer-uuid", "iat": 1_800_000_000, "exp": 1_800_000_000 + 900,
                                   "aud": "appstoreconnect-v1"})
        raw = base64.urlsafe_b64decode(pad(sig_b64))
        self.assertEqual(len(raw), 64)
        pub = os.path.join(self.tmp, "pub.pem")
        subprocess.run([OPENSSL, "pkey", "-in", self.key, "-pubout", "-out", pub], check=True)
        sig = os.path.join(self.tmp, "sig.der")
        with open(sig, "wb") as f:
            f.write(asc_api.raw_to_der_signature(raw))
        verify = subprocess.run([OPENSSL, "dgst", "-sha256", "-verify", pub, "-signature", sig],
                                input=f"{header_b64}.{payload_b64}".encode(), capture_output=True)
        self.assertEqual(verify.returncode, 0, verify.stderr)
        # A tampered payload must not verify.
        verify = subprocess.run([OPENSSL, "dgst", "-sha256", "-verify", pub, "-signature", sig],
                                input=f"{header_b64}.{payload_b64}x".encode(), capture_output=True)
        self.assertNotEqual(verify.returncode, 0)

    def test_many_signatures_roundtrip(self):
        # r or s with a leading zero byte / high bit set must still become exactly 32 bytes each.
        for i in range(40):
            token = asc_api.make_token(self.key, "K", "I", now=1_700_000_000 + i)
            raw = base64.urlsafe_b64decode(token.split(".")[2] + "==")
            self.assertEqual(len(raw), 64)
            self.assertEqual(asc_api.der_to_raw_signature(asc_api.raw_to_der_signature(raw)), raw)

    def test_rejects_missing_ids(self):
        with self.assertRaises(asc_api.AscError):
            asc_api.make_token(self.key, "", "issuer")


class DerTests(unittest.TestCase):
    def test_short_integers_are_left_padded(self):
        der = bytes([0x30, 0x08, 0x02, 0x02, 0x00, 0x80, 0x02, 0x02, 0x01, 0x02])
        self.assertEqual(asc_api.der_to_raw_signature(der), b"\x00" * 31 + b"\x80" + b"\x00" * 30 + b"\x01\x02")

    def test_garbage(self):
        for bad in (b"", b"\x31\x00", bytes([0x30, 0x09, 0x02, 0x01, 0x01, 0x02, 0x01, 0x01])):
            with self.assertRaises(asc_api.AscError):
                asc_api.der_to_raw_signature(bad)


class DeviceTests(unittest.TestCase):
    def test_udid_formats(self):
        self.assertEqual(asc_api.normalize_udid(" 00008110-001a2b3c4d5e801e "), UDID_NEW)
        self.assertEqual(asc_api.normalize_udid(UDID_OLD), UDID_OLD.upper())
        for bad in ("", "00008110001A2B3C4D5E801E", "00008110-001A2B3C4D5E801", "zz008110-001A2B3C4D5E801E",
                    UDID_OLD + "0", "'; rm -rf /"):
            with self.assertRaises(asc_api.AscError, msg=bad):
                asc_api.normalize_udid(bad)

    def test_names(self):
        self.assertEqual(asc_api.normalize_name("  Marcels   iPhone "), "Marcels iPhone")
        self.assertEqual(asc_api.normalize_name(""), "iPhone")
        self.assertEqual(asc_api.normalize_name("zwei\nZeilen"), "zwei Zeilen")
        for bad in ("x" * 51, "a<b", 'a"b', "tab\x00"):
            with self.assertRaises(asc_api.AscError):
                asc_api.normalize_name(bad)

    def test_register_creates_once(self):
        fake = FakeAsc()
        client = fake_client(fake)
        self.assertEqual(asc_api.register_device(client, UDID_NEW.lower(), "Marcels iPhone"), "created")
        self.assertEqual(asc_api.register_device(client, UDID_NEW, "Marcels iPhone"), "exists")
        self.assertEqual(len(fake.devices), 1)
        post = [c for c in fake.calls if c[0] == "POST"]
        self.assertEqual(post[0][3]["data"]["attributes"], {"name": "Marcels iPhone", "platform": "IOS", "udid": UDID_NEW})
        self.assertEqual(post[0][4]["Authorization"], "Bearer TOKEN")
        # The UDID never goes into a URL (nothing to leak through proxies or error messages).
        self.assertFalse(any(UDID_NEW.lower() in (c[1] + json.dumps(c[2])).lower() for c in fake.calls))

    def test_register_enables_disabled_device(self):
        fake = FakeAsc()
        fake.add_device(UDID_NEW, status="DISABLED")
        self.assertEqual(asc_api.register_device(fake_client(fake), UDID_NEW, "iPhone"), "enabled")
        self.assertEqual(fake.devices[0]["attributes"]["status"], "ENABLED")

    def test_register_follows_pagination(self):
        fake = FakeAsc()
        fake.page_size = 2
        for i in range(5):
            fake.add_device(f"00008110-00000000000000{i:02d}")
        fake.add_device(UDID_NEW)
        self.assertEqual(asc_api.register_device(fake_client(fake), UDID_NEW, "iPhone"), "exists")
        self.assertFalse(any(c[0] == "POST" for c in fake.calls))

    def test_conflict_for_another_reason_fails_and_is_redacted(self):
        fake = FakeAsc()
        original = fake.__call__

        def limit_reached(request, timeout=None):
            if request.get_method() == "POST":
                fake._error(409, f"Device '{UDID_NEW}' cannot be registered: the device limit was reached.")
            return original(request, timeout)

        client = asc_api.Client(lambda: "TOKEN", opener=limit_reached, redact=(UDID_NEW,))
        with self.assertRaises(asc_api.AscError) as ctx:
            asc_api.register_device(client, UDID_NEW, "iPhone")
        self.assertIn("HTTP 409", str(ctx.exception))
        self.assertNotIn(UDID_NEW, str(ctx.exception))
        self.assertNotIn(UDID_NEW.lower(), str(ctx.exception).lower())

    def test_auth_errors_explain_the_role(self):
        fake = FakeAsc()
        fake.fail_with = (403, {"errors": [{"title": "Forbidden", "detail": "not allowed"}]})
        with self.assertRaises(asc_api.AscError) as ctx:
            asc_api.register_device(fake_client(fake), UDID_NEW, "iPhone")
        self.assertIn("Admin", str(ctx.exception))

    def test_cli_reads_udid_from_event_and_never_prints_it(self):
        fake = FakeAsc()
        with tempfile.TemporaryDirectory() as tmp:
            event = os.path.join(tmp, "event.json")
            with open(event, "w") as f:
                json.dump({"inputs": {"udid": UDID_NEW.lower(), "name": "Marcels iPhone"}}, f)
            key = os.path.join(tmp, "k.p8")
            open(key, "w").close()
            env = {"ASC_KEY_PATH": key, "ASC_KEY_ID": "K", "ASC_ISSUER_ID": "I"}
            out, err = io.StringIO(), io.StringIO()
            old = dict(os.environ)
            os.environ.update(env)
            try:
                orig = asc_api.make_token
                asc_api.make_token = lambda *a, **k: "TOKEN"
                with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                    self.assertEqual(asc_api.main(["register-device", "--event", event, "--name", "Marcels iPhone"],
                                                  opener=fake), 0)
                    self.assertEqual(asc_api.main(["register-device", "--event", event], opener=fake), 0)
                    with open(event, "w") as f:
                        json.dump({"inputs": {"udid": "nope"}}, f)
                    self.assertEqual(asc_api.main(["register-device", "--event", event], opener=fake), 1)
            finally:
                asc_api.make_token = orig
                os.environ.clear()
                os.environ.update(old)
        text = out.getvalue() + err.getvalue()
        self.assertIn("iPhone registriert.", text)
        self.assertIn("schon registriert", text)
        self.assertNotIn(UDID_NEW.lower(), text.lower())
        self.assertNotIn("Marcels", text)
        self.assertEqual(len(fake.devices), 1)
        posted = [c[3] for c in fake.calls if c[0] == "POST"]
        self.assertEqual(posted[0]["data"]["attributes"]["name"], "Marcels iPhone")

    def test_cli_takes_the_name_from_the_event(self):
        fake = FakeAsc()
        with tempfile.TemporaryDirectory() as tmp:
            event = os.path.join(tmp, "event.json")
            with open(event, "w") as f:
                json.dump({"inputs": {"udid": UDID_NEW, "name": "  Arbeits-iPhone "}}, f)
            key = os.path.join(tmp, "k.p8")
            open(key, "w").close()
            old = dict(os.environ)
            os.environ.update({"ASC_KEY_PATH": key, "ASC_KEY_ID": "K", "ASC_ISSUER_ID": "I"})
            orig = asc_api.make_token
            asc_api.make_token = lambda *a, **k: "TOKEN"
            try:
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(asc_api.main(["register-device", "--event", event], opener=fake), 0)
            finally:
                asc_api.make_token = orig
                os.environ.clear()
                os.environ.update(old)
        self.assertEqual(fake.devices[0]["attributes"]["name"], "Arbeits-iPhone")


class DevicesCommandTests(unittest.TestCase):
    def test_counts_enabled_iphones_only(self):
        fake = FakeAsc()
        fake.add_device(UDID_NEW)
        fake.add_device(UDID_OLD, status="DISABLED")
        fake.add_device("00008030-0000000000000002", platform="MAC_OS")
        with tempfile.TemporaryDirectory() as tmp:
            key = os.path.join(tmp, "k.p8")
            open(key, "w").close()
            old = dict(os.environ)
            os.environ.update({"ASC_KEY_PATH": key, "ASC_KEY_ID": "K", "ASC_ISSUER_ID": "I"})
            orig = asc_api.make_token
            asc_api.make_token = lambda *a, **k: "TOKEN"
            out = io.StringIO()
            try:
                with contextlib.redirect_stdout(out):
                    self.assertEqual(asc_api.main(["devices"], opener=fake), 0)
            finally:
                asc_api.make_token = orig
                os.environ.clear()
                os.environ.update(old)
        self.assertEqual(out.getvalue().strip(), "1")


class ProfileTests(unittest.TestCase):
    def setUp(self):
        self.fake = FakeAsc()
        self.a = self.fake.add_device(UDID_NEW)
        self.b = self.fake.add_device(UDID_OLD)
        self.off = self.fake.add_device("00008030-0000000000000001", status="DISABLED")
        self.fake.bundles = [
            {"type": "bundleIds", "id": "B1", "attributes": {"identifier": "com.knitelarlberg.klimabilanz"}},
            {"type": "bundleIds", "id": "B2", "attributes": {"identifier": "com.knitelarlberg.klimabilanz.widgets"}},
        ]

    def profile(self, pid, bundle, devices, kind="IOS_APP_ADHOC", state="ACTIVE"):
        self.fake.profiles[pid] = {"bundle": bundle, "devices": [d["id"] for d in devices],
                                   "attributes": {"profileType": kind, "profileState": state, "name": pid}}

    def test_stale_profiles_are_deleted_current_ones_kept(self):
        self.profile("P-app-old", "B1", [self.a])                    # misses b
        self.profile("P-app-dev", "B1", [self.a], kind="IOS_APP_DEVELOPMENT")
        self.profile("P-widget", "B2", [self.a, self.b])              # complete (disabled device does not count)
        self.profile("P-widget-invalid", "B2", [self.a, self.b], state="INVALID")
        report = asc_api.refresh_adhoc(fake_client(self.fake),
                                       ["com.knitelarlberg.klimabilanz", "com.knitelarlberg.klimabilanz.widgets"])
        self.assertEqual(sorted(self.fake.profiles), ["P-app-dev", "P-widget"])
        text = "\n".join(f"{b}: {a}" for b, a in report)
        self.assertIn("klimabilanz: veraltetes Ad-hoc-Profil gelöscht (1 Gerät(e) fehlten)", text)
        self.assertIn("widgets: Ad-hoc-Profil aktuell (2 Geräte)", text)
        self.assertIn("Profil ungültig", text)

    def test_profiles_close_to_expiry_are_renewed(self):
        now = asc_api.datetime.datetime(2026, 10, 9, tzinfo=asc_api.datetime.timezone.utc)
        self.profile("P-app-soon", "B1", [self.a, self.b])
        self.fake.profiles["P-app-soon"]["attributes"]["expirationDate"] = "2026-10-30T12:00:00.000+0000"   # Apple's format
        self.profile("P-widget-long", "B2", [self.a, self.b])
        self.fake.profiles["P-widget-long"]["attributes"]["expirationDate"] = "2027-06-01T00:00:00Z"
        report = dict(asc_api.refresh_adhoc(fake_client(self.fake),
                                            ["com.knitelarlberg.klimabilanz", "com.knitelarlberg.klimabilanz.widgets"], now=now))
        self.assertEqual(sorted(self.fake.profiles), ["P-widget-long"])
        self.assertIn("Profil läuft bald ab", report["com.knitelarlberg.klimabilanz"])
        self.assertIn("aktuell", report["com.knitelarlberg.klimabilanz.widgets"])

    def test_profile_with_a_disabled_device_is_renewed(self):
        self.profile("P-app-extra", "B1", [self.a, self.b, self.off])
        report = dict(asc_api.refresh_adhoc(fake_client(self.fake), ["com.knitelarlberg.klimabilanz"]))
        self.assertNotIn("P-app-extra", self.fake.profiles)
        self.assertIn("1 deaktivierte(s) Gerät(e) enthalten", report["com.knitelarlberg.klimabilanz"])

    def test_expiry_parsing(self):
        now = asc_api.datetime.datetime(2026, 10, 9, tzinfo=asc_api.datetime.timezone.utc)
        self.assertTrue(asc_api.expires_soon("2026-10-20T00:00:00Z", now))
        self.assertTrue(asc_api.expires_soon("2026-10-20T00:00:00.000+0000", now))
        self.assertFalse(asc_api.expires_soon("2027-10-20T00:00:00.000+0000", now))
        self.assertTrue(asc_api.expires_soon("2026-01-01T00:00:00Z", now))   # already expired
        self.assertFalse(asc_api.expires_soon("2027-10-01T00:00:00Z", now))
        for unknown in (None, "", "morgen", 5):
            self.assertFalse(asc_api.expires_soon(unknown, now))

    def test_unregistered_bundle_and_missing_profile(self):
        self.fake.bundles = self.fake.bundles[1:]   # the app id itself is not registered yet
        report = dict(asc_api.refresh_adhoc(fake_client(self.fake),
                                            ["com.knitelarlberg.klimabilanz", "com.knitelarlberg.klimabilanz.widgets"]))
        self.assertIn("noch nicht registriert", report["com.knitelarlberg.klimabilanz"])
        self.assertIn("kein Ad-hoc-Profil", report["com.knitelarlberg.klimabilanz.widgets"])
        self.assertFalse(any(c[0] == "DELETE" for c in self.fake.calls))


def fake_profile(devices, get_task_allow=False, all_devices=False):
    plist = {"Name": "XC Ad Hoc: com.knitelarlberg.klimabilanz", "TeamIdentifier": ["ABCDE12345"],
             "Entitlements": {"get-task-allow": get_task_allow, "application-identifier": "ABCDE12345.com.knitelarlberg.klimabilanz"}}
    if devices:
        plist["ProvisionedDevices"] = devices
    if all_devices:
        plist["ProvisionsAllDevices"] = True
    # CMS envelope stand-in: binary bytes around the XML plist, like the real file.
    return b"\x30\x82\x01\x00garbage" + plistlib.dumps(plist) + b"\xa0\x82trailer"


def write_ipa(path, app_profile, widget_profile):
    with zipfile.ZipFile(path, "w") as zf:
        zf.writestr("Payload/KlimaBilanz.app/Info.plist", plistlib.dumps({"CFBundleIdentifier": "com.knitelarlberg.klimabilanz"}))
        if app_profile is not None:
            zf.writestr("Payload/KlimaBilanz.app/embedded.mobileprovision", app_profile)
        zf.writestr("Payload/KlimaBilanz.app/PlugIns/KlimaBilanzWidgets.appex/Info.plist", plistlib.dumps({}))
        if widget_profile is not None:
            zf.writestr("Payload/KlimaBilanz.app/PlugIns/KlimaBilanzWidgets.appex/embedded.mobileprovision", widget_profile)


class CheckIpaTests(unittest.TestCase):
    def test_counts_and_missing_devices(self):
        with tempfile.TemporaryDirectory() as tmp:
            ipa = os.path.join(tmp, "a.ipa")
            write_ipa(ipa, fake_profile([UDID_NEW.lower(), UDID_OLD]), fake_profile([UDID_NEW]))
            lines, ok = asc_api.check_ipa(ipa, {UDID_NEW, UDID_OLD.upper()})
            self.assertFalse(ok)
            self.assertIn("KlimaBilanz.app: 2 Gerät(e) im Profil, alle registrierten iPhones enthalten", lines)
            self.assertIn("KlimaBilanzWidgets.appex: 1 Gerät(e) im Profil, 1 registrierte(s) iPhone(s) fehlen", lines)
            self.assertFalse(any(UDID_NEW in line for line in lines))
            lines, ok = asc_api.check_ipa(ipa, None)
            self.assertTrue(ok)

    def test_development_and_enterprise_profiles_are_not_adhoc(self):
        with tempfile.TemporaryDirectory() as tmp:
            ipa = os.path.join(tmp, "a.ipa")
            write_ipa(ipa, fake_profile([UDID_NEW], get_task_allow=True), fake_profile([], all_devices=True))
            lines, ok = asc_api.check_ipa(ipa, None)
            self.assertFalse(ok)
            self.assertIn("KlimaBilanz.app: Entwicklungsprofil statt Ad-hoc", lines)
            self.assertIn("KlimaBilanzWidgets.appex: kein Ad-hoc-Profil (keine Geräteliste)", lines)
            write_ipa(ipa, None, None)
            self.assertEqual(asc_api.check_ipa(ipa, None), (["Die .ipa enthält kein Provisioning-Profil"], False))


if __name__ == "__main__":
    unittest.main()
