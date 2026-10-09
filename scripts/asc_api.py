#!/usr/bin/env python3
"""App Store Connect API helper for direct install (ad-hoc OTA, docs/DIREKT_INSTALLIEREN.md).

Python standard library + the `openssl` command line (ES256 JWT). The repository is PUBLIC: nothing here ever prints
a key, a UDID or a device name – messages from Apple are redacted before they are shown.

Commands:
  key --out FILE
      Writes the API key as a clean PEM .p8 (mode 0600). Accepts ASC_KEY_P8 (the raw text of AuthKey_XXXX.p8, pasted
      on an iPhone – lost line breaks, spaces or "smart" dashes are repaired) or ASC_KEY_BASE64 (base64 of the file).
  register-device --event FILE | --udid-env NAME  [--name NAME]
      Registers an iPhone (platform IOS) – idempotent: an existing device stays, a disabled one is enabled again.
      The UDID comes from the workflow_dispatch event payload or an environment variable, never from the command line.
  refresh-adhoc --bundle-id ID [--bundle-id ID ...]
      Deletes ad-hoc profiles of these bundle ids that miss an enabled iPhone (or are no longer valid), so the next
      `xcodebuild -exportArchive -allowProvisioningUpdates` creates them again – with every registered device.
  devices
      Prints the number of enabled iPhones of the team (an ad-hoc export needs at least one).
  check-ipa FILE
      Compares the devices in the ad-hoc .ipa's profiles with the enabled iPhones of the team (counts only).

Environment: ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (a .p8 written by `key`) for the API commands.
"""
import argparse
import base64
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

API = "https://api.appstoreconnect.apple.com"
# Apple accepts tokens that live at most 20 minutes.
TOKEN_LIFETIME = 15 * 60

# Since 2018 (A12): 8 hex digits, dash, 16 hex digits. Before: 40 hex digits.
UDID_RE = re.compile(r"^(?:[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}|[0-9A-Fa-f]{40})$")
DEVICE_NAME_RE = re.compile(r"^[^\x00-\x1f\x7f<>\"\\]{1,50}$")
DASHES = "-‐‑‒–—―−"
PEM_RE = re.compile(
    r"[" + DASHES + r"]+\s*BEGIN ([A-Z ]+?)\s*[" + DASHES + r"]+(.*?)[" + DASHES + r"]+\s*END \1\s*[" + DASHES + r"]+",
    re.S,
)


class AscError(Exception):
    pass


def notice(kind, message):
    """GitHub annotation (::notice:: / ::warning:: / ::error::) – plain text outside Actions."""
    if os.environ.get("GITHUB_ACTIONS") == "true":
        print(f"::{kind}::{message}", file=sys.stderr)
    else:
        print(f"{kind}: {message}", file=sys.stderr)


# ---------------------------------------------------------------- key

def normalize_p8(raw):
    """Returns the key as PEM text with 64-column lines, from pasted PEM text or base64 of the .p8 file."""
    text = (raw or "").replace("\r", "").replace("﻿", "").strip()
    if not text:
        raise AscError("Der API-Schlüssel ist leer")
    if not PEM_RE.search(text):
        compact = re.sub(r"\s+", "", text)
        try:
            decoded = base64.b64decode(compact + "=" * (-len(compact) % 4), validate=True)
        except ValueError as error:
            raise AscError("Der API-Schlüssel ist weder .p8-Text noch Base64") from error
        if b"BEGIN" in decoded:
            text = decoded.decode("utf-8", "replace")
        elif decoded[:1] == b"\x30":
            # Only the base64 body was pasted (without BEGIN/END lines): it is the PKCS#8 key itself.
            text = "-----BEGIN PRIVATE KEY-----\n" + base64.b64encode(decoded).decode() + "\n-----END PRIVATE KEY-----"
        else:
            raise AscError("Der API-Schlüssel ist weder .p8-Text noch Base64")
    match = PEM_RE.search(text)
    if not match:
        raise AscError("Im API-Schlüssel fehlt „BEGIN PRIVATE KEY“ … „END PRIVATE KEY“")
    label = re.sub(r"\s+", " ", match.group(1)).strip()
    body = re.sub(r"\s+", "", match.group(2))
    try:
        der = base64.b64decode(body, validate=True)
    except ValueError as error:
        raise AscError("Der API-Schlüssel enthält ungültige Zeichen") from error
    if not der or der[:1] != b"\x30":
        raise AscError("Der API-Schlüssel ist beschädigt")
    body = base64.b64encode(der).decode()
    lines = [body[i:i + 64] for i in range(0, len(body), 64)]
    return f"-----BEGIN {label}-----\n" + "\n".join(lines) + f"\n-----END {label}-----\n"


def key_from_env(env=os.environ):
    raw = env.get("ASC_KEY_P8", "").strip() or env.get("ASC_KEY_BASE64", "").strip()
    if not raw:
        raise AscError("Weder ASC_KEY_P8 noch ASC_KEY_BASE64 ist gesetzt")
    return normalize_p8(raw)


def write_key(pem, path):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(pem)
    os.chmod(path, 0o600)
    openssl = shutil.which("openssl")
    if openssl:
        proc = subprocess.run([openssl, "pkey", "-in", path, "-noout"], capture_output=True)
        if proc.returncode != 0:
            raise AscError("openssl kann den API-Schlüssel nicht lesen – bitte die .p8-Datei vollständig einfügen")


# ---------------------------------------------------------------- JWT (ES256)

def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _der_length(der, i):
    first = der[i]
    if first < 0x80:
        return first, i + 1
    count = first & 0x7F
    if count == 0 or count > 2:
        raise AscError("ungültige DER-Länge")
    return int.from_bytes(der[i + 1:i + 1 + count], "big"), i + 1 + count


def der_to_raw_signature(der, size=32):
    """ECDSA signature: DER SEQUENCE { INTEGER r, INTEGER s } (openssl) → r || s, as JWS ES256 wants it."""
    if len(der) < 8 or der[0] != 0x30:
        raise AscError("unerwartete Signatur von openssl")
    length, i = _der_length(der, 1)
    if i + length != len(der):
        raise AscError("unerwartete Signaturlänge")
    out = b""
    for _ in range(2):
        if der[i] != 0x02:
            raise AscError("unerwartete Signatur von openssl")
        n, i = _der_length(der, i + 1)
        value = der[i:i + n].lstrip(b"\x00")
        i += n
        if len(value) > size:
            raise AscError("Signaturwert zu lang")
        out += value.rjust(size, b"\x00")
    if i != len(der):
        raise AscError("unerwartete Daten nach der Signatur")
    return out


def raw_to_der_signature(raw):
    """r || s → DER (for verifying with `openssl dgst -verify` in tests)."""
    def integer(b):
        b = b.lstrip(b"\x00") or b"\x00"
        if b[0] & 0x80:
            b = b"\x00" + b
        return b"\x02" + bytes([len(b)]) + b
    half = len(raw) // 2
    body = integer(raw[:half]) + integer(raw[half:])
    return b"\x30" + bytes([len(body)]) + body


def make_token(key_path, key_id, issuer_id, now=None, lifetime=TOKEN_LIFETIME, openssl="openssl"):
    if not key_id or not issuer_id:
        raise AscError("ASC_KEY_ID und ASC_ISSUER_ID müssen gesetzt sein")
    now = int(time.time() if now is None else now)
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer_id, "iat": now, "exp": now + lifetime, "aud": "appstoreconnect-v1"}
    signing_input = (b64url(json.dumps(header, separators=(",", ":")).encode()) + "."
                     + b64url(json.dumps(payload, separators=(",", ":")).encode()))
    proc = subprocess.run([openssl, "dgst", "-sha256", "-sign", key_path], input=signing_input.encode(),
                          capture_output=True)
    if proc.returncode != 0 or not proc.stdout:
        raise AscError("openssl konnte das Token nicht signieren (ist der Schlüssel ein EC-Schlüssel aus App Store Connect?)")
    return signing_input + "." + b64url(der_to_raw_signature(proc.stdout))


# ---------------------------------------------------------------- HTTP

class Client:
    """Minimal JSON:API client. `opener(request, timeout)` is injectable for tests; secrets are redacted in errors."""

    def __init__(self, token_factory, opener=None, base=API, redact=()):
        self.token_factory = token_factory
        self.opener = opener or urllib.request.urlopen
        self.base = base
        self.redact = [r for r in redact if r]
        self._token = None
        self._token_at = 0.0

    def _auth(self):
        if self._token is None or time.time() - self._token_at > TOKEN_LIFETIME - 120:
            self._token = self.token_factory()
            self._token_at = time.time()
        return self._token

    def scrub(self, text):
        for secret in self.redact:
            text = re.sub(re.escape(secret), "<…>", text, flags=re.I)
        return text

    def request(self, method, path, body=None, query=None):
        url = path if path.startswith("https://") else self.base + path
        if query:
            url += ("&" if "?" in url else "?") + urllib.parse.urlencode(query, safe="[],")
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", "Bearer " + self._auth())
        req.add_header("Accept", "application/json")
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with self.opener(req, timeout=60) as resp:
                raw = resp.read()
                return resp.status, (json.loads(raw) if raw else {})
        except urllib.error.HTTPError as error:
            raw = error.read() or b""
            try:
                payload = json.loads(raw)
            except ValueError:
                payload = {}
            return error.code, payload
        except urllib.error.URLError as error:
            raise AscError(f"App Store Connect nicht erreichbar ({error.reason})") from error

    def fail(self, what, status, payload):
        details = []
        for err in (payload or {}).get("errors", [])[:3]:
            details.append(" – ".join(str(x) for x in (err.get("title"), err.get("detail")) if x))
        hint = ""
        if status == 401:
            hint = " (Schlüssel-ID, Issuer-ID oder Schlüssel passen nicht zusammen)"
        elif status == 403:
            hint = " (der API-Schlüssel braucht die Rolle „Admin“)"
        raise AscError(self.scrub(f"{what}: HTTP {status}{hint}" + (": " + "; ".join(details) if details else "")))

    def get_all(self, path, query=None):
        items = []
        status, payload = self.request("GET", path, query=query)
        while True:
            if status != 200:
                self.fail(f"GET {path}", status, payload)
            items.extend(payload.get("data", []))
            nxt = (payload.get("links") or {}).get("next")
            if not nxt:
                return items
            status, payload = self.request("GET", nxt)


def client_from_env(env=os.environ, opener=None, redact=()):
    key_path = env.get("ASC_KEY_PATH", "")
    if not key_path or not os.path.isfile(key_path):
        raise AscError("ASC_KEY_PATH fehlt – zuerst `asc_api.py key --out …` ausführen")
    key_id, issuer = env.get("ASC_KEY_ID", "").strip(), env.get("ASC_ISSUER_ID", "").strip()
    return Client(lambda: make_token(key_path, key_id, issuer), opener=opener, redact=redact)


# ---------------------------------------------------------------- devices

def normalize_udid(value):
    udid = (value or "").strip().replace(" ", "")
    if not UDID_RE.match(udid):
        raise AscError("Das ist keine gültige UDID (8 Hex-Zeichen, Bindestrich, 16 Hex-Zeichen – oder bei älteren iPhones 40 Hex-Zeichen)")
    return udid.upper()


def normalize_name(value):
    name = re.sub(r"\s+", " ", (value or "").strip()) or "iPhone"
    if not DEVICE_NAME_RE.match(name):
        raise AscError("Gerätename: höchstens 50 Zeichen, ohne < > \" \\")
    return name


def ios_devices(client):
    return client.get_all("/v1/devices", {"filter[platform]": "IOS", "limit": "200"})


def register_device(client, udid, name):
    """Returns "created", "enabled" or "exists"."""
    udid = normalize_udid(udid)
    name = normalize_name(name)
    for device in ios_devices(client):
        attrs = device.get("attributes", {})
        if str(attrs.get("udid", "")).upper() != udid:
            continue
        if attrs.get("status") == "ENABLED":
            return "exists"
        body = {"data": {"type": "devices", "id": device["id"], "attributes": {"status": "ENABLED", "name": name}}}
        status, payload = client.request("PATCH", f"/v1/devices/{device['id']}", body)
        if status != 200:
            client.fail("Gerät aktivieren", status, payload)
        return "enabled"
    body = {"data": {"type": "devices", "attributes": {"name": name, "platform": "IOS", "udid": udid}}}
    status, payload = client.request("POST", "/v1/devices", body)
    if status == 409 and any(str(d.get("attributes", {}).get("udid", "")).upper() == udid for d in ios_devices(client)):
        # Registered meanwhile – Apple answers 409 ENTITY_ERROR. Any other 409 (e.g. the yearly device limit) fails.
        return "exists"
    if status != 201:
        client.fail("Gerät registrieren", status, payload)
    return "created"


def enabled_udids(client):
    return {str(d.get("attributes", {}).get("udid", "")).upper()
            for d in ios_devices(client) if d.get("attributes", {}).get("status") == "ENABLED"}


# ---------------------------------------------------------------- ad-hoc profiles

def refresh_adhoc(client, bundle_ids):
    """Deletes stale IOS_APP_ADHOC profiles of the given bundle ids. Returns a list of (bundle id, action) lines."""
    wanted = enabled_udids(client)
    report = []
    for identifier in bundle_ids:
        matches = [b for b in client.get_all("/v1/bundleIds", {"filter[identifier]": identifier, "limit": "200"})
                   if b.get("attributes", {}).get("identifier") == identifier]
        if not matches:
            report.append((identifier, "noch nicht registriert – der Export legt die App-ID an"))
            continue
        for bundle in matches:
            profiles = [p for p in client.get_all(f"/v1/bundleIds/{bundle['id']}/profiles", {"limit": "200"})
                        if p.get("attributes", {}).get("profileType") == "IOS_APP_ADHOC"]
            if not profiles:
                report.append((identifier, "kein Ad-hoc-Profil – der Export erstellt eines"))
            for profile in profiles:
                attrs = profile.get("attributes", {})
                devices = {str(d.get("attributes", {}).get("udid", "")).upper()
                           for d in client.get_all(f"/v1/profiles/{profile['id']}/devices", {"limit": "200"})}
                missing = len(wanted - devices)
                if attrs.get("profileState") == "ACTIVE" and missing == 0:
                    report.append((identifier, f"Ad-hoc-Profil aktuell ({len(devices)} Geräte)"))
                    continue
                status, payload = client.request("DELETE", f"/v1/profiles/{profile['id']}")
                if status not in (200, 204):
                    client.fail("Veraltetes Ad-hoc-Profil löschen", status, payload)
                reason = f"{missing} Gerät(e) fehlten" if missing else "Profil ungültig"
                report.append((identifier, f"veraltetes Ad-hoc-Profil gelöscht ({reason}) – der Export erstellt es neu"))
    return report


# ---------------------------------------------------------------- .ipa inspection

def parse_mobileprovision(data):
    start = data.find(b"<?xml")
    end = data.rfind(b"</plist>")
    if start < 0 or end < 0:
        raise AscError("embedded.mobileprovision enthält keine Property-List")
    return plistlib.loads(data[start:end + len(b"</plist>")])


def ipa_profiles(ipa_path):
    """{bundle path inside the .ipa: profile dict} for the app and every extension."""
    out = {}
    with zipfile.ZipFile(ipa_path) as zf:
        for name in zf.namelist():
            if name.endswith("/embedded.mobileprovision"):
                out[name[: -len("/embedded.mobileprovision")]] = parse_mobileprovision(zf.read(name))
    return out


def check_ipa(ipa_path, wanted=None):
    """Returns (lines, ok). `wanted` = enabled UDIDs of the team (None = unknown)."""
    profiles = ipa_profiles(ipa_path)
    if not profiles:
        return ["Die .ipa enthält kein Provisioning-Profil"], False
    lines, ok = [], True
    for path, profile in sorted(profiles.items()):
        name = path.split("/")[-1]
        devices = {str(u).upper() for u in profile.get("ProvisionedDevices", [])}
        if not devices or profile.get("ProvisionsAllDevices"):
            lines.append(f"{name}: kein Ad-hoc-Profil (keine Geräteliste)")
            ok = False
            continue
        if (profile.get("Entitlements") or {}).get("get-task-allow"):
            lines.append(f"{name}: Entwicklungsprofil statt Ad-hoc")
            ok = False
        line = f"{name}: {len(devices)} Gerät(e) im Profil"
        if wanted is not None:
            missing = len(set(wanted) - devices)
            line += f", {missing} registrierte(s) iPhone(s) fehlen" if missing else ", alle registrierten iPhones enthalten"
            ok = ok and missing == 0
        lines.append(line)
    return lines, ok


# ---------------------------------------------------------------- CLI

def udid_from_args(args):
    if args.event:
        with open(args.event, encoding="utf-8") as f:
            return str((json.load(f).get("inputs") or {}).get("udid", ""))
    return os.environ.get(args.udid_env or "", "")


def main(argv=None, opener=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p_key = sub.add_parser("key")
    p_key.add_argument("--out", required=True)
    p_reg = sub.add_parser("register-device")
    src = p_reg.add_mutually_exclusive_group(required=True)
    src.add_argument("--event", help="workflow_dispatch event payload (GITHUB_EVENT_PATH)")
    src.add_argument("--udid-env", help="name of the environment variable holding the UDID")
    p_reg.add_argument("--name", default="iPhone")
    p_ref = sub.add_parser("refresh-adhoc")
    p_ref.add_argument("--bundle-id", action="append", required=True)
    sub.add_parser("devices")
    p_chk = sub.add_parser("check-ipa")
    p_chk.add_argument("ipa")
    p_chk.add_argument("--offline", action="store_true", help="do not ask the API for the registered devices")
    args = parser.parse_args(argv)

    try:
        if args.command == "key":
            write_key(key_from_env(), args.out)
            print("API-Schlüssel gelesen.")
            return 0
        if args.command == "register-device":
            raw = udid_from_args(args)
            udid = normalize_udid(raw)
            name = normalize_name(args.name)
            client = client_from_env(opener=opener, redact=(raw.strip(), udid, name))
            result = register_device(client, udid, name)
            print({"created": "iPhone registriert.",
                   "enabled": "iPhone war deaktiviert und ist wieder aktiv.",
                   "exists": "iPhone war schon registriert – nichts zu tun."}[result])
            return 0
        if args.command == "refresh-adhoc":
            client = client_from_env(opener=opener)
            for identifier, action in refresh_adhoc(client, args.bundle_id):
                print(f"{identifier}: {action}")
            return 0
        if args.command == "devices":
            print(len(enabled_udids(client_from_env(opener=opener))))
            return 0
        if args.command == "check-ipa":
            wanted = None
            if not args.offline:
                try:
                    wanted = enabled_udids(client_from_env(opener=opener))
                except AscError as error:
                    notice("warning", f"Registrierte Geräte nicht abrufbar: {error}")
            lines, ok = check_ipa(args.ipa, wanted)
            for line in lines:
                print(line)
            if wanted is not None:
                print(f"Registrierte, aktive iPhones im Team: {len(wanted)}")
            return 0 if ok else 2
    except AscError as error:
        notice("error", str(error))
        return 1
    return 1


if __name__ == "__main__":
    sys.exit(main())
