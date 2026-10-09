#!/usr/bin/env python3
"""Writes the small KBPL v2 test fixtures (ENRICH_SPEC "Step 0") into
Packages/KlimaCore/Tests/KlimaCoreTests/Fixtures/places/v2/.

The subset covers the three reference stops of the spec and their surroundings: Warth (Vorarlberg) Dorfplatz
`at:48:344` with the whole Gemeinde Warth, St. Anton am Arlberg Bahnhof `at:47:1222`, Wien Floridsdorf `at:49:334`,
plus Innsbruck Hbf, St. Anton im Montafon and Warth/Neunkirchen (spot checks) and the stops their lines reach next.
The v2 files are written by the format prototype `encode_v2.py` (ENRICH_SPEC Appendix A) from a v1 subset of the
shipped files and the enrichment outputs, so they follow the prototype layout (Appendix B deltas still apply: curated
ski areas sit in the OSM META, one shared operator list). Regenerate them with the WP-D1 port once it exists.

    python3 -I scripts/places_v2_fixtures.py --encoder <enrich/spec/encode_v2.py> --lines <enrich/lines/out> \
        --lines-official <enrich/lines/out_official> --tags <enrich/tags/out/tags.json> [--repo .]

Outputs (deterministic: same inputs → same bytes):
    v1/places.bin, v1/localities.bin       the subset in today's v1 layout (AT-C2)
    places.bin, stops_osm.bin, localities.bin   the same subset as KBPL v2, sections raw DEFLATE (codec 1) except RPRD/BASE
    stops_osm_other_base.bin               stops_osm.bin of a "different build" (other BASE, AT-C3)
    corrupt/places_bad_crc.bin             places.bin with the STRS CRC changed in the directory (CRC mismatch)
    corrupt/places_bad_deflate.bin         places.bin with one byte of the deflated RECS stream changed
    inflate/*.deflate + inflate/vectors.json   RFC 1951 vectors for the pure-Swift Inflate (AT-C1)
    manifest.json                          subset ids, counts, per-file SHA-256 and per-section CRCs
Stdlib only.
"""
import argparse
import hashlib
import json
import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib

sys.dont_write_bytecode = True

SEEDS = [  # (stop id, radius in m around it that is taken completely)
    ("at:48:344", 1500),    # Warth (Vorarlberg) Dorfplatz – the reference case
    ("at:47:1222", 600),    # St. Anton am Arlberg Bahnhof
    ("at:49:334", 300),     # Wien Floridsdorf
    ("at:47:1187", 300),    # Innsbruck Hbf (no ski tag; Tirol KlimaTicket default)
    ("at:48:187", 300),     # St. Anton im Montafon (not Arlberg)
    ("at:43:30742", 500),   # Warth/Neunkirchen Marktplatz (NÖ, no ski tag)
]
WHOLE_GEMEINDEN = {80239}   # Warth (Vorarlberg)
DEFLATE = "RECS,STRS,LSTP,TAGS,META,LPAT,LCAT,LNAM,GTAG,EXTR,GEMS"


def dist_m(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 2 * 6371000 * math.asin(math.sqrt(h))


# ------------------------------------------------------------------------------------------------ v1 files
def read_v1(path):
    """Raw v1 records (kept byte-exact apart from the remapped offsets)."""
    b = open(path, "rb").read()
    magic, ver, _fl, n, ng = struct.unpack_from("<4sHHII", b, 0)
    assert magic == b"KBPL" and ver == 1, path
    o_rec, l_rec, o_str, l_str, o_gem, l_gem, o_ex, l_ex = struct.unpack_from("<8I", b, 16)
    n_stops = struct.unpack_from("<I", b, 48)[0]

    def s(o):
        e = b.index(b"\0", o_str + o)
        return b[o_str + o:e].decode("utf-8")
    gems = [struct.unpack_from("<II", b, o_gem + 8 * g) for g in range(ng)]
    gems = [(gkz, s(so)) for gkz, so in gems]
    recs = []
    for i in range(n):
        f = list(struct.unpack_from("<iiIIHHHBBBBH", b, o_rec + 28 * i))
        ex = []
        if f[3] != 0xFFFFFFFF:
            k = b[o_ex + f[3]]
            for j in range(k):
                tag, v = struct.unpack_from("<BI", b, o_ex + f[3] + 1 + 5 * j)
                ex.append((tag, s(v) if tag in (3, 5, 7) else v))
        recs.append({"f": f, "str": s(f[2]), "ex": ex, "gem": gems[f[6]] if f[6] != 0xFFFF else None})
    return recs, n_stops, gems


def write_v1(path, recs, n_stops):
    """Same layout as scripts/build_places.py write_bin (header 64 B, RECS, STRS, GEMS, EXTR)."""
    pool = bytearray(b"\0")
    smap = {}

    def off(t):
        if t not in smap:
            smap[t] = len(pool)
            pool.extend(t.encode("utf-8") + b"\0")
        return smap[t]
    gem_list = sorted({r["gem"] for r in recs if r["gem"]}, key=lambda g: g[0])
    gem_idx = {g: i for i, g in enumerate(gem_list)}
    out_recs, extras = bytearray(), bytearray()
    for r in recs:
        f = list(r["f"])
        f[2] = off(r["str"])
        f[6] = gem_idx[r["gem"]] if r["gem"] else 0xFFFF
        f[3] = 0xFFFFFFFF
        if r["ex"]:
            f[3] = len(extras)
            extras.append(len(r["ex"]))
            for tag, v in r["ex"]:
                extras.extend(struct.pack("<BI", tag, off(v) if tag in (3, 5, 7) else v))
        out_recs.extend(struct.pack("<iiIIHHHBBBBH", *f))
    gsec = bytearray()
    for gkz, name in gem_list:
        gsec.extend(struct.pack("<II", gkz, off(name)))
    o_rec = 64
    o_str = o_rec + len(out_recs)
    o_gem = o_str + len(pool)
    o_ex = o_gem + len(gsec)
    hdr = struct.pack("<4sHHII", b"KBPL", 1, 0, len(recs), len(gem_list))
    hdr += struct.pack("<8I", o_rec, len(out_recs), o_str, len(pool), o_gem, len(gsec), o_ex, len(extras))
    hdr += struct.pack("<I", n_stops)
    hdr = hdr.ljust(64, b"\0")
    with open(path, "wb") as fh:
        fh.write(hdr + out_recs + pool + gsec + extras)


# ------------------------------------------------------------------------------------------------ KBPL v2 helpers
def read_dir(b):
    dir_off, n, _ = struct.unpack_from("<III", b, 52)
    return [list(struct.unpack_from("<4sIIIBBHII", b, dir_off + 28 * i)) + [dir_off + 28 * i] for i in range(n)]


def sections_raw(b):
    out = []
    for t, o, sl, rl, c, _z, cnt, h, _r, _pos in read_dir(b):
        raw = b[o:o + sl]
        if c == 1:
            raw = zlib.decompress(raw, -15)
        assert len(raw) == rl and zlib.crc32(raw) == h
        out.append((t.decode(), raw, c, cnt))
    return out


# ------------------------------------------------------------------------------------------------ inflate vectors
def lcg(n, seed=1):
    out = bytearray(n)
    x = seed
    for i in range(n):
        x = (x * 1103515245 + 12345) & 0x7FFFFFFF
        out[i] = (x >> 16) & 0xFF
    return bytes(out)


def repeat(text, n):
    t = text.encode("utf-8")
    return (t * (n // len(t) + 1))[:n]


class BitWriter:
    def __init__(self):
        self.out, self.acc, self.n = bytearray(), 0, 0

    def bits(self, v, k):           # LSB first (RFC 1951 §3.1.1)
        self.acc |= v << self.n
        self.n += k
        while self.n >= 8:
            self.out.append(self.acc & 0xFF)
            self.acc >>= 8
            self.n -= 8

    def huff(self, code, k):        # Huffman codes are packed MSB first
        rev = 0
        for i in range(k):
            if code >> i & 1:
                rev |= 1 << (k - 1 - i)
        self.bits(rev, k)

    def align(self):
        if self.n:
            self.bits(0, 8 - self.n)

    def done(self):
        self.align()
        return bytes(self.out)


def far_match_stream(history):
    """Stored block with 32,768 bytes, then a fixed-Huffman block: one match of length 258 at distance 32,768
    (zlib never emits distances > 32,506, so this one is written by hand)."""
    assert len(history) == 32768
    w = BitWriter()
    w.bits(0, 1)                    # not final
    w.bits(0, 2)                    # stored
    w.align()
    w.bits(len(history), 16)
    w.bits(len(history) ^ 0xFFFF, 16)
    for byte in history:
        w.bits(byte, 8)
    w.bits(1, 1)                    # final
    w.bits(1, 2)                    # fixed Huffman
    w.huff(0b11000101, 8)           # literal/length symbol 285 (= length 258): fixed code 280–287 → 11000000 + 5
    w.huff(29, 5)                   # distance code 29: base 24,577, 13 extra bits
    w.bits(32768 - 24577, 13)
    w.huff(0, 7)                    # end of block (symbol 256 → 7-bit code 0)
    return w.done()


def deflate(data, level=9, strategy=zlib.Z_DEFAULT_STRATEGY):
    c = zlib.compressobj(level, zlib.DEFLATED, -15, 9, strategy)
    return c.compress(data) + c.flush()


def write_vectors(out_dir, spec_text):
    os.makedirs(out_dir, exist_ok=True)
    text = repeat(spec_text, 24_000)                    # mixed German text with long repeats → dynamic blocks
    vectors = [
        ("empty", deflate(b""), {"kind": "bytes", "hex": ""}),
        ("stored", deflate(lcg(66_000, 7), level=0), {"kind": "lcg", "seed": 7, "length": 66_000}),
        ("fixed", deflate(text[:6000], strategy=zlib.Z_FIXED), {"kind": "text", "length": 6000}),
        ("dynamic", deflate(text), {"kind": "text", "length": len(text)}),
        ("huffman_only", deflate(text[:9000], strategy=zlib.Z_HUFFMAN_ONLY), {"kind": "text", "length": 9000}),
        ("rle", deflate(lcg(3000, 3) * 4, strategy=zlib.Z_RLE), {"kind": "lcg_repeat", "seed": 3, "length": 3000,
                                                                "times": 4}),
        ("repetitive_1mib", deflate(repeat("KlimaBilanz · Warth (Vorarlberg) Dorfplatz · 110 852 Skibus\n", 1 << 20)),
         {"kind": "repeat", "text": "KlimaBilanz · Warth (Vorarlberg) Dorfplatz · 110 852 Skibus\n", "length": 1 << 20}),
        ("match258_dist32768", far_match_stream(lcg(32768, 11)), {"kind": "far_match", "seed": 11}),
    ]
    with open(os.path.join(out_dir, "text.txt"), "wb") as fh:
        fh.write(text)
    manifest = []
    for name, stream, expect in vectors:
        raw = zlib.decompress(stream, -15)               # Python's zlib is the reference decoder
        if expect["kind"] == "far_match":
            assert raw == lcg(32768, 11) + lcg(32768, 11)[:258]
        with open(os.path.join(out_dir, name + ".deflate"), "wb") as fh:
            fh.write(stream)
        manifest.append({"name": name, "file": name + ".deflate", "rawLength": len(raw), "crc32": zlib.crc32(raw),
                         "sha256": hashlib.sha256(raw).hexdigest(), "expect": expect})
    with open(os.path.join(out_dir, "vectors.json"), "w", encoding="utf-8") as fh:
        json.dump({"lcg": "x = (x * 1103515245 + 12345) & 0x7FFFFFFF; byte = (x >> 16) & 0xFF (x starts at seed)",
                   "text": "text.txt (prefix of the given length)", "vectors": manifest}, fh, indent=1,
                  ensure_ascii=False)
        fh.write("\n")


# ------------------------------------------------------------------------------------------------ main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--encoder", required=True, help="enrich/spec/encode_v2.py")
    ap.add_argument("--lines", required=True)
    ap.add_argument("--lines-official", required=True)
    ap.add_argument("--tags", required=True)
    ap.add_argument("--repo", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    a = ap.parse_args()
    repo = os.path.abspath(a.repo)
    out = os.path.join(repo, "Packages/KlimaCore/Tests/KlimaCoreTests/Fixtures/places/v2")
    res = os.path.join(repo, "App/Resources")

    P, n_stops_all, _ = read_v1(os.path.join(res, "places.bin"))
    Lc, _, _ = read_v1(os.path.join(res, "localities.bin"))
    stops = P[:n_stops_all]
    ids = [r["str"].split("\x1f")[0] for r in stops]
    pos = {i: (r["f"][0] / 1e6, r["f"][1] / 1e6) for i, r in zip(ids, stops)}
    Bf = json.load(open(os.path.join(a.lines, "lines_by_stop.json")))
    Bo = json.load(open(os.path.join(a.lines_official, "lines_by_stop.json")))

    keep = set()
    for sid, radius in SEEDS:
        keep |= {i for i in ids if dist_m(pos[sid], pos[i]) <= radius}
    keep |= {i for i, r in zip(ids, stops) if r["gem"] and r["gem"][0] in WHOLE_GEMEINDEN}
    for sid, _ in SEEDS:                                   # the stops the seeds' lines reach next
        for B in (Bf, Bo):
            for _li, _to, nx, _c in (B.get(sid) or {"l": []})["l"]:
                keep |= set(nx) & set(ids)
    sub = [r for i, r in zip(ids, stops) if i in keep]
    sub_ids = [r["str"].split("\x1f")[0] for r in sub]
    locs = [r for r in Lc if any(t == 7 and v in keep for t, v in r["ex"])]

    work = tempfile.mkdtemp(prefix="kbpl-fixtures-")
    try:
        os.makedirs(os.path.join(work, "v1"))
        write_v1(os.path.join(work, "v1/places.bin"), sub, len(sub))
        write_v1(os.path.join(work, "v1/localities.bin"), locs, 0)

        # lines: only those of the subset, renumbered (catalogue index == id), successors kept
        def filter_lines(src_dir, dst_dir):
            cat = json.load(open(os.path.join(src_dir, "lines_catalog.json")))
            by = json.load(open(os.path.join(src_dir, "lines_by_stop.json")))
            by = {k: v for k, v in by.items() if k in keep}
            used = {li for v in by.values() for li, *_ in v["l"]}
            lines = cat["lines"]
            more = {lines[li]["successor"] for li in used if lines[li].get("successor") is not None}
            used = sorted(used | more)
            remap = {old: new for new, old in enumerate(used)}
            new_lines = []
            for old in used:
                L = dict(lines[old])
                L["id"] = remap[old]
                if L.get("successor") is not None:
                    L["successor"] = remap.get(L["successor"])
                new_lines.append(L)
            for v in by.values():
                v["l"] = [[remap[li], to, [x for x in nx if x in keep], c] for li, to, nx, c in v["l"]]
            os.makedirs(dst_dir)
            json.dump({"lines": new_lines, "net_names": cat["net_names"]},
                      open(os.path.join(dst_dir, "lines_catalog.json"), "w"), ensure_ascii=False)
            json.dump(by, open(os.path.join(dst_dir, "lines_by_stop.json"), "w"), ensure_ascii=False)
            return len(new_lines)
        n_full = filter_lines(a.lines, os.path.join(work, "lines"))
        n_off = filter_lines(a.lines_official, os.path.join(work, "lines_official"))

        T = json.load(open(a.tags))
        st = {k: v for k, v in T["stops"].items() if k in keep}
        ski_ids, reg_ids = set(), set()
        for v in st.values():
            for t in v["t"]:
                if t[0] in ("ski", "skiAlliance", "glacierSki"):
                    ski_ids.add(t[1])
                elif t[0] in ("region", "landscape"):
                    reg_ids.add(t[1])
        for sid in list(ski_ids):                          # parents / alliances of the areas present
            par = (T["skiAreas"].get(sid) or {}).get("parent")
            if par:
                ski_ids.add(par)
        T2 = dict(T)
        T2["stops"] = st
        T2["skiAreas"] = {k: v for k, v in T["skiAreas"].items() if k in ski_ids}
        T2["regions"] = {k: v for k, v in T["regions"].items() if k in reg_ids}
        json.dump(T2, open(os.path.join(work, "tags.json"), "w"), ensure_ascii=False)

        enc_out = os.path.join(work, "v2")
        subprocess.run([sys.executable, "-I", a.encoder, "--places-bin", os.path.join(work, "v1/places.bin"),
                        "--localities-bin", os.path.join(work, "v1/localities.bin"),
                        "--lines", os.path.join(work, "lines"), "--lines-official", os.path.join(work, "lines_official"),
                        "--tags", os.path.join(work, "tags.json"),
                        "--build-places", os.path.join(repo, "scripts/build_places.py"),
                        "--out", enc_out, "--localities-v2", "--deflate", DEFLATE],
                       check=True, stdout=subprocess.DEVNULL)

        if os.path.isdir(out):
            shutil.rmtree(out)
        os.makedirs(os.path.join(out, "v1"))
        os.makedirs(os.path.join(out, "corrupt"))
        for f in ("v1/places.bin", "v1/localities.bin"):
            shutil.copyfile(os.path.join(work, f), os.path.join(out, f))
        for f in ("places.bin", "stops_osm.bin", "localities.bin"):
            shutil.copyfile(os.path.join(enc_out, f), os.path.join(out, f))
        sys.path.insert(0, os.path.dirname(os.path.abspath(a.encoder)))
        import encode_v2 as E                                  # noqa: E402 – the prototype's container writer

        # a stops_osm.bin of another build: same content, other BASE
        osm = open(os.path.join(out, "stops_osm.bin"), "rb").read()
        secs = [(t, hashlib.sha256(b"another build").digest() if t == "BASE" else r, c, n)
                for t, r, c, n in sections_raw(osm)]
        hx = osm[8:52]
        E.write_container(os.path.join(out, "stops_osm_other_base.bin"), 2, secs, hx)

        places = bytearray(open(os.path.join(out, "places.bin"), "rb").read())
        d = {e[0].decode(): e for e in read_dir(bytes(places))}
        bad = bytearray(places)
        struct.pack_into("<I", bad, d["STRS"][9] + 20, d["STRS"][7] ^ 0x00010000)
        open(os.path.join(out, "corrupt/places_bad_crc.bin"), "wb").write(bad)
        bad = bytearray(places)
        rec_off, rec_len = d["RECS"][1], d["RECS"][2]
        bad[rec_off + rec_len // 2] ^= 0x5A
        open(os.path.join(out, "corrupt/places_bad_deflate.bin"), "wb").write(bad)

        spec_text = open(os.path.join(repo, "docs/ENRICH_SPEC.md"), encoding="utf-8").read() \
            if os.path.exists(os.path.join(repo, "docs/ENRICH_SPEC.md")) else __doc__
        write_vectors(os.path.join(out, "inflate"), spec_text)

        files = {}
        for root, _d, fs in os.walk(out):
            for f in sorted(fs):
                p = os.path.join(root, f)
                rel = os.path.relpath(p, out)
                if rel == "manifest.json":
                    continue
                files[rel] = {"bytes": os.path.getsize(p), "sha256": hashlib.sha256(open(p, "rb").read()).hexdigest()}
        sections = {}
        for f in ("places.bin", "stops_osm.bin", "localities.bin"):
            b = open(os.path.join(out, f), "rb").read()
            sections[f] = {e[0].decode(): {"codec": e[4], "stored": e[2], "raw": e[3], "count": e[6], "crc32": e[7]}
                           for e in read_dir(b)}
        manifest = {
            "generator": "scripts/places_v2_fixtures.py (encode_v2.py prototype layout)",
            "seeds": [s for s, _ in SEEDS], "stops": sub_ids, "localities": [r["str"].split("\x1f")[0] for r in locs],
            "counts": {"stops": len(sub), "localities": len(locs), "linesFull": n_full, "linesOfficial": n_off},
            "files": dict(sorted(files.items())), "sections": sections}
        with open(os.path.join(out, "manifest.json"), "w", encoding="utf-8") as fh:
            json.dump(manifest, fh, indent=1, ensure_ascii=False)
            fh.write("\n")
        print(json.dumps(manifest["counts"]), sum(v["bytes"] for v in files.values()), "bytes")
    finally:
        shutil.rmtree(work)


if __name__ == "__main__":
    main()
