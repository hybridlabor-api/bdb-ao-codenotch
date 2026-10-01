#!/usr/bin/env python3
"""Convert Sources/Localizable.xcstrings to <out>/<lang>.lproj/Localizable.strings.

Stands in for Xcode's string-catalog compiler. The catalog holds only plain
stringUnit entries, so a straight dump is lossless.
"""
import json, os, sys

src, out = sys.argv[1], sys.argv[2]
cat = json.load(open(src, encoding="utf-8"))
langs = {}
for key, entry in cat["strings"].items():
    for lang, loc in entry.get("localizations", {}).items():
        v = loc.get("stringUnit", {}).get("value")
        if v is not None:
            langs.setdefault(lang, {})[key] = v
langs.setdefault(cat["sourceLanguage"], {})

def q(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'

for lang, d in langs.items():
    if lang == cat["sourceLanguage"]:
        d = {**{k: k for k in cat["strings"]}, **d}
    p = os.path.join(out, f"{lang}.lproj")
    os.makedirs(p, exist_ok=True)
    with open(os.path.join(p, "Localizable.strings"), "w", encoding="utf-8") as f:
        for k, v in sorted(d.items()):
            f.write(f"{q(k)} = {q(v)};\n")
print(f"{len(langs)} languages")
