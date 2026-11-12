"""Unit tests for scripts/perf_compare.py (run by CI: python3 -m unittest discover -s scripts -p 'test_*.py')."""
import contextlib
import io
import json
import os
import tempfile
import unittest

import perf_compare


def run(ratio, first=100.0, mem=200.0):
    return {"scroll": [{"screen": "Fahrten", "variant": "Demo-Jahr", "source": "touch", "hitchRatio": ratio}],
            "transitions": [{"to": "Fahrten", "variant": "Demo-Jahr", "firstFrameMs": first, "longestFrameMs": first + 10}],
            "launch": [{"variant": "Demo-Jahr", "initToFirstFrameMs": 900.0}],
            "memory": [{"screen": "Fahrten", "variant": "Demo-Jahr", "peakMB": mem}],
            "hangs": []}


class PerfCompareTests(unittest.TestCase):
    def test_verdict_needs_relative_and_absolute_movement(self):
        self.assertEqual(perf_compare.verdict(10.0, 5.0, 1.0, 0.15), "besser")
        self.assertEqual(perf_compare.verdict(5.0, 10.0, 1.0, 0.15), "schlechter")
        self.assertEqual(perf_compare.verdict(10.0, 10.9, 1.0, 0.15), "gleich")   # inside the tolerance
        self.assertEqual(perf_compare.verdict(0.4, 1.2, 1.0, 0.15), "gleich")     # tiny numbers: below the absolute floor
        self.assertEqual(perf_compare.verdict(None, 3.0, 1.0, 0.15), "–")

    def test_improvement_is_listed_and_nothing_is_worse(self):
        lines, worse = perf_compare.compare(run(14.0, first=300.0), run(3.0, first=120.0))
        text = "\n".join(lines)
        self.assertEqual(worse, [])
        self.assertIn("| Fahrten · Demo-Jahr · touch | 14.0 ms/s | 3.0 ms/s | -11.0 | besser |", text)
        self.assertIn("| Fahrten · Demo-Jahr | 300 ms | 120 ms | -180 | besser |", text)
        self.assertIn("| Demo-Jahr | 900 ms | 900 ms | +0 | gleich |", text)

    def test_regression_is_reported(self):
        lines, worse = perf_compare.compare(run(4.0), run(9.0, mem=260.0))
        self.assertEqual(worse, ["Scrollen: Hitch Time Ratio (ms Ruckeln pro s Scrollen, kleiner ist besser): Fahrten · Demo-Jahr · touch",
                                 "Speicher: Spitze je Bildschirm: Fahrten · Demo-Jahr"])

    def test_new_and_removed_screens(self):
        before, after = run(5.0), run(5.0)
        after["scroll"].append({"screen": "Zug-Radar", "variant": "Demo-Jahr", "source": "touch", "hitchRatio": 2.0})
        before["scroll"].append({"screen": "Alt", "variant": "Demo-Jahr", "source": "touch", "hitchRatio": 2.0})
        lines, worse = perf_compare.compare(before, after)
        text = "\n".join(lines)
        self.assertIn("| Zug-Radar · Demo-Jahr · touch | – | 2.0 ms/s | – | neu |", text)
        self.assertIn("| Alt · Demo-Jahr · touch | 2.0 ms/s | – | – | entfernt |", text)
        self.assertEqual(worse, [])

    def test_cli_and_exit_code(self):
        with tempfile.TemporaryDirectory() as tmp:
            paths = []
            for name, ratio in (("before.json", 4.0), ("after.json", 9.0)):
                path = os.path.join(tmp, name)
                with open(path, "w", encoding="utf-8") as f:
                    json.dump({"summary": {}, "appDiagnostics": {"inApp": run(ratio)}}, f)
                paths.append(path)
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                self.assertEqual(perf_compare.main(paths), 0)
                self.assertEqual(perf_compare.main(paths + ["--fail-on-regress"]), 1)
                self.assertEqual(perf_compare.main(paths[::-1] + ["--fail-on-regress"]), 0)
            self.assertIn("schlechter", out.getvalue())

    def test_missing_sections_do_not_break(self):
        lines, worse = perf_compare.compare({}, {})
        self.assertEqual(lines, [])
        self.assertEqual(worse, [])


if __name__ == "__main__":
    unittest.main()
