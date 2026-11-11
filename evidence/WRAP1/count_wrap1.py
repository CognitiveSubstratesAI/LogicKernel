"""Throwaway check of tools/mutants/WRAP1.py: every `old` occurs exactly once in its file, `new` differs, ids unique, targets exist.
Run: python3 -I evidence/WRAP1/count_wrap1.py <worktree root>"""
import os
import runpy
import sys

root = sys.argv[1]
ns = runpy.run_path(root + "/tools/mutants/WRAP1.py")
ms = ns["MUTANTS"]
bad = 0
ids = set()
for m in ms:
    src = open(root + "/" + m["file"]).read()
    n = src.count(m["old"])
    if n != 1 or m["old"] == m["new"] or m["id"] in ids:
        bad += 1
        print("BAD", m["id"][:40], "count", n, "same" if m["old"] == m["new"] else "")
    ids.add(m["id"])
    for t in m["targets"]:
        if not os.path.exists(root + "/" + t):
            bad += 1
            print("NOFILE", t)
    for k in m:
        if k not in ("id", "file", "old", "new", "equivalent", "targets", "expect"):
            bad += 1
            print("KEY", k)
print(len(ms), "mutants,", bad, "problems;", sum(1 for m in ms if m.get("equivalent")), "equivalent/deferred")
for t in ns["TARGETS"]:
    if not os.path.exists(root + "/" + t):
        print("NOFILE", t)
