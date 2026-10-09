import unittest

import symbolicate_diagnostics as sym

BUNDLE = {
    "app": {"version": "1.0.0", "build": "139"},
    "metricKit": {"payloads": [{"file": "diagnostic-x.json", "payload": {"crashDiagnostics": [{
        "diagnosticMetaData": {"appBuildVersion": "139"},
        "callStackTree": {"callStackPerThread": True, "callStacks": [{"threadAttributed": True, "callStackRootFrames": [{
            "binaryName": "libswiftCore.dylib", "offsetIntoBinaryTextSegment": 4096, "subFrames": [{
                "binaryName": "KlimaBilanz", "offsetIntoBinaryTextSegment": 304112, "subFrames": [{
                    "binaryName": "KlimaBilanz", "offsetIntoBinaryTextSegment": 1200}]}]}]}]}}]}}]},
}


class SymbolicateTests(unittest.TestCase):
    def test_walks_attributed_stack_top_down(self):
        (_, _, diagnostic), = sym.diagnostics(BUNDLE)
        (label, frames), = sym.stacks(diagnostic)
        self.assertIn("betroffen", label)
        self.assertEqual([f["binaryName"] for f in frames], ["libswiftCore.dylib", "KlimaBilanz", "KlimaBilanz"])

    def test_collects_app_offsets_only(self):
        self.assertEqual(sym.app_offsets(BUNDLE, "KlimaBilanz"), [1200, 304112])


if __name__ == "__main__":
    unittest.main()
