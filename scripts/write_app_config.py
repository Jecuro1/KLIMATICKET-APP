#!/usr/bin/env python3
"""Writes App/Resources/AppConfig.json from environment variables (CI) without clobbering local values."""
import json, os, sys

path = sys.argv[1] if len(sys.argv) > 1 else "App/Resources/AppConfig.json"
try:
    with open(path, encoding="utf-8") as f:
        config = json.load(f)
except FileNotFoundError:
    config = {}

mapping = {
    "SUPABASE_URL": "supabaseURL",
    "SUPABASE_ANON_KEY": "supabaseAnonKey",
    "UPDATE_MANIFEST_URL": "updateManifestURL",
    "TARIFFS_URL": "tariffsURL",
}
for env, key in mapping.items():
    value = os.environ.get(env, "").strip()
    if value:
        config[key] = value
    config.setdefault(key, "")

with open(path, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("AppConfig:", {k: ("<set>" if v else "") for k, v in config.items()})
