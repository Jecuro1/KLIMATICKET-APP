#!/usr/bin/env python3
"""Packs the relation-price table into the downloadable "KBRP" file (docs/TARIFF_FRESHNESS.md §3) and writes the catalogue
block that describes it.

  data/relations-pack.bin         the pack (what the app downloads, validates and installs)
  data/relations_pack_info.json   {url, sha256, version, validFrom, bytes} – build_tariffs.py copies it into tariffs.json
                                  as `relationsPack`

By default the pack is made from the table bundled in the app (App/Resources/relations-points.json + relations.bin), so it
carries exactly the numbers the app already has – no new data. A newer table (a new price list) is built into those two
files by scripts/build_relations.py first; then run this script with the new --version and --valid-from.

  python3 scripts/build_relations_pack.py                       # version and day taken from relations-points.json
  python3 scripts/build_relations_pack.py --version 2 --valid-from 2026-12-13
  python3 scripts/build_relations_pack.py --check data/relations-pack.bin   # parse and validate a pack (exit 1 on a problem)

Format (little endian), the same as RelationPack.swift:
   0 "KBRP" | 4 u16 format (1) | 6 u16 flags (0) | 8 u32 data version | 12 u32 validFrom yyyymmdd
  16 u32 pointCount | 20 u32 pairCount | 24 u32 pointsStoredLength | 28 u32 pointsRawLength
  32 u32 pairsStoredLength | 36 u32 pointsCRC32 | 40 u32 pairsCRC32 | 44 u32 0
  48 points section (raw DEFLATE of {"source", "points"} JSON), then pairs section (raw DEFLATE of u16 A, u16 B, u16 price)
Only the Python standard library."""
import argparse, hashlib, json, os, struct, sys, zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAGIC = b"KBRP"
FORMAT = 1
HEADER = 48
MAX_BYTES = 8 << 20
MAX_PRICE_UNITS = 30_000


def raw_deflate(data):
    comp = zlib.compressobj(9, zlib.DEFLATED, -15)
    return comp.compress(data) + comp.flush()


def raw_inflate(data):
    return zlib.decompress(data, -15)


def pack_bytes(version, valid_from, source, points, pairs_stored, pairs_raw):
    """`pairs_stored` is a raw-DEFLATE stream of `pairs_raw` (kept as is when it comes from relations.bin)."""
    y, m, d = (int(x) for x in valid_from.split("-"))
    points_raw = json.dumps({"source": source, "points": points}, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    points_stored = raw_deflate(points_raw)
    header = (MAGIC + struct.pack("<HHII", FORMAT, 0, version, y * 10000 + m * 100 + d)
              + struct.pack("<IIIIIIII", len(points), len(pairs_raw) // 6, len(points_stored), len(points_raw),
                            len(pairs_stored), zlib.crc32(points_raw), zlib.crc32(pairs_raw), 0))
    assert len(header) == HEADER
    return header + points_stored + pairs_stored


def check_pack(data, reference_pairs=None):
    """Parses and validates a pack like RelationPackValidator (without the SHA-256, which the catalogue holds).
    Returns the list of problems (empty = fine)."""
    problems = []
    if len(data) > MAX_BYTES:
        return ["larger than 8 MB"]
    if len(data) < HEADER or data[:4] != MAGIC:
        return ["bad magic"]
    fmt, flags, version, day = struct.unpack_from("<HHII", data, 4)
    point_count, pair_count, p_stored, p_raw, q_stored, p_crc, q_crc, _ = struct.unpack_from("<IIIIIIII", data, 16)
    if fmt != FORMAT or flags != 0:
        return [f"unsupported format {fmt}/{flags}"]
    if HEADER + p_stored + q_stored != len(data):
        return ["section lengths do not add up to the file size"]
    try:
        points_raw = raw_inflate(data[HEADER:HEADER + p_stored])
        pairs_raw = raw_inflate(data[HEADER + p_stored:])
    except zlib.error as e:
        return [f"inflate failed: {e}"]
    if zlib.crc32(points_raw) != p_crc or zlib.crc32(pairs_raw) != q_crc:
        problems.append("CRC-32 mismatch")
    block = json.loads(points_raw)
    ids = [p["stationID"] for p in block["points"]]
    if len(ids) != point_count or len(set(ids)) != len(ids) or "" in ids:
        problems.append("points: count, uniqueness or empty id")
    if len(pairs_raw) != pair_count * 6:
        problems.append("pair count does not match the pairs section")
    last = -1
    for i in range(pair_count):
        a, b, p = struct.unpack_from("<HHH", pairs_raw, i * 6)
        key = (a << 16) | b
        if not (a < b < point_count) or key <= last:
            problems.append(f"pair {i}: not canonical (A < B, ascending)")
            break
        last = key
        if not (1 <= p <= MAX_PRICE_UNITS):
            problems.append(f"pair {i}: price {p} out of range")
            break
    if reference_pairs and abs(pair_count - reference_pairs) * 4 > reference_pairs:
        problems.append(f"pair count {pair_count} is more than 25 % away from {reference_pairs}")
    valid_from = f"{day // 10000:04d}-{day // 100 % 100:02d}-{day % 100:02d}"
    print(f"pack: version {version}, valid from {valid_from}, {point_count} points, {pair_count} pairs, {len(data)} bytes, "
          f"sha256 {hashlib.sha256(data).hexdigest()}")
    return problems


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--points", default=os.path.join(ROOT, "App", "Resources", "relations-points.json"))
    ap.add_argument("--bin", default=os.path.join(ROOT, "App", "Resources", "relations.bin"))
    ap.add_argument("--out", default=os.path.join(ROOT, "data", "relations-pack.bin"))
    ap.add_argument("--info", default=os.path.join(ROOT, "data", "relations_pack_info.json"))
    ap.add_argument("--url", default="relations-pack.bin",
                    help="download URL: relative to the tariffs document (default) or an https URL on the same host")
    ap.add_argument("--version", type=int, help="data version (default: `version` of the points file, else 1)")
    ap.add_argument("--valid-from", help="first valid day, YYYY-MM-DD (default: `validFrom` of the points file)")
    ap.add_argument("--check", metavar="PACK", help="only parse and validate this pack file")
    args = ap.parse_args()

    if args.check:
        problems = check_pack(open(args.check, "rb").read())
        for p in problems:
            print("PROBLEM:", p)
        sys.exit(1 if problems else 0)

    meta = json.load(open(args.points, encoding="utf-8"))
    version = args.version if args.version is not None else int(meta.get("version", 1))
    valid_from = args.valid_from or meta["validFrom"]
    stored = open(args.bin, "rb").read()
    pairs_raw = raw_inflate(stored)
    data = pack_bytes(version, valid_from, meta.get("source", ""), meta["points"], stored, pairs_raw)
    problems = check_pack(data)
    if problems:
        for p in problems:
            print("PROBLEM:", p)
        sys.exit(1)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "wb") as f:
        f.write(data)
    info = {"url": args.url, "sha256": hashlib.sha256(data).hexdigest(), "version": version, "validFrom": valid_from,
            "bytes": len(data)}
    with open(args.info, "w", encoding="utf-8") as f:
        json.dump(info, f, indent=2)
        f.write("\n")
    print(f"wrote {args.out} and {args.info}")


if __name__ == "__main__":
    main()
