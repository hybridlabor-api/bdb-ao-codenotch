#!/usr/bin/env python3
"""Write THIRD_PARTY_LICENSES.txt from Package.resolved and .build/checkouts."""
import glob, json, os, sys

out = sys.argv[1]
pins = json.load(open("Package.resolved"))["pins"]
parts = ["Third-party Swift packages resolved for this build (Package.resolved).\n"]
for p in sorted(pins, key=lambda p: p["identity"]):
    name, ver = p["identity"], p["state"].get("version", p["state"].get("revision", "?"))
    files = sorted(f for g in ("LICENSE*", "LICENCE*", "COPYING*")
                   for f in glob.glob(f".build/checkouts/{name}/{g}") if os.path.isfile(f))
    parts.append("=" * 72 + f"\n{name} {ver}\n{p['location']}\n" + "=" * 72 + "\n")
    parts.append(open(files[0], errors="replace").read() if files
                 else "Licence file not found in the resolved checkout.\n")
open(out, "w").write("\n".join(parts))
