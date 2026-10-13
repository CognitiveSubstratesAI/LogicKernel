#!/usr/bin/env python3
# ORIGINAL: the evidence run's CI side (user, 2026-10-13) — no swipl-devel counterpart.
# tools/evidence_ci.py DIR — what .github/workflows/evidence.yml's last job
# calls. DIR holds, per term type T, `units_T.tsv` (test/runtests.jl under LOGICKERNEL_TERM_ONLY:
# `all<TAB>label` for every unit of the suite, `ran<TAB>label` for those the job ran) and `row_T.md`
# (the job's verdict row). Prints the table and checks THE PARTITION: every job enumerated the same
# full list, every unit of it was run by exactly one job, and nothing outside it was run. Exit 1 on a
# failed or missing job, or a broken partition — three green jobs that skipped a unit are not green.
import os
import sys

TERMS = ("reference", "alt", "alt_interned")


def main(d):
    problems, rows, alls, rans = [], [], {}, {}
    for t in TERMS:
        row = os.path.join(d, "row_%s.md" % t)
        units = os.path.join(d, "units_%s.tsv" % t)
        if os.path.isfile(row):
            text = open(row).read().strip()
            rows.append(text)
            if "passed" not in text:
                problems.append("%s: the job did not pass" % t)
        else:
            rows.append("| %s | **NO VERDICT** | — |" % t)
            problems.append("%s: no verdict row (the job died before writing one)" % t)
        if not os.path.isfile(units):
            problems.append("%s: no unit list" % t)
            continue
        alls[t], rans[t] = [], []
        for line in open(units):
            kind, _, label = line.rstrip("\n").partition("\t")
            (alls[t] if kind == "all" else rans[t]).append(label)
    if len(alls) == len(TERMS):
        full = alls[TERMS[0]]
        if not full:
            problems.append("the full unit list is EMPTY")
        for t in TERMS[1:]:
            if alls[t] != full:
                problems.append("%s enumerated a different suite than %s" % (t, TERMS[0]))
        ran = [u for t in TERMS for u in rans[t]]
        twice = sorted({u for u in ran if ran.count(u) > 1})
        missed = sorted(set(full) - set(ran))
        extra = sorted(set(ran) - set(full))
        if twice:
            problems.append("run by two jobs: " + ", ".join(twice[:5]))
        if missed:
            problems.append("%d unit(s) run by NO job: %s" % (len(missed), ", ".join(missed[:5])))
        if extra:
            problems.append("run but not in the suite: " + ", ".join(extra[:5]))
        counts = ", ".join("%s %d" % (t, len(rans[t])) for t in TERMS)
        summary = "%d units in the suite; run: %s" % (len(full), counts)
    else:
        summary = "the partition could not be checked"
    print("## Evidence — three term types\n")
    print("| term type | verdict | time |\n|---|---|---|")
    print("\n".join(rows))
    print("\n" + summary)
    print("\n**%s**" % ("PASS" if not problems else "FAIL: " + "; ".join(problems)))
    return 1 if problems else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: evidence_ci.py DIR")
    sys.exit(main(sys.argv[1]))
