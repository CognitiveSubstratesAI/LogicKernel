#!/usr/bin/env python3
# ORIGINAL: the Pkg.test cost table (D-0091 item 3, 2026-10-22; A-0054 item 4) — no swipl-devel counterpart.
# What CI.yml's `pkgtest` gather prints as ONE annotation, `::notice title=unit-costs::file=seconds;…` (tools/
# evidence_ci.py write_tables: seconds per test file, all term types summed, measured UNDER Pkg.test WITH COVERAGE),
# turned into the table that balances the Pkg.test file groups: test/pkgtest_costs.tsv. test/unit_costs.tsv holds
# the costs measured in Evidence (no coverage); they are not Pkg.test's (A-0054: the `Julia 1` groups ran
# 1004 / 483 / 559 s on the Evidence-balanced split), so the `test` jobs balance by their own table:
# LOGICKERNEL_COSTS_TABLE=pkgtest_costs.tsv (CI.yml, `test` job env; test/ci_slices.jl `lk_costs_path`).
#
#   pkgtest_costs.py parse SRC [OUT] [--source TEXT]   SRC = a file holding the notice (the whole `::notice` line, or
#                                                      just its `file=seconds;…` message), or `-` for stdin
#   pkgtest_costs.py fetch RUN_ID [OUT] [--version V]  the notice of run RUN_ID's `Julia V - ubuntu-24.04` gather job
#                                                      (V = 1 by default; the job must have succeeded), read from
#                                                      GitHub WITHOUT a token: 2 API calls (60 an hour in all)
#   pkgtest_costs.py fetch --job ID [OUT] [--source TEXT]   the same for a job id already known: 1 call
#   pkgtest_costs.py balance TABLE [GROUPS] [--tests DIR]   the groups' loads under test/ci_slices.jl's assignment
#                                                      (longest-processing-time first, ties to the lower group),
#                                                      over TABLE's files or, with --tests, DIR's test_*.jl files
#
# OUT defaults to stdout. The table is validated before it is written: every entry `name.jl=seconds`, a finite
# non-negative number, no name twice, the static analysis in none (it runs in Evidence's shards, not in a group),
# at least one entry — a half-read annotation must not become a table the groups are balanced by.
# Exit 0 done, 1 an invalid notice or table, 2 unreadable (no network, an API error, a bad argument).
# LOGICKERNEL_GH_FIXTURE=<dir>: read <dir>/jobs.json and <dir>/annotations.json instead of the API
# (test/test_gate_split.jl). LOGICKERNEL_REPO=owner/name overrides the slug read from `origin`.
import json
import math
import os
import re
import subprocess
import sys
import urllib.request

SA_LABEL = "test_static_analysis.jl"
NOTICE = re.compile(r"^::notice title=([^:]*)::(.*)$", re.S)
HEADER = (
    "# test/pkgtest_costs.tsv — seconds per test file under Pkg.test WITH COVERAGE (CI.yml's `test` jobs), all term types\n"
    "# summed: the weights the Pkg.test file groups are balanced by (LOGICKERNEL_COSTS_TABLE=pkgtest_costs.tsv; test/\n"
    "# ci_slices.jl). test/unit_costs.tsv holds Evidence's costs (no coverage) and balances Evidence's groups; the two differ.\n"
    "# A file missing here counts as the median. Written by tools/pkgtest_costs.py from the pkgtest gather's `unit-costs`\n"
    "# notice when the groups drift apart; never hand-edited.\n"
)


class Invalid(Exception):
    pass


def parse_notice(text):
    """{file: seconds} from the notice: the whole `::notice title=unit-costs…::` line or its message alone."""
    text = text.strip()
    m = NOTICE.match(text)
    if m:
        if not m.group(1).startswith("unit-costs"):
            raise Invalid("the annotation's title is %r, not unit-costs" % m.group(1))
        text = m.group(2).strip()
    if not text:
        raise Invalid("the notice is empty")
    costs = {}
    for entry in text.split(";"):
        name, eq, secs = entry.strip().rpartition("=")
        if not eq or not name:
            raise Invalid("not a file=seconds entry: %r" % entry[:80])
        if not name.endswith(".jl"):
            raise Invalid("not a test file name: %r" % name[:80])
        if name.split("/")[-1] == SA_LABEL:
            raise Invalid("the static analysis is in no file group, its cost must not be in the table")
        try:
            v = float(secs)
        except ValueError:
            raise Invalid("%s: %r is not a number" % (name, secs[:40]))
        if not math.isfinite(v) or v < 0:
            raise Invalid("%s: %r is not a finite non-negative number of seconds" % (name, secs[:40]))
        if name in costs:
            raise Invalid("%s: listed twice" % name)
        costs[name] = v
    return costs


def table_text(costs, source):
    return HEADER + "# Measured: %s\n" % source + "".join("%s\t%.1f\n" % (f, costs[f]) for f in sorted(costs))


def read_table(path):
    """{file: seconds} from a `file<TAB>seconds` table, `#` lines skipped (test/ci_slices.jl lk_unit_costs)."""
    costs = {}
    for line in open(path):
        if not line.strip() or line.startswith("#"):
            continue
        f = line.rstrip("\n").split("\t")
        if len(f) != 2:
            raise Invalid("%s: not file<TAB>seconds: %r" % (path, line[:80]))
        try:
            costs[f[0]] = float(f[1])
        except ValueError:
            raise Invalid("%s: %r is not a number" % (path, f[1]))
    return costs


def lpt_groups(files, groups, costs):
    """test/ci_slices.jl lk_file_groups: {file: 1..groups}, the costliest first (then by name) into the group with
    the least load so far (the lowest on a tie); a file with no cost counts as the median (1.0 with none)."""
    known = sorted(costs[f] for f in files if f in costs)
    median = known[(len(known) + 1) // 2 - 1] if known else 1.0
    cost = lambda f: costs.get(f, median)
    load = [0.0] * groups
    out = {}
    for f in sorted(files, key=lambda f: (-cost(f), f)):
        k = load.index(min(load))
        out[f] = k + 1
        load[k] += cost(f)
    return out, load


def balance(table, groups, tests=None):
    costs = read_table(table)
    if tests:
        files = sorted(
            os.path.relpath(os.path.join(d, n), tests)
            for d, _, ns in os.walk(tests) for n in ns
            if n.startswith("test_") and n.endswith(".jl") and n != SA_LABEL)
        if not files:
            raise Invalid("%s holds no test_*.jl file" % tests)
    else:
        files = sorted(costs)
    _, load = lpt_groups(files, groups, costs)
    missing = [f for f in files if f not in costs]
    lines = ["%d files over %d groups (%d without a cost: counted as the median)" % (len(files), groups, len(missing))]
    lines += ["  group %d: %.1f s" % (k + 1, v) for k, v in enumerate(load)]
    lines.append("  spread: %.1f s (max %.1f, min %.1f), total %.1f s" % (max(load) - min(load), max(load), min(load), sum(load)))
    return "\n".join(lines)


def repo_slug():
    if os.environ.get("LOGICKERNEL_REPO"):
        return os.environ["LOGICKERNEL_REPO"]
    url = subprocess.run(["git", "remote", "get-url", "origin"], capture_output=True, text=True, cwd=os.path.dirname(os.path.abspath(__file__))).stdout.strip()
    m = re.search(r"github\.com[:/](.+?)(?:\.git)?$", url)
    if not m:
        raise OSError("no GitHub origin to read the runs of")
    return m.group(1)


def api(path, fixture):
    """The GitHub REST answer as JSON, anonymous (a public repository). Never prints a URL with a credential."""
    if os.environ.get("LOGICKERNEL_GH_FIXTURE"):
        return json.load(open(os.path.join(os.environ["LOGICKERNEL_GH_FIXTURE"], fixture)))
    req = urllib.request.Request("https://api.github.com/repos/%s/%s" % (repo_slug(), path),
                                 headers={"Accept": "application/vnd.github+json", "User-Agent": "lk-pkgtest-costs"})
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            return json.load(r)
    except Exception as e:  # network, rate limit (403), not found (404), bad JSON
        raise OSError("GitHub API %s: %s" % (path.split("?")[0], e))


def notice_of_job(job_id):
    anns = api("check-runs/%s/annotations?per_page=100" % job_id, "annotations.json")
    notes = [a for a in anns if (a.get("title") or "").startswith("unit-costs")]
    if len(notes) != 1:
        raise Invalid("job %s has %d unit-costs annotation(s), want exactly one" % (job_id, len(notes)))
    return notes[0]["message"]


def fetch_run(run_id, version):
    jobs = api("actions/runs/%s/jobs?per_page=100" % run_id, "jobs.json")["jobs"]
    want = "Julia %s - ubuntu-24.04" % version
    hit = [j for j in jobs if j["name"] == want]
    if len(hit) != 1:
        raise Invalid("run %s has %d job(s) named %r, want exactly one" % (run_id, len(hit), want))
    j = hit[0]
    if j.get("conclusion") != "success":
        raise Invalid("job %r of run %s: %s, not success — a failed gather's costs are not a measurement" % (want, run_id, j.get("conclusion")))
    return notice_of_job(j["id"]), "run %s (%s), %s, job %s" % (run_id, (j.get("head_sha") or "?")[:7], want, j["id"])


USAGE = ("usage: pkgtest_costs.py parse SRC [OUT] [--source TEXT] | fetch RUN_ID [OUT] [--version V] | "
         "fetch --job ID [OUT] [--source TEXT] | balance TABLE [GROUPS] [--tests DIR]")


def opts(args, names):
    """(positionals, {name: value}) for `--name value` options among `names`; anything else starting `--` is an error."""
    pos, got, i = [], {}, 0
    while i < len(args):
        if args[i].startswith("--") and len(args[i]) > 2 and args[i] != "--":
            if args[i][2:] not in names or i + 1 >= len(args):
                raise ValueError(args[i])
            got[args[i][2:]] = args[i + 1]
            i += 2
        else:
            pos.append(args[i])
            i += 1
    return pos, got


def emit(text, out):
    if out:
        open(out, "w").write(text)
        print("pkgtest_costs: wrote %s (%d entries)" % (out, text.count("\n") - HEADER.count("\n") - 1))
    else:
        sys.stdout.write(text)


def main(a):
    try:
        cmd, rest = a[0], a[1:]
        if cmd == "parse":
            pos, o = opts(rest, ("source",))
            if len(pos) not in (1, 2):
                raise ValueError("parse")
            text = sys.stdin.read() if pos[0] == "-" else open(pos[0]).read()
            emit(table_text(parse_notice(text), o.get("source", "notice read from %s" % pos[0])), pos[1] if len(pos) == 2 else None)
        elif cmd == "fetch":
            pos, o = opts(rest, ("version", "job", "source"))
            if "job" in o:
                if len(pos) > 1 or "version" in o:
                    raise ValueError("fetch --job")
                msg, src = notice_of_job(o["job"]), o.get("source", "job %s" % o["job"])
                out = pos[0] if pos else None
            else:
                if len(pos) not in (1, 2) or "source" in o:
                    raise ValueError("fetch")
                msg, src = fetch_run(pos[0], o.get("version", "1"))
                out = pos[1] if len(pos) == 2 else None
            emit(table_text(parse_notice(msg), src), out)
        elif cmd == "balance":
            pos, o = opts(rest, ("tests",))
            if len(pos) not in (1, 2):
                raise ValueError("balance")
            g = int(pos[1]) if len(pos) == 2 else 3
            if g < 1:
                raise ValueError("balance")
            print(balance(pos[0], g, o.get("tests")))
        else:
            raise ValueError(cmd)
    except Invalid as e:
        print("pkgtest_costs: %s" % e)
        return 1
    except OSError as e:
        print("pkgtest_costs: %s" % e)
        return 2
    except (ValueError, IndexError):
        print(USAGE)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
