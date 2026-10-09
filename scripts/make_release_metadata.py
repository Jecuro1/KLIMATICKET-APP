#!/usr/bin/env python3
"""Creates the release metadata for a tagged build, derived from the FINAL sideload .ipa:

  dist/update.json           in-app updater manifest (KlimaCore.UpdateManifest)
  dist/altstore-source.json  AltStore / SideStore source (AltStore source format 2.x + legacy fields)
  dist/RELEASE_NOTES.md      GitHub release body
  dist/tariffs.json, dist/AppIcon.png

AltStore and SideStore refuse to install/update from a source unless
  * versions[0].version / buildVersion equal CFBundleShortVersionString / CFBundleVersion of the .ipa,
  * versions[0].sha256 (when present) matches the downloaded file, and
  * appPermissions lists EVERY entitlement embedded in the app and its extensions (except
    application-identifier / team-identifier) and EVERY "...UsageDescription" key of their Info.plists.
So nothing here is hard-coded: everything is read from the .ipa itself.

Usage:
  make_release_metadata.py <distdir> [--ipa FILE] [--entitlements PLIST ...] [--strict]
                           [--ota-manifest FILE --ota-manifest-url URL]

Direct install (ad-hoc OTA, docs/DIREKT_INSTALLIEREN.md): only when the signed ad-hoc build exists, CI passes its
manifest.plist (scripts/make_ota_manifest.py) and the HTTPS URL it is published under. update.json then carries
`otaManifestURL`, and the app offers „Jetzt installieren“ (itms-services). Without them nothing changes – the unsigned
.ipa and the AltStore/SideStore source stay exactly as they are.

Entitlements, in order of preference:
  1. --entitlements PLIST ...   plists extracted from the signed binaries (CI: `ldid -e`), merged
  2. `ldid -e` on every executable inside the .ipa (when ldid is on PATH)
  3. App/Supporting/*-Sideload.entitlements (what CI signs with) – warning; error with --strict

Environment:
  DOWNLOAD_BASE      base URL for update.json, altstore-source.json, tariffs.json, AppIcon.png (required)
  IPA_DOWNLOAD_BASE  base URL for the .ipa (default DOWNLOAD_BASE) – use the immutable per-tag URL so the
                     sha256 in the source always matches the file behind the URL
  VERSION, BUILD     optional cross-check against the .ipa's Info.plist (mismatch = error)
  MINIMUM_SUPPORTED_VERSION  optional, forces the update sheet for older installs
"""
import argparse
import datetime
import glob
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE_BUNDLE_ID = "com.knitelarlberg.klimabilanz"
SOURCE_IDENTIFIER = BASE_BUNDLE_ID + ".source"
TINT = "#1F8A70"
# AltStore's known app categories (anything else is shown as "Other" or rejected by older clients).
ALTSTORE_CATEGORIES = {"developer", "entertainment", "games", "lifestyle", "other", "photo-video", "social", "utilities"}
CATEGORY = "utilities"
# AltStore ignores these when comparing entitlements with the source (they are rewritten on re-signing).
IGNORED_ENTITLEMENTS = {"application-identifier", "com.apple.developer.team-identifier"}
FALLBACK_ENTITLEMENTS = [
    os.path.join(ROOT, "App", "Supporting", "KlimaBilanz-Sideload.entitlements"),
    os.path.join(ROOT, "App", "Supporting", "KlimaBilanzWidgets-Sideload.entitlements"),
]

APP_INFO_RE = re.compile(r"^Payload/([^/]+)\.app/Info\.plist$")
EXT_INFO_RE = re.compile(r"^Payload/[^/]+\.app/(?:PlugIns|Extensions)/([^/]+)\.appex/Info\.plist$")


def fail(message):
    print(f"::error::{message}", file=sys.stderr)
    sys.exit(1)


def warn(message):
    print(f"::warning::{message}", file=sys.stderr)


def iso_now():
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_plist_blob(data):
    """Parses a plist that may be surrounded by other bytes (ldid output, CMS envelope)."""
    data = data.strip()
    if not data:
        return {}
    if data.startswith(b"bplist"):
        return plistlib.loads(data)
    start = data.find(b"<?xml")
    if start < 0:
        start = data.find(b"<plist")
    end = data.rfind(b"</plist>")
    if start < 0 or end < 0:
        raise ValueError("no property list found")
    return plistlib.loads(data[start:end + len(b"</plist>")])


# ---------------------------------------------------------------- .ipa inspection

def read_bundles(zf):
    """Returns the main app bundle and its extensions: [{kind, name, root, info, executable}]."""
    names = set(zf.namelist())
    apps = [n for n in names if APP_INFO_RE.match(n)]
    if len(apps) != 1:
        fail(f"Expected exactly one Payload/<name>.app in the .ipa, found {len(apps)}: {sorted(apps)}")
    bundles = []
    for kind, info_path in [("app", apps[0])] + [("appex", n) for n in sorted(names) if EXT_INFO_RE.match(n)]:
        root = info_path[: -len("Info.plist")]
        info = plistlib.loads(zf.read(info_path))
        exe = info.get("CFBundleExecutable")
        if not exe or root + exe not in names:
            fail(f"{root}: executable {exe!r} missing in the .ipa")
        bundles.append({"kind": kind, "name": root.rstrip("/").split("/")[-1], "root": root,
                        "info": info, "executable": root + exe})
    return bundles


def entitlements_via_ldid(zf, bundles):
    ldid = shutil.which("ldid")
    if not ldid:
        return None
    result = []
    with tempfile.TemporaryDirectory() as tmp:
        for i, bundle in enumerate(bundles):
            path = os.path.join(tmp, f"bin{i}")
            with open(path, "wb") as f:
                f.write(zf.read(bundle["executable"]))
            proc = subprocess.run([ldid, "-e", path], capture_output=True)
            try:
                ents = parse_plist_blob(proc.stdout)
            except Exception as error:  # noqa: BLE001 – report and treat as "no entitlements"
                warn(f"ldid -e {bundle['executable']}: {error}")
                ents = {}
            if not ents:
                warn(f"{bundle['executable']} has no embedded entitlements (not ldid-signed?)")
            result.append((bundle["executable"], ents))
    return result


def entitlements_from_files(paths):
    result = []
    for path in paths:
        with open(path, "rb") as f:
            result.append((path, parse_plist_blob(f.read())))
    return result


def app_permissions(bundles, entitlement_sets):
    entitlements = set()
    for _, ents in entitlement_sets:
        if not isinstance(ents, dict):
            fail("Entitlements must be a dictionary plist")
        entitlements |= {k for k in ents if k not in IGNORED_ENTITLEMENTS}
    privacy = {}
    for bundle in bundles:  # app first, then extensions – the app's wording wins
        for key, value in bundle["info"].items():
            if "UsageDescription" in key:
                privacy.setdefault(key, str(value).strip())
    return {"entitlements": sorted(entitlements), "privacy": dict(sorted(privacy.items()))}


# ---------------------------------------------------------------- validation

def validate_source(source, ipa_info, ipa_size, ipa_sha):
    errors = []
    for key in ("name", "identifier", "apps"):
        if not source.get(key):
            errors.append(f"source.{key} missing")
    for app in source.get("apps", []):
        for key in ("name", "bundleIdentifier", "developerName", "localizedDescription", "iconURL", "versions", "appPermissions"):
            if key not in app:
                errors.append(f"app.{key} missing")
        if app.get("category") not in ALTSTORE_CATEGORIES:
            errors.append(f"app.category {app.get('category')!r} is not an AltStore category")
        if app.get("bundleIdentifier") != ipa_info.get("CFBundleIdentifier"):
            errors.append("app.bundleIdentifier != CFBundleIdentifier of the .ipa")
        versions = app.get("versions") or []
        if not versions:
            errors.append("app.versions empty")
        for v in versions[:1]:
            for key in ("version", "buildVersion", "date", "downloadURL", "size", "sha256", "minOSVersion", "localizedDescription"):
                if key not in v:
                    errors.append(f"versions[0].{key} missing")
            if v.get("version") != ipa_info.get("CFBundleShortVersionString"):
                errors.append("versions[0].version != CFBundleShortVersionString")
            if v.get("buildVersion") != str(ipa_info.get("CFBundleVersion")):
                errors.append("versions[0].buildVersion != CFBundleVersion")
            if not isinstance(v.get("size"), int) or v.get("size") != ipa_size:
                errors.append("versions[0].size != .ipa size")
            if v.get("sha256") != ipa_sha or not re.fullmatch(r"[0-9a-f]{64}", v.get("sha256", "")):
                errors.append("versions[0].sha256 invalid")
            if not str(v.get("downloadURL", "")).startswith("https://"):
                errors.append("versions[0].downloadURL must be https")
        perms = app.get("appPermissions", {})
        if not isinstance(perms.get("entitlements"), list) or not all(isinstance(e, str) for e in perms["entitlements"]):
            errors.append("appPermissions.entitlements must be a list of strings")
        if not isinstance(perms.get("privacy"), dict) or not all(isinstance(v, str) and v for v in perms["privacy"].values()):
            errors.append("appPermissions.privacy must map keys to non-empty usage descriptions")
    json.loads(json.dumps(source))  # round-trip: plain JSON types only
    if errors:
        fail("Invalid AltStore source:\n  " + "\n  ".join(errors))


# ---------------------------------------------------------------- direct install (ad-hoc OTA)

def ota_manifest_url(path, url):
    """The otaManifestURL for update.json, or None. Both arguments or neither."""
    if not path and not url:
        return None
    if not path or not url:
        fail("--ota-manifest and --ota-manifest-url belong together")
    url = url.strip()
    if not re.fullmatch(r"https://[^\s\"'<>]+/manifest\.plist", url):
        fail(f"--ota-manifest-url must be an https URL ending in /manifest.plist, got {url!r}")
    if not os.path.isfile(path):
        fail(f"{path} not found")
    return url


def check_ota_manifest(path, bundle_id, version):
    """The ad-hoc build must be the same release as the sideload .ipa – otherwise the app would offer another version."""
    with open(path, "rb") as f:
        manifest = plistlib.load(f)
    try:
        item = manifest["items"][0]
        meta = item["metadata"]
        package = next(a["url"] for a in item["assets"] if a["kind"] == "software-package")
    except (KeyError, IndexError, StopIteration, TypeError):
        fail(f"{path} is not an itms-services manifest")
    if meta.get("bundle-identifier") != bundle_id or str(meta.get("bundle-version")) != version:
        fail(f"{path} describes {meta.get('bundle-identifier')} {meta.get('bundle-version')}, the release is {bundle_id} {version}")
    if not str(package).startswith("https://"):
        fail(f"{path}: the .ipa URL must be https")


# ---------------------------------------------------------------- main

def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("dist")
    parser.add_argument("--ipa", help="the final sideload .ipa (default: newest *.ipa in <dist>)")
    parser.add_argument("--entitlements", nargs="+", action="extend", default=[], metavar="PLIST",
                        help="entitlement plists extracted from the signed binaries (ldid -e)")
    parser.add_argument("--strict", action="store_true", help="fail instead of falling back to the repo entitlements")
    parser.add_argument("--ota-manifest", metavar="FILE", help="manifest.plist of the ad-hoc build (direct install)")
    parser.add_argument("--ota-manifest-url", metavar="URL", help="HTTPS URL the manifest.plist is published under")
    args = parser.parse_args()
    ota_url = ota_manifest_url(args.ota_manifest, args.ota_manifest_url)

    dist = args.dist
    base = os.environ.get("DOWNLOAD_BASE", "").strip().rstrip("/")
    if not base:
        fail("DOWNLOAD_BASE is not set")
    ipa_base = (os.environ.get("IPA_DOWNLOAD_BASE", "").strip() or base).rstrip("/")

    ipas = [args.ipa] if args.ipa else sorted(glob.glob(os.path.join(dist, "*.ipa")), key=os.path.getmtime)
    if not ipas or not os.path.isfile(ipas[-1]):
        fail(f"No .ipa found in {dist}")
    ipa = ipas[-1]
    ipa_name = os.path.basename(ipa)
    size = os.path.getsize(ipa)
    sha = sha256_of(ipa)

    with zipfile.ZipFile(ipa) as zf:
        bundles = read_bundles(zf)
        if args.entitlements:
            entitlement_sets = entitlements_from_files(args.entitlements)
            origin = "files: " + ", ".join(args.entitlements)
        else:
            entitlement_sets = entitlements_via_ldid(zf, bundles)
            origin = "ldid -e"
            if entitlement_sets is None or not entitlement_sets[0][1]:
                message = "Could not read entitlements from the .ipa (ldid missing or app unsigned)"
                if args.strict:
                    fail(message)
                warn(message + " – falling back to App/Supporting/*-Sideload.entitlements")
                entitlement_sets = entitlements_from_files([p for p in FALLBACK_ENTITLEMENTS if os.path.exists(p)])
                origin = "fallback files"

    app_info = bundles[0]["info"]
    bundle_id = app_info.get("CFBundleIdentifier", "")
    version = str(app_info.get("CFBundleShortVersionString", ""))
    build = str(app_info.get("CFBundleVersion", ""))
    min_os = str(app_info.get("MinimumOSVersion") or "26.0")
    if bundle_id != BASE_BUNDLE_ID:
        fail(f"CFBundleIdentifier is {bundle_id!r}, expected {BASE_BUNDLE_ID!r}")
    if not re.fullmatch(r"\d+(\.\d+){0,2}", version) or not build.isdigit():
        fail(f"Unexpected version/build in Info.plist: {version!r} ({build!r})")
    for env, actual in (("VERSION", version), ("BUILD", build)):
        expected = os.environ.get(env, "").strip()
        if expected and expected != actual:
            fail(f"{env}={expected} but the .ipa's Info.plist says {actual} – AltStore would reject the source")
    for bundle in bundles[1:]:
        ext_version = (str(bundle["info"].get("CFBundleShortVersionString")), str(bundle["info"].get("CFBundleVersion")))
        if ext_version != (version, build):
            warn(f"{bundle['name']} has version {ext_version}, app has {(version, build)}")

    permissions = app_permissions(bundles, entitlement_sets)
    now = iso_now()

    notes_path = os.path.join(ROOT, "docs", "release-notes", f"{version}.md")
    if os.path.exists(notes_path):
        with open(notes_path, encoding="utf-8") as f:
            notes = [l.strip()[2:].strip() for l in f if l.strip().startswith("- ")]
    else:
        notes = []
    notes = notes or ["Verbesserungen und Fehlerbehebungen"]
    notes_text = "\n".join(f"• {n}" for n in notes)

    tariffs_src = os.path.join(ROOT, "App", "Resources", "tariffs.json")
    with open(tariffs_src, encoding="utf-8") as f:
        tariffs_version = json.load(f).get("version", 1)
    os.makedirs(dist, exist_ok=True)
    shutil.copy(tariffs_src, os.path.join(dist, "tariffs.json"))
    shutil.copy(os.path.join(ROOT, "App", "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png"),
                os.path.join(dist, "AppIcon.png"))

    ipa_url = f"{ipa_base}/{ipa_name}"
    icon_url = f"{base}/AppIcon.png"
    update = {
        "version": version,
        "build": int(build),
        "publishedAt": now,
        "minimumOSVersion": min_os,
        "bundleIdentifier": bundle_id,
        "downloadURL": ipa_url,
        "size": size,
        "sha256": sha,
        "altstoreSourceURL": f"{base}/altstore-source.json",
        "releaseNotes": notes,
        "tariffsVersion": tariffs_version,
        "tariffsURL": f"{base}/tariffs.json",
        "tariffsSHA256": sha256_of(tariffs_src),
    }
    if ota_url:
        check_ota_manifest(args.ota_manifest, bundle_id, version)
        update["otaManifestURL"] = ota_url
    minimum_supported = os.environ.get("MINIMUM_SUPPORTED_VERSION", "").strip()
    if minimum_supported:
        # KlimaCore.SemanticVersion only decodes "1", "1.2" or "1.2.3" – anything else would make EVERY installed
        # app fail to decode update.json (no update hints at all). A minimum above this release would force the
        # non-dismissible update sheet even on the newest version, forever.
        normalized = minimum_supported[1:] if minimum_supported[:1] in ("v", "V") else minimum_supported
        if not re.fullmatch(r"\d+(\.\d+){0,2}", normalized):
            fail(f"MINIMUM_SUPPORTED_VERSION={minimum_supported!r} is not a version like 1.2.0")

        def version_tuple(v):
            parts = [int(p) for p in v.split(".")]
            return tuple(parts + [0] * (3 - len(parts)))

        if version_tuple(normalized) > version_tuple(version):
            fail(f"MINIMUM_SUPPORTED_VERSION={normalized} is newer than this release ({version})")
        update["minimumSupportedVersion"] = normalized

    description = ("Erfasse deine Fahrten und sieh auf einen Blick, ob sich dein KlimaTicket schon rentiert hat. "
                   "Neue Versionen erscheinen hier automatisch – ein Tipp auf „Aktualisieren“, und die App ist aktuell.")
    source = {
        "name": "KlimaBilanz",
        "identifier": SOURCE_IDENTIFIER,
        "subtitle": "Hat sich dein KlimaTicket schon rentiert?",
        "description": "Offizielle Quelle für KlimaBilanz-Updates.",
        "iconURL": icon_url,
        "tintColor": TINT,
        "featuredApps": [bundle_id],
        "apps": [{
            "name": "KlimaBilanz",
            "bundleIdentifier": bundle_id,
            "developerName": "Knitel Arlberg",
            "subtitle": "Dein KlimaTicket-Tracker",
            "localizedDescription": description,
            "iconURL": icon_url,
            "tintColor": TINT,
            "category": CATEGORY,
            "versions": [{
                "version": version,
                "buildVersion": build,
                "date": now,
                "localizedDescription": notes_text,
                "downloadURL": ipa_url,
                "size": size,
                "sha256": sha,
                "minOSVersion": min_os,
            }],
            "appPermissions": permissions,
            # Legacy single-version fields for older AltStore/SideStore releases (ignored when "versions" is understood).
            "version": version,
            "versionDate": now,
            "versionDescription": notes_text,
            "downloadURL": ipa_url,
            "size": size,
        }],
        "news": [],
    }
    website = os.environ.get("SOURCE_WEBSITE", "").strip()
    if website:
        source["website"] = website

    validate_source(source, app_info, size, sha)

    with open(os.path.join(dist, "update.json"), "w", encoding="utf-8") as f:
        json.dump(update, f, indent=2, ensure_ascii=False)
        f.write("\n")
    with open(os.path.join(dist, "altstore-source.json"), "w", encoding="utf-8") as f:
        json.dump(source, f, indent=2, ensure_ascii=False)
        f.write("\n")
    with open(os.path.join(dist, "RELEASE_NOTES.md"), "w", encoding="utf-8") as f:
        f.write(f"## KlimaBilanz {version} (Build {build})\n\n" + "\n".join(f"- {n}" for n in notes) + "\n\n"
                f"SHA-256 (`{ipa_name}`): `{sha}`\n"
                + ("\nDirekt installieren (registrierte iPhones, ohne AltStore/SideStore): in der App unter "
                   "Einstellungen › Updates oder über die Installationsseite – docs/DIREKT_INSTALLIEREN.md\n" if ota_url else ""))

    print(f"Bundles: {', '.join(b['name'] for b in bundles)} · entitlements from {origin}")
    print("appPermissions:", json.dumps(permissions, indent=2, ensure_ascii=False))
    print(json.dumps(update, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
