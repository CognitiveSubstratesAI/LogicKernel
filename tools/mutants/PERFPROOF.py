# ORIGINAL: scratch list of the GATESPEED proof case (audit D-0535) - no swipl-devel counterpart.
# tools/mutants/PERFPROOF.py - two mutants of TRIE3 (the first killable one, TR3-L1, and the first declared EQUIVALENT one,
# TR3-U1), taken from tools/mutants/TRIE3.py by runpy, so no `old` text is duplicated here. Used ONLY on a scratch branch
# `perf/bat-PERFPROOF` (resolve_list in tools/mutate_ci.py maps it to this file): pushed TWICE to the same ref, the first
# push seeds the shared depot cache, the second must restore it (the step log says "dropping the restored ...") and still
# print `caught` for L1 and `EQUIVALENT (declared)` for U1. Never a mutants/* name for it. Delete after the proof.
import os
import runpy

_T = runpy.run_path(os.path.join(os.path.dirname(os.path.abspath(__file__)), "TRIE3.py"))
TARGETS = _T["TARGETS"]
MUTANTS = [m for m in _T["MUTANTS"] if m["id"].split()[0] in ("TR3-L1", "TR3-U1")]
assert len(MUTANTS) == 2
