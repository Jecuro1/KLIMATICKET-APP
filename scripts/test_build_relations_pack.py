#!/usr/bin/env python3
"""Tests for build_relations_pack.py and the pack/catalogue agreement (fixtures and repository files only, no network):
python3 -m unittest discover -s scripts -p 'test_*.py'"""
import hashlib
import json
import os
import struct
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import build_relations_pack as brp  # noqa: E402


def small_pack(version=2, valid_from="2026-12-13", pairs=None):
    points = [{"name": f"P{i}", "stationID": f"at:test:{i}"} for i in range(6)]
    pairs = pairs if pairs is not None else [(a, b, 100 + a * 10 + b) for a in range(6) for b in range(a + 1, 6)]
    raw = b"".join(struct.pack("<HHH", *p) for p in pairs)
    return brp.pack_bytes(version, valid_from, "test", points, brp.raw_deflate(raw), raw)


class PackFormat(unittest.TestCase):
    def test_a_well_formed_pack_passes_the_check(self):
        self.assertEqual(brp.check_pack(small_pack()), [])

    def test_header_carries_version_and_day(self):
        data = small_pack(version=7, valid_from="2026-12-13")
        self.assertEqual(data[:4], b"KBRP")
        fmt, flags, version, day = struct.unpack_from("<HHII", data, 4)
        self.assertEqual((fmt, flags, version, day), (1, 0, 7, 20261213))

    def test_damage_is_found(self):
        data = bytearray(small_pack())
        data[-3] ^= 0xFF
        self.assertTrue(brp.check_pack(bytes(data)))
        self.assertTrue(brp.check_pack(b"KBPL" + small_pack()[4:]))
        self.assertTrue(brp.check_pack(small_pack() + b"\0"))

    def test_pairs_must_be_canonical(self):
        self.assertTrue(brp.check_pack(small_pack(pairs=[(1, 0, 100)])))               # B before A
        self.assertTrue(brp.check_pack(small_pack(pairs=[(0, 1, 100), (0, 1, 110)])))   # twice
        self.assertTrue(brp.check_pack(small_pack(pairs=[(0, 2, 100), (0, 1, 110)])))   # not ascending
        self.assertTrue(brp.check_pack(small_pack(pairs=[(0, 1, 0)])))                  # price 0
        self.assertTrue(brp.check_pack(small_pack(pairs=[(0, 1, 65535)])))              # clamp value
        self.assertTrue(brp.check_pack(small_pack(pairs=[(0, 9, 100)])))                # point that does not exist

    def test_pair_count_is_compared_with_the_table_in_use(self):
        data = small_pack()   # 15 pairs
        self.assertEqual(brp.check_pack(data, reference_pairs=15), [])
        self.assertTrue(brp.check_pack(data, reference_pairs=30))


class RepositoryPack(unittest.TestCase):
    """data/relations-pack.bin is what tariffs.json describes, and holds the bundled table."""

    def test_pack_matches_the_catalogue_block(self):
        catalog = json.load(open(os.path.join(ROOT, "App", "Resources", "tariffs.json"), encoding="utf-8"))
        info = catalog["relationsPack"]
        data = open(os.path.join(ROOT, "data", os.path.basename(info["url"])), "rb").read()
        self.assertEqual(len(data), info["bytes"])
        self.assertEqual(hashlib.sha256(data).hexdigest(), info["sha256"])
        self.assertEqual(brp.check_pack(data), [])
        _, _, version, day = struct.unpack_from("<HHII", data, 4)
        self.assertEqual(version, info["version"])
        self.assertEqual(f"{day // 10000:04d}-{day // 100 % 100:02d}-{day % 100:02d}", info["validFrom"])

    def test_pack_holds_the_bundled_table(self):
        meta = json.load(open(os.path.join(ROOT, "App", "Resources", "relations-points.json"), encoding="utf-8"))
        bundled = brp.raw_inflate(open(os.path.join(ROOT, "App", "Resources", "relations.bin"), "rb").read())
        data = open(os.path.join(ROOT, "data", "relations-pack.bin"), "rb").read()
        p_stored = struct.unpack_from("<I", data, 24)[0]
        self.assertEqual(brp.raw_inflate(data[brp.HEADER + p_stored:]), bundled)
        self.assertEqual(json.loads(brp.raw_inflate(data[brp.HEADER:brp.HEADER + p_stored]))["points"], meta["points"])
        self.assertEqual(meta.get("version", 1), struct.unpack_from("<I", data, 8)[0],
                         "the published pack is the bundled table until a newer one is published")


if __name__ == "__main__":
    unittest.main()
