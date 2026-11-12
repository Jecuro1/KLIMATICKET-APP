"""Unit tests for scripts/doc_numbers.py (run by CI: python3 -m unittest discover -s scripts -p 'test_*.py')."""
import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_spec = importlib.util.spec_from_file_location("doc_numbers", os.path.join(ROOT, "scripts", "doc_numbers.py"))
tool = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(tool)


class DocNumbersTests(unittest.TestCase):
    def test_german_grouping(self):
        self.assertEqual(tool.de(39711), "39.711")
        self.assertEqual(tool.de(21050), "21.050")
        self.assertEqual(tool.de(33), "33")
        self.assertEqual(tool.de(1234567), "1.234.567")
        self.assertEqual(tool.de("2025-12-14"), "2025-12-14")

    def test_the_shipped_data_gives_plausible_numbers(self):
        figures = tool.numbers(ROOT)
        values = {key: value for key, (value, _) in figures.items()}
        self.assertGreater(values["stops"], 30_000)
        self.assertGreater(values["localities"], 10_000)
        self.assertEqual(values["legacy_stations"], 1487)   # frozen list, docs/DATA_SOURCES.md
        self.assertGreater(values["relation_pairs"], values["relation_origins"])
        self.assertGreater(values["ticket_products"], 10)
        self.assertGreaterEqual(values["achievements"], 10)
        self.assertRegex(values["relation_valid_from"], r"^\d{4}-\d{2}-\d{2}$")

    def test_json_output(self):
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(tool.main(["--json"]), 0)
        data = json.loads(out.getvalue())
        self.assertEqual(set(data), {"stops", "localities", "legacy_stations", "relation_pairs", "relation_origins",
                                     "relation_valid_from", "ticket_products", "achievements"})

    def test_missing_names_the_figures_no_text_quotes(self):
        figures = {"stops": (39711, "a"), "localities": (21050, "b"), "relation_pairs": (29883, "c")}
        self.assertEqual(tool.missing(figures, ["... 39.711 Haltestellen, 21.050 Orte, 29.883 Preise ..."]), [])
        self.assertEqual(tool.missing(figures, ["39.711 und 29.883", "nur 21.050"]), [])
        self.assertEqual(tool.missing(figures, ["39711 ohne Punkt"]), ["stops", "localities", "relation_pairs"])
        self.assertEqual(tool.missing(figures, ["1.487 und 21.050"]), ["stops", "relation_pairs"])

    def test_tree_check_wants_every_folder_written_as_name_slash(self):
        with tempfile.TemporaryDirectory() as tmp:
            for folder in ("App/Sources/Features/Radar", "App/Sources/Features/Stops", "App/Sources/Services/Live",
                           "Packages/KlimaCore/Sources/KlimaCore/Places", "Shared", "scripts", ".git", "build"):
                os.makedirs(os.path.join(tmp, folder))
            names = tool.tree_names(tmp)
            self.assertIn("Radar", names)
            self.assertIn("Shared", names)
            self.assertNotIn(".git", names)       # hidden
            self.assertNotIn("build", names)      # build output
            self.assertNotIn("Sources", names)    # structural folder
            text = "Features/Radar/ Features/Stops/ Services/Live/ Places/ Shared/ scripts/ App/ Packages/ KlimaCore/ Features/ Services/"
            self.assertEqual(tool.untreed(tmp, text), [])
            # a plain word is no mention: "Radar" without a slash does not count
            self.assertEqual(tool.untreed(tmp, text.replace("Radar/", "Radar ")), ["Radar"])


if __name__ == "__main__":
    unittest.main()
