#!/usr/bin/env python3
"""Writes App/Resources/AppConfig.json from environment variables (CI) without clobbering local values.

Keys (docs/CLOUDFLARE_BACKEND.md §5.2):
  apiBaseURL         cloud backend origin. Source, in this order:
                       1. API_BASE_URL (repository variable, e.g. a custom domain),
                       2. CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID → the account's workers.dev subdomain
                          → https://klimabilanz-api.<subdomain>.workers.dev (API_WORKER_NAME overrides the name),
                       3. the value already in the file (empty in the repo → the app runs local-only).
                     Must be https:// without path, query or fragment; anything else → warning and "".
                     A failing GET <url>/v1/health is only a warning (the backend may be deployed later).
  updateManifestURL  UPDATE_MANIFEST_URL
  tariffsURL         TARIFFS_URL
The Supabase-era keys (supabaseURL, supabaseAnonKey) are removed. The build never fails because of this script, and
the Cloudflare token is only sent to api.cloudflare.com (header), never printed.
"""
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

DEFAULT_WORKER_NAME = "klimabilanz-api"
CLOUDFLARE_API = "https://api.cloudflare.com/client/v4"
LEGACY_KEYS = ("supabaseURL", "supabaseAnonKey")
PASSTHROUGH = {"UPDATE_MANIFEST_URL": "updateManifestURL", "TARIFFS_URL": "tariffsURL"}
WORKER_NAME = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")
SUBDOMAIN = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$")


def warn(message):
    print(f"::warning title=AppConfig::{message}")


def normalize_origin(value):
    """Returns the https origin without trailing slash, or None if `value` is not a plain https origin."""
    value = (value or "").strip()
    if not value:
        return None
    if any(c in value for c in "?#\\ \t\r\n"):
        return None
    try:
        parts = urllib.parse.urlsplit(value)
        port = parts.port  # raises ValueError for a bad port
    except ValueError:
        return None
    if parts.scheme != "https" or not parts.hostname or parts.username or parts.password:
        return None
    if parts.path not in ("", "/") or parts.query or parts.fragment:
        return None
    if port is not None and not 0 < port < 65536:
        return None
    host = parts.hostname.lower()
    return f"https://{host}" + (f":{port}" if port is not None else "")


def fetch_workers_subdomain(token, account_id, opener=urllib.request.urlopen, timeout=10):
    """Asks the Cloudflare API for the account's workers.dev subdomain; returns it or None (with a warning)."""
    if not re.fullmatch(r"[0-9a-fA-F]{32}", account_id or ""):
        warn("CLOUDFLARE_ACCOUNT_ID sieht nicht wie eine Cloudflare-Account-ID aus (32 Hex-Zeichen).")
        return None
    request = urllib.request.Request(
        f"{CLOUDFLARE_API}/accounts/{account_id}/workers/subdomain",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
    )
    try:
        with opener(request, timeout=timeout) as response:
            body = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        warn(f"Cloudflare-API antwortet mit HTTP {error.code} – API-URL bleibt leer (Token-Berechtigungen? docs/SETUP.md §3).")
        return None
    except (urllib.error.URLError, TimeoutError, OSError, ValueError) as error:
        warn(f"Cloudflare-API nicht erreichbar ({type(error).__name__}) – API-URL bleibt leer.")
        return None
    subdomain = ((body or {}).get("result") or {}).get("subdomain") if isinstance(body, dict) else None
    if not isinstance(subdomain, str) or not SUBDOMAIN.fullmatch(subdomain):
        warn("Keine workers.dev-Subdomain im Cloudflare-Konto – einmal *Workers & Pages* im Dashboard öffnen.")
        return None
    return subdomain


def probe_health(url, opener=urllib.request.urlopen, timeout=5):
    """GET <url>/v1/health; returns True if the backend answers 200. Failures are warnings only."""
    request = urllib.request.Request(f"{url}/v1/health", headers={"Accept": "application/json"})
    try:
        with opener(request, timeout=timeout) as response:
            if response.status == 200:
                return True
            warn(f"{url}/v1/health antwortet mit HTTP {response.status} – ist das Backend bereitgestellt (Actions › Backend)?")
    except urllib.error.HTTPError as error:
        warn(f"{url}/v1/health antwortet mit HTTP {error.code} – ist das Backend bereitgestellt (Actions › Backend)?")
    except (urllib.error.URLError, TimeoutError, OSError, ValueError) as error:
        warn(f"{url} ist nicht erreichbar ({type(error).__name__}) – die App versucht es später selbst; Backend bereitgestellt?")
    return False


def resolve_api_base_url(env, current, opener=urllib.request.urlopen):
    """Returns (url_or_empty, source) following the order in the module docstring."""
    explicit = (env.get("API_BASE_URL") or "").strip()
    if explicit:
        url = normalize_origin(explicit)
        if url is None:
            warn("API_BASE_URL muss eine https-Adresse ohne Pfad sein (z. B. https://api.example.at) – Cloud bleibt aus.")
            return "", "API_BASE_URL (ungültig)"
        return url, "API_BASE_URL"
    token = (env.get("CLOUDFLARE_API_TOKEN") or "").strip()
    account = (env.get("CLOUDFLARE_ACCOUNT_ID") or "").strip()
    if token and account:
        worker = (env.get("API_WORKER_NAME") or "").strip() or DEFAULT_WORKER_NAME
        if not WORKER_NAME.fullmatch(worker):
            warn("API_WORKER_NAME ist kein gültiger Worker-Name – Cloud bleibt aus.")
            return "", "Cloudflare (ungültiger Worker-Name)"
        subdomain = fetch_workers_subdomain(token, account, opener=opener)
        if subdomain:
            return f"https://{worker}.{subdomain.lower()}.workers.dev", "Cloudflare-Konto (workers.dev)"
    elif token or account:
        warn("Nur eines von CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID ist gesetzt – API-URL kann nicht ermittelt werden.")
    current = (current or "").strip()
    if current:
        url = normalize_origin(current)
        if url is None:
            warn("apiBaseURL in AppConfig.json ist keine https-Adresse ohne Pfad – Cloud bleibt aus.")
            return "", "AppConfig.json (ungültig)"
        return url, "AppConfig.json"
    return "", "keine (App läuft lokal ohne Konto)"


def write_config(path, env, opener=urllib.request.urlopen, probe=True):
    try:
        with open(path, encoding="utf-8") as f:
            config = json.load(f)
    except FileNotFoundError:
        config = {}
    if not isinstance(config, dict):
        config = {}
    for key in LEGACY_KEYS:
        config.pop(key, None)

    url, source = resolve_api_base_url(env, config.get("apiBaseURL", ""), opener=opener)
    config["apiBaseURL"] = url
    for name, key in PASSTHROUGH.items():
        value = (env.get(name) or "").strip()
        if value:
            config[key] = value
        config.setdefault(key, "")

    with open(path, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
        f.write("\n")

    health = None
    if url and probe:
        health = probe_health(url, opener=opener)
    print(f"AppConfig: apiBaseURL = {url or '(leer)'}  [Quelle: {source}]" + ("" if health is None else f"  health: {'ok' if health else 'nicht erreichbar'}"))
    print("AppConfig:", {k: ("<set>" if v else "") for k, v in config.items() if k != "apiBaseURL"})
    return config


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    path = argv[0] if argv else "App/Resources/AppConfig.json"
    write_config(path, os.environ)
    return 0


if __name__ == "__main__":
    sys.exit(main())
