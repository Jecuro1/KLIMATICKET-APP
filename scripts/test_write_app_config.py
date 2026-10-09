#!/usr/bin/env python3
"""Tests for write_app_config.py (no network): python3 -m unittest discover -s scripts -p 'test_*.py'"""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
import urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import write_app_config as wac  # noqa: E402

ACCOUNT = "0123456789abcdef0123456789abcdef"


class FakeResponse:
    def __init__(self, status, body):
        self.status = status
        self._body = body

    def read(self):
        return self._body.encode("utf-8")

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class FakeOpener:
    """Routes requests by URL suffix; records (url, headers, timeout)."""

    def __init__(self, routes):
        self.routes = routes
        self.calls = []

    def __call__(self, request, timeout=None):
        url = request.full_url
        self.calls.append((url, dict(request.header_items()), timeout))
        for suffix, answer in self.routes.items():
            if url.endswith(suffix):
                if isinstance(answer, Exception):
                    raise answer
                status, body = answer
                if status >= 400:
                    raise urllib.error.HTTPError(url, status, "error", {}, io.BytesIO(body.encode()))
                return FakeResponse(status, body)
        raise urllib.error.URLError("no route")


def subdomain_ok(name="marcel"):
    return (200, json.dumps({"success": True, "errors": [], "result": {"subdomain": name}}))


class NormalizeOriginTests(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(wac.normalize_origin("https://api.example.at"), "https://api.example.at")
        self.assertEqual(wac.normalize_origin(" https://API.Example.at/ "), "https://api.example.at")
        self.assertEqual(wac.normalize_origin("https://a.b:8443"), "https://a.b:8443")

    def test_invalid(self):
        for value in ["", "api.example.at", "http://a.b", "https://", "https://a.b/v1", "https://a.b/?x=1",
                      "https://a.b#x", "https://u:p@a.b", "https://a.b:99999", "ftp://a.b", "https://a b"]:
            self.assertIsNone(wac.normalize_origin(value), value)


class ResolveTests(unittest.TestCase):
    def resolve(self, env, current="", routes=None):
        opener = FakeOpener(routes or {})
        with contextlib.redirect_stdout(io.StringIO()) as out:
            url, source = wac.resolve_api_base_url(env, current, opener=opener)
        return url, source, opener, out.getvalue()

    def test_explicit_variable_wins_and_skips_cloudflare(self):
        url, source, opener, _ = self.resolve(
            {"API_BASE_URL": "https://api.knitel.at/", "CLOUDFLARE_API_TOKEN": "t", "CLOUDFLARE_ACCOUNT_ID": ACCOUNT})
        self.assertEqual((url, source), ("https://api.knitel.at", "API_BASE_URL"))
        self.assertEqual(opener.calls, [])

    def test_invalid_explicit_variable_turns_cloud_off(self):
        url, _, _, out = self.resolve({"API_BASE_URL": "https://api.knitel.at/v1"}, current="https://old.example")
        self.assertEqual(url, "")
        self.assertIn("::warning", out)

    def test_derived_from_cloudflare_subdomain(self):
        url, source, opener, out = self.resolve(
            {"CLOUDFLARE_API_TOKEN": "secret-token", "CLOUDFLARE_ACCOUNT_ID": ACCOUNT},
            routes={"/workers/subdomain": subdomain_ok("Marcel")})
        self.assertEqual(url, "https://klimabilanz-api.marcel.workers.dev")
        self.assertIn("Cloudflare", source)
        called_url, headers, timeout = opener.calls[0]
        self.assertEqual(called_url, f"https://api.cloudflare.com/client/v4/accounts/{ACCOUNT}/workers/subdomain")
        self.assertEqual(headers.get("Authorization"), "Bearer secret-token")
        self.assertEqual(timeout, 10)
        self.assertNotIn("secret-token", out)

    def test_worker_name_override(self):
        url, _, _, _ = self.resolve(
            {"CLOUDFLARE_API_TOKEN": "t", "CLOUDFLARE_ACCOUNT_ID": ACCOUNT, "API_WORKER_NAME": "kb-test"},
            routes={"/workers/subdomain": subdomain_ok()})
        self.assertEqual(url, "https://kb-test.marcel.workers.dev")

    def test_cloudflare_failures_fall_back_to_file_value_or_empty(self):
        env = {"CLOUDFLARE_API_TOKEN": "t", "CLOUDFLARE_ACCOUNT_ID": ACCOUNT}
        for answer in [(403, '{"success":false}'), (200, '{"success":true,"result":{"subdomain":null}}'),
                       (200, "<html>"), urllib.error.URLError("down"), TimeoutError()]:
            url, _, _, out = self.resolve(env, routes={"/workers/subdomain": answer})
            self.assertEqual(url, "", answer)
            self.assertIn("::warning", out)
            url, source, _, _ = self.resolve(env, current="https://manual.example/", routes={"/workers/subdomain": answer})
            self.assertEqual((url, source), ("https://manual.example", "AppConfig.json"))

    def test_bad_account_id_is_not_sent(self):
        url, _, opener, out = self.resolve({"CLOUDFLARE_API_TOKEN": "t", "CLOUDFLARE_ACCOUNT_ID": "../x"})
        self.assertEqual(url, "")
        self.assertEqual(opener.calls, [])
        self.assertIn("::warning", out)

    def test_only_one_cloudflare_value(self):
        url, _, opener, out = self.resolve({"CLOUDFLARE_API_TOKEN": "t"})
        self.assertEqual(url, "")
        self.assertEqual(opener.calls, [])
        self.assertIn("::warning", out)

    def test_nothing_configured(self):
        self.assertEqual(self.resolve({})[0], "")
        self.assertEqual(self.resolve({}, current="javascript:alert(1)")[0], "")


class WriteConfigTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.dir.name, "AppConfig.json")

    def tearDown(self):
        self.dir.cleanup()

    def run_write(self, env, initial=None, routes=None, probe=True):
        if initial is not None:
            with open(self.path, "w", encoding="utf-8") as f:
                json.dump(initial, f)
        opener = FakeOpener(routes or {})
        with contextlib.redirect_stdout(io.StringIO()) as out:
            wac.write_config(self.path, env, opener=opener, probe=probe)
        with open(self.path, encoding="utf-8") as f:
            return json.load(f), out.getvalue(), opener

    def test_ci_build_with_cloudflare_and_update_urls(self):
        config, out, opener = self.run_write(
            {"CLOUDFLARE_API_TOKEN": "tok", "CLOUDFLARE_ACCOUNT_ID": ACCOUNT,
             "UPDATE_MANIFEST_URL": "https://github.com/Jecuro1/KLIMATICKET-APP/releases/latest/download/update.json",
             "TARIFFS_URL": "https://github.com/Jecuro1/KLIMATICKET-APP/releases/latest/download/tariffs.json"},
            initial={"supabaseURL": "https://x.supabase.co", "supabaseAnonKey": "anon", "updateManifestURL": "", "tariffsURL": ""},
            routes={"/workers/subdomain": subdomain_ok(), "/v1/health": (200, '{"ok":true}')})
        self.assertEqual(config, {
            "updateManifestURL": "https://github.com/Jecuro1/KLIMATICKET-APP/releases/latest/download/update.json",
            "tariffsURL": "https://github.com/Jecuro1/KLIMATICKET-APP/releases/latest/download/tariffs.json",
            "apiBaseURL": "https://klimabilanz-api.marcel.workers.dev",
        })
        self.assertEqual(opener.calls[-1][0], "https://klimabilanz-api.marcel.workers.dev/v1/health")
        self.assertEqual(opener.calls[-1][2], 5)
        self.assertIn("health: ok", out)
        self.assertNotIn("tok", out.replace("token", ""))

    def test_health_failure_is_only_a_warning(self):
        for answer in [(503, '{"ok":false}'), urllib.error.URLError("dns")]:
            config, out, _ = self.run_write({"API_BASE_URL": "https://api.knitel.at"}, initial={},
                                            routes={"/v1/health": answer})
            self.assertEqual(config["apiBaseURL"], "https://api.knitel.at")
            self.assertIn("::warning", out)

    def test_local_values_are_kept_without_env(self):
        config, _, _ = self.run_write({}, initial={"apiBaseURL": "https://dev.example", "updateManifestURL": "https://u",
                                                   "tariffsURL": "", "extra": 1}, probe=False)
        self.assertEqual(config, {"apiBaseURL": "https://dev.example", "updateManifestURL": "https://u", "tariffsURL": "", "extra": 1})

    def test_missing_file_gets_all_keys(self):
        config, out, _ = self.run_write({})
        self.assertEqual(config, {"apiBaseURL": "", "updateManifestURL": "", "tariffsURL": ""})
        self.assertIn("(leer)", out)

    def test_committed_appconfig_is_compatible(self):
        repo_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "App", "Resources", "AppConfig.json")
        with open(repo_file, encoding="utf-8") as f:
            initial = json.load(f)
        config, _, _ = self.run_write({}, initial=initial, probe=False)
        self.assertEqual(config["apiBaseURL"], "")
        self.assertNotIn("supabaseURL", config)
        self.assertNotIn("supabaseAnonKey", config)


if __name__ == "__main__":
    unittest.main()
