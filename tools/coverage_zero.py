#!/usr/bin/env python3
# ORIGINAL: the "no src/ file at 0%" ratchet (user, 2026-10-14) — no swipl-devel counterpart.
# tools/coverage_zero.py LCOV KNOWN — exit 0 only if the src/ files with coverable lines and NO
# executed line in LCOV are exactly the files KNOWN lists (one path per line, `#` comments).
#   * a 0% file not in KNOWN fails: new untested code (or a test that moved into a subprocess);
#   * a KNOWN file that is no longer at 0% fails too, until it is taken off the list — so the list
#     can only shrink (the ratchet). The two at the start, pl-prologflag.jl and pl-codelist.jl, are
#     an audit item: missing tests, or tests in a subprocess coverage does not see.
# A file absent from LCOV entirely (never loaded) counts as 0%, when it is under src/.
import os, re, sys


def zero_files(lcov_path, root):
    hits, seen = {}, set()
    cur = None
    for line in open(lcov_path):
        line = line.strip()
        if line.startswith("SF:"):
            p = os.path.relpath(os.path.realpath(line[3:]), root) if os.path.isabs(line[3:]) else line[3:]
            cur = p if p.startswith("src" + os.sep) else None
            if cur:
                seen.add(cur)
                hits.setdefault(cur, [0, 0])
        elif cur and line.startswith("DA:"):
            n = int(line[3:].split(",")[1])
            hits[cur][0] += 1
            hits[cur][1] += n > 0
        elif line == "end_of_record":
            cur = None
    zero = {f for f, (lines, run) in hits.items() if lines > 0 and run == 0}
    for d, _, fs in os.walk(os.path.join(root, "src")):
        for f in fs:
            rel = os.path.relpath(os.path.join(d, f), root)
            if f.endswith(".jl") and rel not in seen:
                zero.add(rel)
    return zero


def known_files(path):
    out = set()
    for line in open(path):
        line = line.split("#", 1)[0].strip()
        if line:
            out.add(line)
    return out


def main(argv):
    if len(argv) != 3:
        print("usage: tools/coverage_zero.py LCOV KNOWN", file=sys.stderr)
        return 2
    root = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    zero, known = zero_files(argv[1], root), known_files(argv[2])
    if not os.path.getsize(argv[1]) or not re.search(r"^SF:", open(argv[1]).read(), re.M):
        print("coverage_zero: the LCOV file names no source file — no verdict (fail closed)")
        return 1
    new, gone = sorted(zero - known), sorted(known - zero)
    for f in new:
        print(f"coverage_zero: {f} is at 0% — test it, or (audited) list it in {argv[2]}")
    for f in gone:
        print(f"coverage_zero: {f} is no longer at 0% — take it off {argv[2]} (the list only shrinks)")
    print(f"coverage_zero: {len(zero)} src/ file(s) at 0%, {len(known)} listed — "
          + ("OK" if not new and not gone else "FAIL"))
    return 0 if not new and not gone else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
