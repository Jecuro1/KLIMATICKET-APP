#!/usr/bin/env python3
"""Creates update.json (in-app updater), altstore-source.json (AltStore/SideStore auto-updates)
and RELEASE_NOTES.md for a tagged release. Usage: make_release_metadata.py <distdir>"""
import datetime, glob, json, os, sys

dist = sys.argv[1]
version = os.environ["VERSION"]
build = int(os.environ["BUILD"])
base = os.environ["DOWNLOAD_BASE"].rstrip("/")
ipa = sorted(glob.glob(os.path.join(dist, "*.ipa")))[-1]
ipa_name = os.path.basename(ipa)
size = os.path.getsize(ipa)
now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

notes_path = os.path.join("docs", "release-notes", f"{version}.md")
if os.path.exists(notes_path):
    notes = [l.strip()[2:].strip() for l in open(notes_path, encoding="utf-8") if l.strip().startswith("- ")]
else:
    notes = ["Verbesserungen und Fehlerbehebungen"]

import shutil
with open(os.path.join("App", "Resources", "tariffs.json"), encoding="utf-8") as f:
    tariffs_version = json.load(f).get("version", 1)
shutil.copy(os.path.join("App", "Resources", "tariffs.json"), os.path.join(dist, "tariffs.json"))
shutil.copy(os.path.join("App", "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png"), os.path.join(dist, "AppIcon.png"))

update = {
    "version": version,
    "build": build,
    "publishedAt": now,
    "minimumOSVersion": "26.0",
    "downloadURL": f"{base}/{ipa_name}",
    "altstoreSourceURL": f"{base}/altstore-source.json",
    "releaseNotes": notes,
    "tariffsVersion": tariffs_version,
    "tariffsURL": f"{base}/tariffs.json",
}
source = {
    "name": "KlimaBilanz",
    "identifier": "com.knitelarlberg.klimabilanz.source",
    "subtitle": "Hat sich dein KlimaTicket schon rentiert?",
    "description": "Offizielle Quelle für KlimaBilanz-Updates.",
    "iconURL": f"{base}/AppIcon.png",
    "tintColor": "#1F8A70",
    "apps": [{
        "name": "KlimaBilanz",
        "bundleIdentifier": "com.knitelarlberg.klimabilanz",
        "developerName": "Knitel Arlberg",
        "subtitle": "Dein KlimaTicket-Tracker",
        "localizedDescription": "Erfasse deine Fahrten und sieh auf einen Blick, ob sich dein KlimaTicket schon rentiert hat.",
        "iconURL": f"{base}/AppIcon.png",
        "tintColor": "#1F8A70",
        "category": "travel",
        "versions": [{
            "version": version,
            "buildVersion": str(build),
            "date": now,
            "localizedDescription": "\n".join(f"• {n}" for n in notes),
            "downloadURL": f"{base}/{ipa_name}",
            "size": size,
            "minOSVersion": "26.0",
        }],
        "appPermissions": {
            "entitlements": ["com.apple.security.application-groups"],
            "privacy": {"NSLocationWhenInUseUsageDescription": "Nächstgelegene Haltestelle vorschlagen"},
        },
    }],
    "news": [],
}
with open(os.path.join(dist, "update.json"), "w", encoding="utf-8") as f:
    json.dump(update, f, indent=2, ensure_ascii=False)
with open(os.path.join(dist, "altstore-source.json"), "w", encoding="utf-8") as f:
    json.dump(source, f, indent=2, ensure_ascii=False)
with open(os.path.join(dist, "RELEASE_NOTES.md"), "w", encoding="utf-8") as f:
    f.write(f"## KlimaBilanz {version} (Build {build})\n\n" + "\n".join(f"- {n}" for n in notes) + "\n")
print(json.dumps(update, indent=2, ensure_ascii=False))
