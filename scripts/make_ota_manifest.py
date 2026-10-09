#!/usr/bin/env python3
"""Writes the itms-services manifest (manifest.plist) for the ad-hoc .ipa – direct install on registered iPhones
(docs/DIREKT_INSTALLIEREN.md). Everything is read from the .ipa itself, and the .ipa must really be ad-hoc signed
(device list in embedded.mobileprovision, no get-task-allow): a development or unsigned build would only end in
iOS' "Installation nicht möglich".

  itms-services://?action=download-manifest&url=<HTTPS URL of manifest.plist>

Usage:
  make_ota_manifest.py --ipa FILE --base-url URL [--out FILE] [--display-image NAME] [--full-size-image NAME]

  --base-url         HTTPS folder that serves the .ipa and both icons (GitHub release download URL of the tag, or
                     OTA_BASE_URL/<tag> when the Worker proxies them, docs/DIREKT_INSTALLIEREN.md §Technik)
  --display-image    57 × 57 icon file name next to the .ipa (default AppIcon-57.png)
  --full-size-image  512 × 512 icon file name next to the .ipa (default AppIcon-512.png)

Environment: VERSION, BUILD – optional cross-check against the .ipa's Info.plist (mismatch = error).
"""
import argparse
import datetime
import os
import plistlib
import re
import struct
import sys
import zipfile

BUNDLE_ID = "com.knitelarlberg.klimabilanz"
APP_INFO_RE = re.compile(r"^Payload/([^/]+)\.app/Info\.plist$")


def fail(message):
    print(f"::error::{message}", file=sys.stderr)
    sys.exit(1)


def warn(message):
    print(f"::warning::{message}", file=sys.stderr)


def parse_profile(data):
    start, end = data.find(b"<?xml"), data.rfind(b"</plist>")
    if start < 0 or end < 0:
        return None
    return plistlib.loads(data[start:end + len(b"</plist>")])


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        return None
    return struct.unpack(">II", head[16:24])


def inspect_ipa(path):
    """Info.plist of the app plus a summary of every embedded profile (app and extensions)."""
    with zipfile.ZipFile(path) as zf:
        names = zf.namelist()
        apps = [n for n in names if APP_INFO_RE.match(n)]
        if len(apps) != 1:
            fail(f"Expected exactly one Payload/<name>.app in {path}, found {len(apps)}")
        info = plistlib.loads(zf.read(apps[0]))
        app_root = apps[0][: -len("Info.plist")]
        profiles = {}
        for name in names:
            if name.endswith("embedded.mobileprovision") and name.startswith(app_root):
                profile = parse_profile(zf.read(name))
                if profile is None:
                    fail(f"{name}: unreadable provisioning profile")
                profiles[name[len(app_root):] or "embedded.mobileprovision"] = profile
        executables = []
        for name in names:
            m = re.match(r"^(Payload/[^/]+\.app/(?:PlugIns|Extensions)/[^/]+\.appex/)Info\.plist$", name)
            if m:
                executables.append(m.group(1))
    if "embedded.mobileprovision" not in profiles:
        fail("The .ipa has no embedded.mobileprovision – it is not signed for devices (ad-hoc export missing?)")
    for appex in executables:
        key = appex[len(app_root):] + "embedded.mobileprovision"
        if key not in profiles:
            fail(f"{appex} has no embedded.mobileprovision – iOS would refuse the install")
    return info, profiles


def check_adhoc(profiles):
    """Returns (device count of the app's profile, earliest expiration)."""
    expirations, counts = [], {}
    for name, profile in sorted(profiles.items()):
        devices = profile.get("ProvisionedDevices") or []
        if profile.get("ProvisionsAllDevices"):
            fail(f"{name}: enterprise profile – this build is not an ad-hoc build")
        if not devices:
            fail(f"{name}: no device list – App Store profile? Direct install needs the ad-hoc export (release-testing)")
        if (profile.get("Entitlements") or {}).get("get-task-allow"):
            fail(f"{name}: development profile (get-task-allow) – the export method must be release-testing / ad-hoc")
        counts[name] = len(devices)
        exp = profile.get("ExpirationDate")
        if isinstance(exp, datetime.datetime):
            expirations.append(exp)
    app_count = counts.get("embedded.mobileprovision", 0)
    for name, count in counts.items():
        if count != app_count:
            warn(f"{name} lists {count} devices, the app's profile {app_count} – install only works on devices in both")
    return app_count, (min(expirations) if expirations else None)


def build_manifest(info, ipa_url, display_url, full_size_url, title):
    return {
        "items": [{
            "assets": [
                {"kind": "software-package", "url": ipa_url},
                {"kind": "display-image", "url": display_url, "needs-shine": False},
                {"kind": "full-size-image", "url": full_size_url, "needs-shine": False},
            ],
            "metadata": {
                "bundle-identifier": info["CFBundleIdentifier"],
                "bundle-version": str(info["CFBundleShortVersionString"]),
                "kind": "software",
                "platform-identifier": "com.apple.platform.iphoneos",
                "title": title,
            },
        }]
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ipa", required=True)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--out", help="default: manifest.plist next to the .ipa")
    parser.add_argument("--display-image", default="AppIcon-57.png")
    parser.add_argument("--full-size-image", default="AppIcon-512.png")
    parser.add_argument("--title", default="KlimaBilanz")
    args = parser.parse_args(argv)

    base = args.base_url.strip().rstrip("/")
    if not base.startswith("https://"):
        fail("--base-url must be https:// – iOS installs over the air only via HTTPS")
    if not os.path.isfile(args.ipa):
        fail(f"{args.ipa} not found")
    folder = os.path.dirname(os.path.abspath(args.ipa))
    for name, size in ((args.display_image, 57), (args.full_size_image, 512)):
        if "/" in name or not os.path.isfile(os.path.join(folder, name)):
            fail(f"{name} must lie next to the .ipa (it is published with it)")
        actual = png_size(os.path.join(folder, name))
        if actual != (size, size):
            fail(f"{name} must be a {size}×{size} PNG, is {actual}")

    info, profiles = inspect_ipa(args.ipa)
    bundle_id = info.get("CFBundleIdentifier", "")
    version = str(info.get("CFBundleShortVersionString", ""))
    build = str(info.get("CFBundleVersion", ""))
    if bundle_id != BUNDLE_ID:
        fail(f"CFBundleIdentifier is {bundle_id!r}, expected {BUNDLE_ID!r}")
    if not re.fullmatch(r"\d+(\.\d+){0,2}", version) or not build.isdigit():
        fail(f"Unexpected version/build in Info.plist: {version!r} ({build!r})")
    for env, actual in (("VERSION", version), ("BUILD", build)):
        expected = os.environ.get(env, "").strip()
        if expected and expected != actual:
            fail(f"{env}={expected} but the ad-hoc .ipa's Info.plist says {actual}")
    devices, expires = check_adhoc(profiles)

    quote = lambda name: name.replace(" ", "%20")  # noqa: E731 – file names are ours, only spaces could occur
    manifest = build_manifest(info, f"{base}/{quote(os.path.basename(args.ipa))}", f"{base}/{quote(args.display_image)}",
                              f"{base}/{quote(args.full_size_image)}", args.title)
    out = args.out or os.path.join(folder, "manifest.plist")
    with open(out, "wb") as f:
        plistlib.dump(manifest, f, fmt=plistlib.FMT_XML, sort_keys=True)

    print(f"manifest.plist: {bundle_id} {version} ({build}) · {devices} Gerät(e) im Ad-hoc-Profil"
          + (f" · Profil gültig bis {expires:%Y-%m-%d}" if expires else ""))
    now = datetime.datetime.now(datetime.timezone.utc)
    if expires and expires.tzinfo is None:
        now = now.replace(tzinfo=None)  # plistlib reads profile dates as naive UTC
    if expires and expires - now < datetime.timedelta(days=30):
        warn(f"The ad-hoc profile expires on {expires:%Y-%m-%d} – installed copies stop launching then")
    return 0


if __name__ == "__main__":
    sys.exit(main())
