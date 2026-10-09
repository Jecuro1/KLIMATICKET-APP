import json
import os
import tempfile
import unittest

import perf_summary

LOG = """
Test Suite 'LaunchPerfTests' started at 2026-10-09 12:00:00.000.
/Users/runner/work/PerfTests/ScrollPerfTests.swift:9: Test Case '-[KlimaBilanzPerfTests.LaunchPerfTests testLaunch]' measured [Duration (AppLaunch), s] average: 0.912, relative standard deviation: 4.210%, values: [0.950000, 0.901000, 0.893000, 0.910000, 0.906000], performanceMetricID:com.apple.dt.XCTMetric_ApplicationLaunch-AppLaunch.duration, baselineName: "", baselineAverage: , polarity: prefers smaller, maxPercentRegression: 10.000%, maxPercentRelativeStandardDeviation: 10.000%, maxRegression: 0.000, maxStandardDeviation: 0.000
Test Case '-[KlimaBilanzPerfTests.LaunchPerfTests testLaunch]' passed (25.120 seconds).
Test Case '-[KlimaBilanzPerfTests.ScrollPerfTests testScrollTrips]' measured [Hitch Time Ratio (Scroll_DraggingAndDeceleration), ms per s] average: 12.500, relative standard deviation: 20.000%, values: [10.000000, 15.000000], performanceMetricID:com.apple.dt.XCTMetric_OSSignpost-Scroll_DraggingAndDeceleration.hitchTimeRatio, baselineName: "", baselineAverage: , polarity: prefers smaller, maxPercentRegression: 10.000%, maxPercentRelativeStandardDeviation: 10.000%, maxRegression: 0.000, maxStandardDeviation: 0.000
Test Case '-[KlimaBilanzPerfTests.ScrollPerfTests testScrollTrips]' measured [Hitch Time Ratio (Scroll_Deceleration), ms per s] average: 3.000, relative standard deviation: 1.000%, values: [3.000000], performanceMetricID:x
Test Case '-[KlimaBilanzPerfTests.ScrollPerfTests testScrollTrips]' measured [Frame Rate (Scroll_DraggingAndDeceleration), fps] average: 58.000, relative standard deviation: 1.000%, values: [58.000000], performanceMetricID:x
Test Case '-[KlimaBilanzPerfTests.ScrollPerfTests testScrollTrips]' passed (40.000 seconds).
Test Case '-[KlimaBilanzPerfTests.HeavyDataPerfTests testScrollStatisticsHeavy]' measured [Hitch Time Ratio (Scroll_DraggingAndDeceleration), ms per s] average: 4.000, relative standard deviation: 1.000%, values: [4.000000], performanceMetricID:x
Test Case '-[KlimaBilanzPerfTests.ScrollPerfTests testTabSwitching]' measured [Clock Monotonic Time, s] average: 6.500, relative standard deviation: 2.000%, values: [6.400000, 6.600000], performanceMetricID:com.apple.dt.XCTMetric_Clock.time.monotonic
Test Case '-[KlimaBilanzPerfTests.ScrollPerfTests testTabSwitching]' measured [Memory Peak Physical, kB] average: 204800.000, relative standard deviation: 0.500%, values: [204800.000000], performanceMetricID:x
Test Case '-[KlimaBilanzPerfTests.ScrollPerfTests testScrollGipfelbuch]' failed (12.000 seconds).
"""


class PerfSummaryTests(unittest.TestCase):
    def test_parses_launch_scroll_and_tab_tour(self):
        summary = perf_summary.summarize(perf_summary.parse_log(LOG))
        self.assertAlmostEqual(summary["launch"]["seconds"], 0.912)
        self.assertEqual(len(summary["launch"]["values"]), 5)
        trips = next(s for s in summary["scroll"] if s["test"] == "testScrollTrips")
        self.assertEqual(trips["screen"], "Fahrten")
        self.assertAlmostEqual(trips["hitchRatio"], 12.5)
        self.assertAlmostEqual(trips["decelerationHitchRatio"], 3.0)
        self.assertAlmostEqual(trips["frameRate"], 58.0)
        self.assertEqual(trips["rating"], "kritisch")
        heavy = next(s for s in summary["scroll"] if s["test"] == "testScrollStatisticsHeavy")
        self.assertEqual(heavy["screen"], "Statistik (+1 500 Fahrten)")
        self.assertEqual(heavy["rating"], "gut")
        tour = summary["tabTour"][0]
        self.assertAlmostEqual(tour["clockSeconds"], 6.5)
        self.assertAlmostEqual(tour["peakMemoryMB"], 200.0)
        self.assertEqual(summary["failed"], ["testScrollGipfelbuch"])

    def test_markdown_lists_every_screen(self):
        text = perf_summary.markdown(perf_summary.summarize(perf_summary.parse_log(LOG)))
        self.assertIn("0.912 s", text)
        self.assertIn("| Fahrten | 12.5 ms/s", text)
        self.assertIn("Statistik (+1 500 Fahrten)", text)
        self.assertIn("Fehlgeschlagen", text)

    def test_empty_log(self):
        text = perf_summary.markdown(perf_summary.summarize(perf_summary.parse_log("no metrics here")))
        self.assertIn("Keine Messwerte", text)

    def test_app_diagnostics(self):
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "events.json"), "w") as f:
                json.dump([{"kind": "watchdogHang", "screen": "Statistik", "durationMs": 420},
                           {"kind": "watchdogHang", "screen": "Statistik", "durationMs": 300},
                           {"kind": "abnormalExit"}], f)
            with open(os.path.join(d, "sessions.json"), "w") as f:
                json.dump({"current": {"timings": {"Analytics.make": {"count": 2, "totalMs": 30, "maxMs": 20}},
                                       "launch": {"initToFirstFrameMs": 400}},
                           "history": [{"timings": {"Analytics.make": {"count": 1, "totalMs": 10, "maxMs": 10}}}]}, f)
            diag = perf_summary.app_diagnostics(d)
        self.assertEqual(diag["hangs"], 2)
        self.assertEqual(diag["hangsByScreen"]["Statistik"]["count"], 2)
        self.assertEqual(diag["timings"]["Analytics.make"]["count"], 3)
        self.assertEqual(diag["timings"]["Analytics.make"]["maxMs"], 20)
        text = perf_summary.markdown(perf_summary.summarize(perf_summary.parse_log(LOG)), diag)
        self.assertIn("`Analytics.make` | 3 | 13.3 ms | 20.0 ms", text)
        self.assertIn("| Statistik | 2 | 420 ms | 720 ms |", text)


if __name__ == "__main__":
    unittest.main()
