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

    # --- the real repository -------------------------------------------------------------------------------

    def test_the_repository_passes(self):
        self.assertEqual(check.run_checks(ROOT), [])

    def test_main_exit_codes(self):
        self.assertEqual(check.main([self.repo]), 1)   # the temp tree lacks the real contract views
        self.assertEqual(check.main([ROOT]), 0)


if __name__ == "__main__":
    unittest.main()
