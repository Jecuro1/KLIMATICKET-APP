"""Unit tests for scripts/check_integration.py (run by CI: python3 -m unittest discover -s scripts -p 'test_*.py')."""
import importlib.util
import os
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_spec = importlib.util.spec_from_file_location("check_integration", os.path.join(ROOT, "scripts", "check_integration.py"))
check = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check)


class CheckIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = self.tmp.name
        self.write("App/Sources/Views.swift", "struct DashboardView {\n}\nstruct TripsView {\n}\n")
        self.write("Shared/Theme.swift", "enum Theme {\n    static let accent = 1\n}\n")
        self.write("Widgets/Sources/Widget.swift", "struct AmortizationWidget {\n    func body() {}\n}\n")

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, relative, text):
        path = os.path.join(self.repo, relative)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)

    def problems(self, **kwargs):
        kwargs.setdefault("contract", ["DashboardView", "TripsView"])
        return check.run_checks(self.repo, **kwargs)

    # --- the original checks -------------------------------------------------------------------------------

    def test_clean_tree_passes(self):
        self.assertEqual(self.problems(), [])

    def test_missing_contract_type_is_reported(self):
        self.assertEqual(self.problems(contract=["DashboardView", "TicketView"]), ["[missing] contract type TicketView"])

    def test_duplicate_type_in_the_app_target(self):
        self.write("App/Sources/Other.swift", "struct TripsView {\n}\n")
        found = self.problems()
        self.assertEqual(len(found), 1)
        self.assertTrue(found[0].startswith("[dup:App] TripsView"))

    def test_private_types_may_repeat(self):
        self.write("App/Sources/Other.swift", "private struct Helper {\n}\n")
        self.write("App/Sources/More.swift", "private struct Helper {\n}\n")
        self.assertEqual(self.problems(), [])

    def test_unbalanced_braces(self):
        self.write("App/Sources/Broken.swift", "struct Broken {\n")
        found = self.problems()
        self.assertEqual(len(found), 1)
        self.assertTrue(found[0].startswith("[braces] App/Sources/Broken.swift"))

    # --- the network guard ---------------------------------------------------------------------------------

    def test_urlsession_in_the_widget_target_fails(self):
        self.write("Widgets/Sources/Widget.swift", "struct AmortizationWidget {\n    let s = URLSession.shared\n}\n")
        found = self.problems()
        self.assertEqual(len(found), 1)
        self.assertIn("[network] Widgets/Sources/Widget.swift:2: URLSession", found[0])

    def test_every_network_name_is_caught_in_widgets_and_shared(self):
        for name in ("URLSession", "URLRequest", "HafasClient", "LiveDataService"):
            for relative in ("Widgets/Sources/Widget.swift", "Shared/Theme.swift"):
                with self.subTest(name=name, file=relative):
                    self.write(relative, f"struct Probe {{\n    var x: {name}?\n}}\n")
                    found = self.problems()
                    self.assertEqual(len(found), 1, found)
                    self.assertIn(f"{relative}:2: {name}", found[0])
                    self.write("Widgets/Sources/Widget.swift", "struct AmortizationWidget {\n}\n")
                    self.write("Shared/Theme.swift", "enum Theme {\n}\n")

    def test_the_app_target_may_use_the_network(self):
        self.write("App/Sources/Live.swift", "struct LiveClient {\n    let s = URLSession.shared\n    var r: URLRequest?\n}\n")
        self.assertEqual(self.problems(), [])

    def test_comments_and_strings_do_not_count(self):
        self.write("Shared/Notes.swift", '''// never URLSession here
/* HafasClient is app-only
   /* nested URLRequest */ still a comment */
enum Notes {
    static let text = "URLSession is not used"
    static let raw = #"URLRequest \\(not code)"#
    static let many = """
        LiveDataService
        HafasClient
        """
    static func f(_ x: Int) -> String { "\\(x) URLSession" }
}
''')
        self.assertEqual(self.problems(), [])

    def test_code_inside_a_string_interpolation_counts(self):
        # "\(URLSession.shared)" runs the network call: only the text of a string is blanked, never its interpolations.
        self.write("Shared/Interp.swift", 'enum I {\n    static let a = "x \\(URLSession.shared) y"\n'
                   '    static let b = """\n        \\(LiveDataService.shared)\n        """\n'
                   '    static let c = #"raw \\#(HafasClient())"#\n    static let d = "ok \\(f(")", URLRequest(url: u))"\n}\n')
        found = self.problems()
        self.assertEqual(len(found), 4, found)
        for name, line in (("URLSession", 2), ("LiveDataService", 4), ("HafasClient", 6), ("URLRequest", 7)):
            self.assertTrue(any(f"Shared/Interp.swift:{line}: {name}" in item for item in found), (name, found))

    def test_text_next_to_an_interpolation_does_not_count(self):
        self.write("Shared/Text.swift", 'enum T {\n    static func a(_ n: Int) -> String { "\\(n) URLSession \\(n)" }\n'
                   '    static let b = #"\\(HafasClient()) is text in a raw string"#\n}\n')
        self.assertEqual(self.problems(), [])

    def test_code_after_a_string_with_a_slash_pair_still_counts(self):
        self.write("Shared/Url.swift", 'enum U {\n    static let a = "https://example.org"; static let s = URLSession.shared\n}\n')
        found = self.problems()
        self.assertEqual(len(found), 1)
        self.assertIn("Shared/Url.swift:2: URLSession", found[0])

    def test_line_numbers_survive_multiline_comments_and_strings(self):
        self.write("Shared/Lines.swift", 'enum L {\n    /* one\n       two */\n    static let s = """\n        a\n        """\n    var r: URLRequest?\n}\n')
        found = self.problems()
        self.assertEqual(len(found), 1)
        self.assertIn("Shared/Lines.swift:7: URLRequest", found[0])

    def test_allow_list_permits_exactly_the_listed_names_in_the_listed_file(self):
        self.write("Shared/Net.swift", "enum Net {\n    var a: URLSession?\n    var b: URLRequest?\n}\n")
        allow = {"Shared/Net.swift": (("URLSession",), "test")}
        found = self.problems(allow=allow)
        self.assertEqual(len(found), 1)
        self.assertIn("Shared/Net.swift:3: URLRequest", found[0])
        self.write("Widgets/Sources/Widget.swift", "struct AmortizationWidget {\n    var a: URLSession?\n}\n")
        self.assertEqual(len(self.problems(allow=allow)), 2)

    def test_the_shipped_allow_list_is_empty(self):
        # Nothing in Widgets/ or Shared/ may use the network today; a new entry needs a reviewed reason.
        self.assertEqual(check.NETWORK_ALLOW, {})

    # --- sideload compatibility ----------------------------------------------------------------------------

    YML = """targets:
  KlimaBilanz:
    info:
      properties:
        NSLocationWhenInUseUsageDescription: "Text"
        NSLocationAlwaysAndWhenInUseUsageDescription: "Text"
        NSAlarmKitUsageDescription: "Text"
        # a comment between the key and its modes
        UIBackgroundModes:
          - fetch
          # - voip (commented out)
          - location
        BGTaskSchedulerPermittedIdentifiers:
          - com.example.refresh
"""

    @staticmethod
    def entitlements(*keys):
        rows = "".join(f"\t<key>{k}</key>\n\t<true/>\n" for k in keys)
        return ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
                '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n' + rows + '</dict>\n</plist>\n')

    def sideload_tree(self, yml=None, entitlements=("com.apple.security.application-groups",)):
        self.write("project.yml", self.YML if yml is None else yml)
        self.write("App/Supporting/KlimaBilanz-Sideload.entitlements", self.entitlements(*entitlements))

    def test_a_tree_without_project_yml_is_not_checked(self):
        self.assertEqual(check.sideload_problems(self.repo), [])

    def test_the_reviewed_sideload_setup_passes(self):
        self.sideload_tree()
        self.write("App/Sources/Alarm.swift", "import AlarmKit\nimport CoreLocation\nstruct Alarmer {\n    let m = CLLocationManager()\n"
                   "    func a() { m.requestAlwaysAuthorization(); m.allowsBackgroundLocationUpdates = true }\n}\n")
        self.assertEqual(self.problems(), [])

    def test_an_entitlement_that_needs_a_paid_account_fails(self):
        for key in ("com.apple.developer.applesignin", "aps-environment", "com.apple.developer.usernotifications.time-sensitive",
                    "com.apple.developer.usernotifications.critical-alerts", "com.apple.developer.associated-domains"):
            with self.subTest(key=key):
                self.sideload_tree(entitlements=("com.apple.security.application-groups", key))
                found = self.problems()
                self.assertEqual(len(found), 1, found)
                self.assertIn(f"[sideload] App/Supporting/KlimaBilanz-Sideload.entitlements: entitlement {key}", found[0])

    def test_only_the_sideload_entitlements_count(self):
        # The generated KlimaBilanz.entitlements of the Xcode project carries Sign in with Apple for signed builds; CI never signs with it.
        self.sideload_tree()
        self.write("App/Supporting/KlimaBilanz.entitlements", self.entitlements("com.apple.developer.applesignin"))
        self.assertEqual(self.problems(), [])

    def test_a_broken_entitlements_file_is_reported(self):
        self.sideload_tree()
        self.write("App/Supporting/KlimaBilanz-Sideload.entitlements", "not a plist")
        found = self.problems()
        self.assertEqual(len(found), 1)
        self.assertIn("not a property list", found[0])

    def test_a_background_mode_off_the_list_fails(self):
        for mode in ("audio", "voip", "remote-notification", "processing", "bluetooth-central"):
            with self.subTest(mode=mode):
                self.sideload_tree(yml=self.YML.replace("          - location\n", f"          - location\n          - {mode}\n"))
                found = self.problems()
                self.assertEqual(len(found), 1, found)
                self.assertIn(f"UIBackgroundModes {mode}", found[0])

    def test_a_commented_out_mode_does_not_count(self):
        self.sideload_tree()
        self.assertEqual(check._background_modes(self.YML), ["fetch", "location"])

    def test_each_framework_needs_its_usage_string(self):
        cases = [("import AlarmKit\nenum A {}\n", "NSAlarmKitUsageDescription"),
                 ("import CoreLocation\nstruct L {\n    let m = CLLocationManager()\n}\n", "NSLocationWhenInUseUsageDescription"),
                 ("struct L {\n    func f(_ m: Int) { m.requestAlwaysAuthorization() }\n}\n", "NSLocationAlwaysAndWhenInUseUsageDescription")]
        for source, key in cases:
            with self.subTest(key=key):
                self.sideload_tree(yml=self.YML.replace(f"        {key}:", "        Unrelated:"))
                self.write("App/Sources/Use.swift", source)
                found = self.problems()
                self.assertEqual(len(found), 1, found)
                self.assertIn(f"project.yml: {key} is missing", found[0])
                self.write("App/Sources/Use.swift", "struct Use {\n}\n")

    def test_background_location_needs_the_location_mode(self):
        self.sideload_tree(yml=self.YML.replace("          - location\n", ""))
        self.write("App/Sources/Use.swift", "struct Use {\n    func f(_ m: Int) { m.allowsBackgroundLocationUpdates = true }\n}\n")
        found = self.problems()
        self.assertEqual(len(found), 1, found)
        self.assertIn("lacks location", found[0])

    def test_names_in_comments_and_strings_do_not_ask_for_a_usage_string(self):
        self.sideload_tree(yml=self.YML.replace("        NSAlarmKitUsageDescription:", "        Unrelated:"))
        self.write("App/Sources/Notes.swift", '// import AlarmKit\nenum Notes {\n    static let text = "import AlarmKit and CLLocationManager"\n}\n')
        self.assertEqual(self.problems(), [])

    def test_the_shipped_lists_stay_short(self):
        # A new entitlement or background mode is a decision of the owner: it goes on the list together with its reason.
        self.assertEqual(sorted(check.ALLOWED_SIDELOAD_ENTITLEMENTS), ["com.apple.security.application-groups"])
        self.assertEqual(sorted(check.ALLOWED_BACKGROUND_MODES), ["fetch", "location"])
        self.assertTrue(all(reason for reason in {**check.ALLOWED_SIDELOAD_ENTITLEMENTS, **check.ALLOWED_BACKGROUND_MODES}.values()))

    def test_the_repository_is_sideload_compatible(self):
        self.assertEqual(check.sideload_problems(ROOT), [])

    # --- the real repository -------------------------------------------------------------------------------

    def test_the_repository_passes(self):
        self.assertEqual(check.run_checks(ROOT), [])

    def test_main_exit_codes(self):
        self.assertEqual(check.main([self.repo]), 1)   # the temp tree lacks the real contract views
        self.assertEqual(check.main([ROOT]), 0)


if __name__ == "__main__":
    unittest.main()
