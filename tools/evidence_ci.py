#!/usr/bin/env python3
# ORIGINAL: the evidence run's CI side (user, 2026-10-13; sharded, D-0059 2026-10-20) — no swipl-devel
# counterpart. The GATHER of a run spread over several jobs: what .github/workflows/evidence.yml's and
# CI.yml's gather jobs call. Three green jobs that skipped a unit are not green, and neither is a shard
# that analysed nothing — so every check here is on what the jobs WROTE, never on their count.
#
#   evidence_ci.py verdict DIR GROUPS SHARDS   the whole Evidence run: every term type × file group,
#                                              and the static analysis's shards (Verdict table)
#   evidence_ci.py term DIR TERM GROUPS        one term type's file groups (its job, `reference` …)
#   evidence_ci.py sa DIR SHARDS               the static analysis's shards alone
#   evidence_ci.py pkgtest DIR VERSION GROUPS  CI.yml's Pkg.test file groups of one Julia version
#
# DIR holds what the jobs uploaded (test/runtests.jl's LOGICKERNEL_UNITS_OUT; the static analysis's
# LOGICKERNEL_SA_COUNTS_OUT; each job's verdict row):
#   units_<job>.tsv  `slice<TAB>kind<TAB>k<TAB>n<TAB>term`, `all<TAB>label<TAB>impl` for every unit of
#                    the suite, `ran<TAB>label<TAB>passed<TAB>broken<TAB>seconds` for those it ran,
#                    `stats<TAB>plain<TAB>interned<TAB>shared` (the second type's compounds)
#   row_<job>.md     `| job | passed | N s |` or `| job | **FAILED** | — |`
#   sa_<k>.tsv       a static-analysis shard's counts (test/static_analysis_body.jl)
# with <job> = `<term>_g<k>` (Evidence), `sa_<k>` (a static-analysis shard), `julia-<version>_g<k>`.
# THE PARTITION: every job enumerated the same, non-empty suite; each unit but the static analysis
# was run by exactly one file-group job, of its own term type; the static analysis by every shard,
# whose counts SUM to the full ones (each shard's non-zero) with every one-off part run exactly once.
# Writes unit_counts.tsv (each unit's passes) and unit_costs.tsv (seconds per file, the replacement
# for test/unit_costs.tsv) into DIR. Exit 1 on any failure, with every problem named.
import os
import sys

TERMS = ("reference", "alt", "alt_interned")
SA_LABEL = "test_static_analysis.jl"


def read_units(d, job):
    path = os.path.join(d, "units_%s.tsv" % job)
    if not os.path.isfile(path):
        return None
    u = {"slice": None, "all": [], "impl": {}, "ran": [], "stats": None}
    for line in open(path):
        f = line.rstrip("\n").split("\t")
        if f[0] == "slice":
            u["slice"] = tuple(f[1:5]) if len(f) >= 5 else tuple(f[1:]) + ("",)
        elif f[0] == "all":
            u["all"].append(f[1])
            u["impl"][f[1]] = f[2] if len(f) > 2 else ""
        elif f[0] == "ran":
            u["ran"].append((f[1], int(f[2]), int(f[3]), float(f[4])))
        elif f[0] == "stats":
            u["stats"] = tuple(int(x) for x in f[1:4])
    return u


class Gather:
    def __init__(self, d):
        self.d, self.problems, self.rows, self.units = d, [], [], {}

    def job(self, job, kind, k, n, term):
        """One job's row and unit list, its slice as expected; the list kept for the partition."""
        row = os.path.join(self.d, "row_%s.md" % job)
        if os.path.isfile(row):
            text = open(row).read().strip()
            self.rows.append(text)
            if "passed" not in text:
                self.problems.append("%s: the job did not pass" % job)
        else:
            self.rows.append("| %s | **NO VERDICT** | — |" % job)
            self.problems.append("%s: no verdict row (the job died before writing one)" % job)
        u = read_units(self.d, job)
        if u is None:
            self.problems.append("%s: no unit list" % job)
            return None
        want = (kind, str(k), str(n), term)
        if u["slice"] != want:
            self.problems.append("%s: ran as slice %s, expected %s" % (job, u["slice"], want))
        self.units[job] = u
        return u

    def same_suite(self):
        """Every job enumerated the same suite; it is not empty. The full list, or None."""
        lists = list(self.units.values())
        if not lists:
            return None
        full = lists[0]["all"]
        if not full:
            self.problems.append("the full unit list is EMPTY")
            return None
        for job, u in self.units.items():
            if u["all"] != full:
                self.problems.append("%s enumerated a different suite" % job)
        return full

    def partition(self, jobs, expected, label):
        """`expected` (labels) run by exactly one of `jobs`, nothing else run by them."""
        ran = [r[0] for j in jobs if j in self.units for r in self.units[j]["ran"]]
        twice = sorted({x for x in ran if ran.count(x) > 1})
        missed = sorted(set(expected) - set(ran))
        extra = sorted(set(ran) - set(expected))
        if twice:
            self.problems.append("%s: run by two jobs: %s" % (label, ", ".join(twice[:5])))
        if missed:
            self.problems.append("%s: %d unit(s) run by NO job: %s" % (label, len(missed), ", ".join(missed[:5])))
        if extra:
            self.problems.append("%s: run but not its to run: %s" % (label, ", ".join(extra[:5])))
        return len(ran)

    def stats(self, jobs, term):
        """The second implementation's counts, summed over a term type's slices: its own non-zero."""
        got = [self.units[j]["stats"] for j in jobs if j in self.units]
        if not got or any(s is None for s in got):
            self.problems.append("%s: a slice wrote no AltTerm counts" % term)
            return
        plain, interned, shared = (sum(s[i] for s in got) for i in range(3))
        need = {"alt": [("plain", plain)], "alt_interned": [("interned", interned), ("shared", shared)],
                "": [("plain", plain), ("interned", interned), ("shared", shared)]}.get(term, [])
        for name, v in need:
            if v == 0:
                self.problems.append("%s: no %s compound built over its slices" % (term or "all types", name))

    def sa(self, shards):
        """The static analysis's shards: each ran the one unit, and their counts sum to the full ones."""
        parts_all, ran_parts, sums, totals = None, [], {"dispatch": 0, "alloc": 0}, {}
        for k in range(1, shards + 1):
            u = self.job("sa_%d" % k, "sa_shard", k, shards, "reference")
            if u is not None and [r[0] for r in u["ran"]] != [SA_LABEL]:
                self.problems.append("sa_%d: ran %s, not the static analysis alone" % (k, [r[0] for r in u["ran"]]))
            path = os.path.join(self.d, "sa_%d.tsv" % k)
            if not os.path.isfile(path):
                self.problems.append("sa_%d: no counts (the analysis did not run to its end)" % k)
                continue
            seen = {}
            for line in open(path):
                f = line.rstrip("\n").split("\t")
                if f[0] == "shard" and (f[1], f[2]) != (str(k), str(shards)):
                    self.problems.append("sa_%d: analysed as shard %s/%s" % (k, f[1], f[2]))
                elif f[0] == "parts":
                    seen["parts"] = f[1].split(",")
                elif f[0] == "part":
                    ran_parts.append(f[1])
                elif f[0] in sums:
                    seen[f[0]] = 1
                    ran, full = int(f[1]), int(f[2])
                    sums[f[0]] += ran
                    if ran == 0:
                        self.problems.append("sa_%d: %s analysed NOTHING" % (k, f[0]))
                    if totals.setdefault(f[0], full) != full:
                        self.problems.append("sa_%d: a different %s total (%d, not %d)" % (k, f[0], full, totals[f[0]]))
            for key in ("parts", "dispatch", "alloc"):
                if key not in seen:
                    self.problems.append("sa_%d: no %s line" % (k, key))
            if "parts" in seen:
                if parts_all is None:
                    parts_all = seen["parts"]
                elif seen["parts"] != parts_all:
                    self.problems.append("sa_%d: a different list of parts" % k)
        for key, full in totals.items():
            if sums[key] != full:
                self.problems.append("static analysis: %s entries analysed %d, the manifest has %d" % (key, sums[key], full))
        if not totals.get("dispatch") or not totals.get("alloc"):
            self.problems.append("static analysis: a full count is zero or missing")
        if parts_all:
            for p in parts_all:
                c = ran_parts.count(p)
                if c != 1:
                    self.problems.append("static analysis: part %s ran %d times" % (p, c))
            extra = sorted(set(ran_parts) - set(parts_all))
            if extra:
                self.problems.append("static analysis: unknown parts ran: %s" % ", ".join(extra))
        else:
            self.problems.append("static analysis: no shard listed the parts")
        return "static analysis: %d shards; dispatch %d of %s, AllocCheck %d of %s entries; %d parts" % (
            shards, sums["dispatch"], totals.get("dispatch", "?"), sums["alloc"], totals.get("alloc", "?"),
            len(ran_parts))

    def write_tables(self):
        counts, costs = [], {}
        for job in sorted(self.units):
            for label, np, nb, secs in self.units[job]["ran"]:
                counts.append("%s\t%s\t%d\t%d\t%.1f" % (job, label, np, nb, secs))
                f = label.split(" [")[0]
                if f != SA_LABEL:
                    costs[f] = costs.get(f, 0.0) + secs
        with open(os.path.join(self.d, "unit_counts.tsv"), "w") as io:
            io.write("job\tunit\tpassed\tbroken\tseconds\n" + "".join(c + "\n" for c in counts))
        with open(os.path.join(self.d, "unit_costs.tsv"), "w") as io:
            io.write("# test/unit_costs.tsv — seconds per test file, all term types summed: the weights CI's file groups\n"
                     "# are balanced by (test/ci_slices.jl). A file missing here counts as the median. Replace it with the\n"
                     "# Verdict table's `unit-costs` artifact (Evidence) when the groups drift apart; never hand-edited.\n")
            io.write("".join("%s\t%.1f\n" % (f, costs[f]) for f in sorted(costs)))
        return sum(int(c.split("\t")[2]) for c in counts)

    def report(self, title, summary):
        text = "\n".join([
            "## %s\n" % title, "| job | verdict | time |\n|---|---|---|", "\n".join(self.rows),
            "\n" + "\n\n".join(summary),
            "\n**%s**" % ("PASS" if not self.problems else "FAIL: " + "; ".join(self.problems))])
        print(text)
        # in CI: the job's summary, and an ANNOTATION — a public repository's annotations read
        # without a token, its logs and summaries not
        if os.environ.get("GITHUB_STEP_SUMMARY"):
            with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as io:
                io.write(text + "\n")
        if os.environ.get("GITHUB_ACTIONS") == "true":
            if self.problems:
                print("::error title=%s::FAIL: %s" % (title, "; ".join(self.problems)[:900]))
            print("::notice title=%s::%s" % (title, " ".join(summary).replace("\n", " ")[:900]))
        return 1 if self.problems else 0


def group_jobs(g, prefix, groups, term):
    jobs = ["%s_g%d" % (prefix, k) for k in range(1, groups + 1)]
    for k, job in enumerate(jobs, 1):
        g.job(job, "file_group", k, groups, term)
    return jobs


def expected_units(full, impl_of, term):
    """The units the file groups must run: all but the static analysis, of `term` (or every type)."""
    return [x for x in full if x != SA_LABEL and (not term or impl_of[x] == term)]


def verdict(d, groups, shards):
    g, summary = Gather(d), []
    jobs = {t: group_jobs(g, t, groups, t) for t in TERMS}
    summary.append(g.sa(shards))
    full = g.same_suite()
    if full is not None:
        impl_of = next(iter(g.units.values()))["impl"]
        n = 0
        for t in TERMS:
            n += g.partition(jobs[t], expected_units(full, impl_of, t), t)
            g.stats(jobs[t], t)
        if SA_LABEL not in full:
            g.problems.append("the suite has no %s" % SA_LABEL)
        npass = g.write_tables()
        summary.append("%d units in the suite: %d run by the file groups, the static analysis by its %d shards; "
                       "%d assertions passed (unit_counts.tsv)" % (len(full), n, shards, npass))
    return g.report("Evidence — %d term types × %d file groups, static analysis × %d" % (len(TERMS), groups, shards),
                    summary)


def term(d, t, groups):
    if t not in TERMS:
        sys.exit("evidence_ci: no term type %r" % t)
    g = Gather(d)
    jobs = group_jobs(g, t, groups, t)
    full = g.same_suite()
    summary = []
    if full is not None:
        impl_of = next(iter(g.units.values()))["impl"]
        n = g.partition(jobs, expected_units(full, impl_of, t), t)
        g.stats(jobs, t)
        summary.append("%s: %d units over %d file groups" % (t, n, groups))
    return g.report("%s — %d file groups" % (t, groups), summary)


def sa(d, shards):
    g = Gather(d)
    s = g.sa(shards)
    return g.report("Static analysis — %d shards" % shards, [s])


def pkgtest(d, version, groups):
    g = Gather(d)
    jobs = group_jobs(g, "julia-%s" % version, groups, "")
    full = g.same_suite()
    summary = []
    if full is not None:
        impl_of = next(iter(g.units.values()))["impl"]
        n = g.partition(jobs, expected_units(full, impl_of, ""), "julia-%s" % version)
        g.stats(jobs, "")
        g.write_tables()
        summary.append("Julia %s: %d units over %d file groups (the static analysis runs in Evidence's shards: "
                       "Pkg.test has no JET/Aqua/AllocCheck)" % (version, n, groups))
    return g.report("Julia %s — Pkg.test, %d file groups" % (version, groups), summary)


USAGE = "usage: evidence_ci.py verdict DIR GROUPS SHARDS | term DIR TERM GROUPS | sa DIR SHARDS | pkgtest DIR VERSION GROUPS"

if __name__ == "__main__":
    a = sys.argv[1:]
    try:
        if a[:1] == ["verdict"] and len(a) == 4:
            sys.exit(verdict(a[1], int(a[2]), int(a[3])))
        if a[:1] == ["term"] and len(a) == 4:
            sys.exit(term(a[1], a[2], int(a[3])))
        if a[:1] == ["sa"] and len(a) == 3:
            sys.exit(sa(a[1], int(a[2])))
        if a[:1] == ["pkgtest"] and len(a) == 4:
            sys.exit(pkgtest(a[1], a[2], int(a[3])))
    except ValueError:
        pass
    sys.exit(USAGE)
