#!/usr/bin/env python3
"""Trademark guard (docs/LOGO_SPEC.md §1): fail if a ski-area / region brand logo or a logo-pack file is in the checkout.

    python3 -I tools/check_no_brand_logos.py [repo] [--hashes tools/brand_logo_hashes.txt]

Ski-area and region logos never go into the public repo or the app bundle – they are served only by the Cloudflare
logo pack (the Landeswappen in Assets.xcassets/Wappen are public-domain official works and allowed). The check compares
the SHA-256 of every image, vector and archive file in the checkout with the hashes of every collected brand logo and
of every file of the built logo pack (`brand_logo_hashes.txt`: "<sha256>  <source>" per line – hashes only, no logos).
It also rejects logo-pack artefacts by name (`*.logopack.zip`, `logo-pack*/`, `pack-<version>.zip`).
Exit status 1 on a hit, 0 otherwise.
"""
import argparse
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EXT = {".png", ".jpg", ".jpeg", ".webp", ".svg", ".pdf", ".gif", ".zip", ".ai", ".eps", ".heic", ".avif"}
SKIP_DIRS = {".git", ".build", "node_modules", "DerivedData", ".wrangler", ".swiftpm"}
PACK_NAME = re.compile(r"(\.logopack\.zip$|^logo-pack|^pack-\d{10}\.zip$)", re.IGNORECASE)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_hashes(path):
    """"<sha256>  <source>" lines → {sha256: source}; blank lines and # comments are ignored."""
    out = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            h, _, src = line.partition("  ")
            if re.fullmatch(r"[0-9a-f]{64}", h):
                out[h] = src.strip() or "logo"
    return out


def scan(repo, hashes):
    """(hits, name hits, files checked): hash matches and logo-pack artefacts by name."""
    hits, names, n = [], [], 0
    for dp, dn, fn in os.walk(repo):
        dn[:] = [d for d in dn if d not in SKIP_DIRS]
        for d in dn:
            if PACK_NAME.search(d):
                names.append(os.path.relpath(os.path.join(dp, d), repo) + "/")
        for f in fn:
            p = os.path.join(dp, f)
            if PACK_NAME.search(f):
                names.append(os.path.relpath(p, repo))
            if os.path.splitext(f)[1].lower() in EXT and os.path.isfile(p):
                n += 1
                h = sha256(p)
                if h in hashes:
                    hits.append((os.path.relpath(p, repo), hashes[h]))
    return hits, names, n


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("repo", nargs="?", default=os.path.dirname(HERE))
    ap.add_argument("--hashes", default=os.path.join(HERE, "brand_logo_hashes.txt"))
    a = ap.parse_args(argv)
    hashes = load_hashes(a.hashes)
    if not hashes:
        print(f"no hashes in {a.hashes}", file=sys.stderr)
        return 2
    hits, names, n = scan(a.repo, hashes)
    for rel, src in hits:
        print(f"BRAND LOGO IN REPO: {rel}  (= {src})")
    for rel in names:
        print(f"LOGO PACK ARTEFACT IN REPO: {rel}")
    print(f"checked {n} files against {len(hashes)} known logo hashes: {len(hits)} hit(s), {len(names)} pack artefact(s)")
    return 1 if hits or names else 0


if __name__ == "__main__":
    sys.exit(main())
