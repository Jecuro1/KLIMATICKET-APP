"""Unit tests for scripts/launch_trace_summary.py (run by CI: python3 -m unittest discover -s scripts -p 'test_*.py')."""
import contextlib
import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_spec = importlib.util.spec_from_file_location("launch_trace_summary", os.path.join(ROOT, "scripts", "launch_trace_summary.py"))
tool = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(tool)

# Two healthy launches in the format LaunchTrace writes (taken from a real screenshot run).
HEALTHY = """\
1794486353.062 +1 ms  launch dashboard pid 32394
1794486353.089 +28 ms  app.init
1794486353.640 +579 ms  relations.built
1794486353.659 +598 ms  stations.built
1794486353.670 +609 ms  state.services
1794486353.671 +610 ms  app.ready
1794486354.869 +1808 ms  screen.appear
1794486354.871 +1809 ms  root.task
1794486354.873 +1812 ms  root.appear
1794486358.116 +5055 ms  stall 5024 ms from +31 ms
1794486358.613 +5552 ms  auth.loaded
1794486358.615 +5554 ms  stall 433 ms from +5121 ms
1794486385.903 +0 ms  launch yearReview pid 33294
1794486385.915 +11 ms  app.init
1794486386.260 +356 ms  state.services
1794486386.261 +357 ms  app.ready
1794486387.041 +1137 ms  screen.appear
1794486387.469 +1565 ms  stall 1554 ms from +11 ms
1794486387.633 +1730 ms  auth.loaded
"""

# A launch that never got past the launch screen: marks up to root.appear, then nothing – no stall, no auth.loaded.
BLANK = """\
1794486400.000 +0 ms  launch tripDetail pid 40001
1794486400.012 +12 ms  app.init
1794486400.350 +350 ms  app.ready
1794486401.100 +1100 ms  screen.appear
1794486401.102 +1102 ms  root.task
1794486401.103 +1103 ms  root.appear
"""


class LaunchTraceSummaryTests(unittest.TestCase):
    def run_main(self, text, *extra):
        with tempfile.TemporaryDirectory() as tmp:
            trace = os.path.join(tmp, "launch-trace.txt")
            with open(trace, "w", encoding="utf-8") as f:
                f.write(text)
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                code = tool.main([trace, *extra])
            return code, out.getvalue()

    def test_parse_reads_one_entry_per_launch(self):
        launches = tool.parse(HEALTHY)
        self.assertEqual([(l["run"], l["pid"]) for l in launches], [("dashboard", 32394), ("yearReview", 33294)])
        first = launches[0]
        self.assertEqual(first["marks"]["app.ready"], 610)
        self.assertEqual(first["marks"]["screen.appear"], 1808)
        self.assertEqual(first["marks"]["auth.loaded"], 5552)
        self.assertEqual(first["stalls"], [{"ms": 5024, "from": 31}, {"ms": 433, "from": 5121}])

    def test_healthy_trace_has_no_warning(self):
        code, out = self.run_main(HEALTHY)
        self.assertEqual(code, 0)
        self.assertNotIn("::warning", out)
        self.assertIn("| dashboard | 610 ms | 1808 ms | 1812 ms | 5552 ms | 2 | 5024 ms | ok |", out)
        self.assertIn("2 Starts, 0 ohne Lebenszeichen", out)

    def test_blank_launch_is_flagged_with_a_warning(self):
        code, out = self.run_main(HEALTHY + BLANK)
        self.assertEqual(code, 0)   # a finding, not a failed build
        warnings = [line for line in out.splitlines() if line.startswith("::warning")]
        self.assertEqual(len(warnings), 1)
        self.assertIn("tripDetail (pid 40001)", warnings[0])
        self.assertIn("| tripDetail | 350 ms | 1100 ms | 1103 ms | – | 0 | – | **leer?** |", out)
        self.assertIn("3 Starts, 1 ohne Lebenszeichen", out)

    def test_a_stall_line_alone_or_auth_loaded_alone_is_alive(self):
        stall_only = BLANK + "1794486402.000 +2000 ms  stall 1900 ms from +12 ms\n"
        auth_only = BLANK + "1794486402.000 +2000 ms  auth.loaded\n"
        for text in (stall_only, auth_only):
            _, out = self.run_main(text)
            self.assertNotIn("::warning", out)

    def test_every_blank_launch_gets_its_own_warning(self):
        second = BLANK.replace("tripDetail", "settings").replace("40001", "40002")
        _, out = self.run_main(BLANK + second)
        self.assertEqual(len([l for l in out.splitlines() if l.startswith("::warning")]), 2)

    def test_summary_file_gets_the_markdown_and_stdout_only_the_warning(self):
        with tempfile.TemporaryDirectory() as tmp:
            summary = os.path.join(tmp, "summary.md")
            with open(summary, "w", encoding="utf-8") as f:
                f.write("existing\n")
            code, out = self.run_main(BLANK, "--summary-file", summary)
            with open(summary, encoding="utf-8") as f:
                written = f.read()
        self.assertEqual(code, 0)
        self.assertTrue(written.startswith("existing\n### Start-Trace"))
        self.assertIn("**leer?**", written)
        self.assertTrue(out.startswith("::warning title=Leerer Start::tripDetail"))
        self.assertNotIn("###", out)

    def test_json_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = os.path.join(tmp, "summary.json")
            self.run_main(HEALTHY + BLANK, "--json", target)
            with open(target, encoding="utf-8") as f:
                data = json.load(f)
        self.assertEqual(data["blank"], ["tripDetail"])
        self.assertEqual(data["slowestStall"], "dashboard")
        self.assertEqual(len(data["launches"]), 3)

    def test_missing_file_is_a_notice_not_a_failure(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = tool.main(["/nonexistent/launch-trace.txt"])
        self.assertEqual(code, 0)
        self.assertIn("::notice::", out.getvalue())

    def test_empty_and_garbled_files(self):
        for text in ("", "not a trace\n\n+++\n", "1794486400.000 +0 ms  app.init\n"):   # marks without a "launch" line
            code, out = self.run_main(text)
            self.assertEqual(code, 0)
            self.assertNotIn("::warning", out)
            self.assertIn("Keine Starts im Trace gefunden.", out)

    def test_perf_run_names_with_a_plus_sign(self):
        text = "1794486400.000 +0 ms  launch perf+1500 pid 7\n1794486400.100 +100 ms  app.init\n1794486401.000 +1000 ms  auth.loaded\n"
        launches = tool.parse(text)
        self.assertEqual(launches[0]["run"], "perf+1500")
        self.assertFalse(tool.is_blank(launches[0]))


if __name__ == "__main__":
    unittest.main()
