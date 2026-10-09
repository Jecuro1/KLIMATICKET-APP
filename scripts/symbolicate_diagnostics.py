#!/usr/bin/env python3
"""Symbolicates the MetricKit call stacks in a KlimaBilanz diagnostics export (Einstellungen › Diagnose & Stabilität).

Usage (macOS, Xcode command line tools):
    symbolicate_diagnostics.py KlimaBilanz-Diagnose-2026-10-09-1432.json KlimaBilanz.app.dSYM
    symbolicate_diagnostics.py export.json KlimaBilanz.app.dSYM --dry-run   # only print the atos commands

The dSYM must come from the same build as the export (CI artifact "dSYM-<version>-<build>", the build number is in
the export under app.build). Frames of the app binary are resolved with
`atos -o <dSYM>/Contents/Resources/DWARF/KlimaBilanz -l 0x100000000 <0x100000000 + offsetIntoBinaryTextSegment>`;
system frames stay as "<binary> +0x<offset>".
"""
import argparse
import json
import os
import shutil
import subprocess
import sys

LOAD_ADDRESS = 0x100000000
KINDS = ["crashDiagnostics", "hangDiagnostics", "cpuExceptionDiagnostics", "diskWriteExceptionDiagnostics",
         "appLaunchDiagnostics"]


def stacks(diagnostic):
    """[(thread label, [frame dicts top → bottom])] of one MetricKit diagnostic."""
    tree = diagnostic.get("callStackTree") or {}
    out = []
    for index, stack in enumerate(tree.get("callStacks") or []):
        label = f"Thread {index}" + (" (betroffen)" if stack.get("threadAttributed") else "")
        for root in stack.get("callStackRootFrames") or []:
            frames, frame = [], root
            while frame and len(frames) < 512:
                frames.append(frame)
                subs = frame.get("subFrames") or []
                frame = subs[0] if subs else None
            out.append((label, frames))
    return out


def diagnostics(bundle):
    """[(kind, payload file, diagnostic)] from the export's raw MetricKit payloads."""
    out = []
    for item in (bundle.get("metricKit") or {}).get("payloads") or []:
        payload = item.get("payload") or {}
        for kind in KINDS:
            for diagnostic in payload.get(kind) or []:
                out.append((kind, item.get("file", "?"), diagnostic))
    return out


def app_offsets(bundle, executable):
    offsets = set()
    for _, _, diagnostic in diagnostics(bundle):
        for _, frames in stacks(diagnostic):
            for f in frames:
                if f.get("binaryName") == executable and "offsetIntoBinaryTextSegment" in f:
                    offsets.add(int(f["offsetIntoBinaryTextSegment"]))
    return sorted(offsets)


def atos(dwarf, offsets):
    addresses = [hex(LOAD_ADDRESS + o) for o in offsets]
    cmd = ["atos", "-arch", "arm64", "-o", dwarf, "-l", hex(LOAD_ADDRESS)] + addresses
    result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    lines = result.stdout.strip().splitlines()
    return dict(zip(offsets, lines)) if len(lines) == len(offsets) else {}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("export")
    parser.add_argument("dsym")
    parser.add_argument("--executable", default="KlimaBilanz")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    with open(args.export, encoding="utf-8") as f:
        bundle = json.load(f)
    dwarf = os.path.join(args.dsym, "Contents", "Resources", "DWARF", args.executable)
    offsets = app_offsets(bundle, args.executable)
    app = bundle.get("app") or {}
    print(f"Export: Version {app.get('version', '?')} (Build {app.get('build', '?')}), "
          f"{len(diagnostics(bundle))} MetricKit-Diagnosen, {len(offsets)} App-Adressen")
    if not offsets:
        return 0
    if args.dry_run or not shutil.which("atos"):
        print("atos -arch arm64 -o", dwarf, "-l", hex(LOAD_ADDRESS), " ".join(hex(LOAD_ADDRESS + o) for o in offsets))
        return 0
    symbols = atos(dwarf, offsets)
    for kind, file, diagnostic in diagnostics(bundle):
        meta = diagnostic.get("diagnosticMetaData") or {}
        print(f"\n=== {kind} · {file} · Build {meta.get('appBuildVersion', '?')}")
        for label, frames in stacks(diagnostic):
            print(f"  {label}")
            for f in frames[:40]:
                binary = f.get("binaryName", "?")
                offset = int(f.get("offsetIntoBinaryTextSegment", 0))
                name = symbols.get(offset) if binary == args.executable else None
                print(f"    {binary:<28} +0x{offset:x}  {name or ''}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
