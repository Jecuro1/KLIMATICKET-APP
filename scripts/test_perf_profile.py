import os
import unittest

import perf_profile

HERE = os.path.dirname(os.path.abspath(__file__))
PREFIX = os.path.join(HERE, "testdata", "perf-profile")


class PerfProfileTests(unittest.TestCase):
    """testdata/perf-profile.*.xml mimic `xctrace export` (ids defined once, nested, later used via ref)."""

    def test_samples_resolve_refs_and_threads(self):
        samples = perf_profile.load_samples(PREFIX + ".time-profile.xml")
        self.assertEqual(len(samples), 4)
        self.assertEqual([s[2] for s in samples], [True, True, True, False])  # the last one is a background thread
        self.assertEqual(samples[1][3], samples[0][3])  # <backtrace ref="10"/>
        self.assertEqual(samples[2][3][1], ("StatsScreen.body.getter", "KlimaBilanz"))  # <frame ref="15"/>

    def test_phases_from_signposts_and_attribution(self):
        result = perf_profile.analyse(PREFIX)
        self.assertEqual(result["phaseSource"], "signposts")
        phase = result["phases"][0]
        self.assertEqual(phase["phase"], "scroll stats")
        self.assertEqual(phase["samples"], 2)  # 5.000 s and 5.001 s; the 1 s sample is outside, the 5.002 s one off-main
        names = [i["name"] for i in phase["attributed"]]
        self.assertEqual(sorted(names), ["StatsCalc.monthly(_:)", "StatsScreen.body.getter"])
        inclusive = {i["name"]: i["ms"] for i in phase["inclusive"]}
        self.assertEqual(inclusive["StatsScreen.body.getter"], 2.0)
        text = perf_profile.markdown([result])
        self.assertIn("**scroll stats**", text)
        self.assertIn("`StatsScreen.body.getter`", text)

    def test_sample_report(self):
        result = perf_profile.analyse_samples("stats", [("open", os.path.join(HERE, "testdata", "perf-sample.txt"))])
        phase = result["phases"][0]
        self.assertEqual(phase["samples"], 1000)
        self.assertEqual(phase["mainThreadBusyMs"], 400)  # 600 samples wait in mach_msg2_trap
        attributed = {i["name"]: i["ms"] for i in phase["attributed"]}
        # swift_retain under compare() belongs to compare(); Date.formatted under the body closure to the closure;
        # swift_release under AttributeGraph has no app frame below `main`.
        self.assertEqual(attributed["TicketComparator.compare(trips:products:variant:)"], 200)
        self.assertEqual(attributed["closure #1 in StatsScreen.body.getter"], 100)
        self.assertEqual(attributed["(ohne App-Frame: SwiftUI/UIKit/CA)"], 100)
        inclusive = {i["name"]: i["ms"] for i in phase["inclusive"]}
        self.assertEqual(inclusive["closure #1 in StatsScreen.body.getter"], 300)
        self.assertNotIn("main", inclusive)
        self.assertIn("**open** – Hauptthread belegt 400 ms", perf_profile.markdown([result]))


if __name__ == "__main__":
    unittest.main()
