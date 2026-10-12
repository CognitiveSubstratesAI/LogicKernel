#!/usr/bin/env python3
# ORIGINAL: the warm lane's struct gate (user, 2026-10-12) — no swipl-devel counterpart.
# tools/struct_snapshot.py SRC — `name<TAB>hash` for every struct the .jl files under SRC define.
#
# tools/warm.sh `_struct_gate` compares this with the snapshot taken when its daemon started: a
# struct whose definition changed restarts the daemon ("struct changed: <name>"). The hash is of the
# definition from its `struct` line to the `end` at the same indentation, with comments, blank lines
# and runs of spaces left out — so a comment or a re-indentation changes nothing, and a field, its
# type, the supertype, `mutable`, a parameter or an inner constructor does. Two structs of one name
# (two files) hash together.
import hashlib
import os
import re
import sys

RX = re.compile(r"^(\s*)(?:@[\w.]+\s+)*(?:mutable\s+)?struct\s+([A-Za-z_][A-Za-z0-9_]*)")


def snapshot(src):
    out = {}
    for d, dirs, fs in os.walk(src):
        dirs.sort()
        for f in sorted(fs):
            if not f.endswith(".jl"):
                continue
            with open(os.path.join(d, f), encoding="utf-8", errors="replace") as fh:
                lines = fh.read().split("\n")
            i = 0
            while i < len(lines):
                m = RX.match(lines[i])
                if m:
                    indent, name = m.group(1), m.group(2)
                    body, j = [], i
                    while j < len(lines):
                        body.append(re.sub(r"\s+", " ", re.sub(r"#.*$", "", lines[j])).strip())
                        if j > i and re.match(re.escape(indent) + r"end\b", lines[j]):
                            break
                        if j == i and re.search(r"\bend\s*(#.*)?$", lines[j]):   # a one-line struct
                            break
                        j += 1
                    text = out.get(name, "") + "\n".join(b for b in body if b)
                    out[name] = hashlib.sha1(text.encode()).hexdigest()[:16]
                    i = j
                i += 1
    return out


if __name__ == "__main__":
    if len(sys.argv) != 2 or not os.path.isdir(sys.argv[1]):
        print("usage: tools/struct_snapshot.py SRC", file=sys.stderr)
        sys.exit(2)
    snap = snapshot(sys.argv[1])
    if not snap:                                    # an empty snapshot would compare equal to nothing
        print("struct_snapshot: no struct found under " + sys.argv[1], file=sys.stderr)
        sys.exit(1)
    for k in sorted(snap):
        print(k + "\t" + snap[k])
