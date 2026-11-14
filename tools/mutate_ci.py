#!/usr/bin/env python3
# ORIGINAL: the mutation battery's CI side (user, 2026-10-13) — no swipl-devel counterpart.
# tools/mutate_ci.py — what .github/workflows/mutation.yml calls. The LOCAL
# driver is tools/mutate_drive.py (a warm daemon, one mutant after another); here every mutant is a
# CI job of its own, so the three steps are separate commands. THE MUTANT LIST AND THE VERDICT RULES
# ARE THE SAME (see mutate_drive.py's header): `id`, `file`, `old` (must occur EXACTLY once), `new`,
# optional `expect: "hang"`, `equivalent: <reason>`, `targets`.
#
#   mutate_ci.py plan [--impls "A B…"] MUTANTS.py [ID…]   print `matrix=…`, `count=…` and `targets=…` (the
#                                                 list's own `TARGETS`, space-separated; empty when
#                                                 it names none) for $GITHUB_OUTPUT. With --impls also
#                                                 `pairs=` (mutants x impls), `impls=` and `impl_matrix=`
#   mutate_ci.py baseline [--impl A] LIMIT_S TARGET…   the targets on the unmutated tree → baseline[.A].json
#   mutate_ci.py one [--impl A] MUTANTS.py ID LIMIT_S TARGET…   apply ID, run the targets → <ID>[.A].json, .log
#   mutate_ci.py collect [--impls "A B…"] MUTANTS.py COUNT [ID…]   the verdict table (stdout, verdicts.md); exit 0/1
#   mutate_ci.py annotate                         verdicts.md as notice annotations (stdout): a check
#                                                 run's annotations are readable through the API
#                                                 without a token, its job summary and logs are not
#
# THE TERM-TYPE DIMENSION (MUT3; the standing closure rule: a mutant FAILS and the unmutated tree PASSES on
# ALL THREE term types, reference, alt, alt_interned). `--impl A` runs every target with LOGICKERNEL_TERM=A, the
# way tools/warm.sh `file <target> <impl>` does: test/term_under_test.jl reads that variable. warm.sh refuses
# a file that is not term-generic (it does not include ../term_under_test.jl) on another type, because it has ONE
# run, on the reference type: here such a target (and every `sh:` target: tools/mutate_suite.sh pins the reference
# type itself) is SKIPPED on a non-reference type, and a pair with no target left is "N/A (no term-generic
# target)" — not blocking, but named in the table. WITHOUT --impl everything is as before MUT3 (reference type,
# files <ID>.json and baseline.json); with it the files are <ID>.<impl>.json and baseline.<impl>.json.
# THE VERDICT of a MUTANT is the rule over its pairs: caught only if caught on EVERY type ("caught on: reference
# alt alt_interned"); one blocking pair blocks it ("SURVIVED on alt; caught on: reference alt_interned"); a
# declared `equivalent` must survive on every type; a baseline that is not green on a type makes that type's
# pairs NO VERDICT, which BLOCKS. A matrix is at most 256 jobs (GitHub): `plan` refuses a larger one by name.
#
# A TARGET is a test file, run in a FRESH process on the term type (`julia --project=. <file>`,
# LOGICKERNEL_TERM=<impl>, default reference) — or `sh:<command>`.
# THE VERDICT, from exit codes first: a target exits 1 = caught; every target exits 0 = SURVIVED; a
# target past LIMIT_S = TIMEOUT (never "caught", unless the mutant expects a hang); another code =
# INVALID. An exit 1 is caught only when a test failed — mutate_drive.py's `judge`, the one
# classifier of both drivers (D-0050): code that did not parse or load = NO VERDICT (does not load);
# a test file with no failing test line = NO VERDICT (no failing test). A mutant declared
# `equivalent` must SURVIVE ("EQUIVALENT (declared)"); caught, its claim was wrong ("EQUIVALENT
# REFUTED"). BLOCKING: SURVIVED, TIMEOUT, INVALID, BADMATCH, EQUIVALENT REFUTED, NO VERDICT (either
# kind, or a missing verdict file), a baseline that is not green. Every record keeps the deciding
# line (`first_failure`: a caught one's first failing test line); the table shows it.
import json
import os
import re
import runpy
import signal
import subprocess
import sys
import time

sys.dont_write_bytecode = True     # no tools/__pycache__: an untracked file voids the evidence marker
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mutate_drive import judge, noload_hint, run_targets as _run_targets  # noqa: E402 — one classifier, two drivers

OUT = "mutation-out"
BLOCKING = ("SURVIVED", "TIMEOUT", "INVALID", "BADMATCH", "EQUIVALENT REFUTED", "NO VERDICT")
IMPLS = ("reference", "alt", "alt_interned")        # test/runtests.jl LK_TERM_IMPLS; the default of the workflow
MATRIX_MAX = 256                                    # GitHub: jobs of ONE matrix
# warm.sh `_file`'s test for a term-generic file, line for line
GENERIC = re.compile(r'^include\(joinpath\(@__DIR__, "\.\.", "term_under_test\.jl"\)\)', re.M)
NA = "N/A (no term-generic target)"


def pin_julia():
    """The LOCAL Julia pin (audit D-0465, D-0466; tools/lib_julia.sh): put the Julia of tools/WARM_JULIA_VERSION first
    on PATH for every target, or exit 7 (not installed / another version / LOGICKERNEL_JULIA_PIN_OFF=1, which a
    mutation path never accepts). In CI (GITHUB_ACTIONS=true) setup-julia's own version runs: nothing to do."""
    if os.environ.get("GITHUB_ACTIONS") == "true":
        return
    sh = os.path.join(os.path.dirname(os.path.abspath(__file__)), "julia_pin.sh")
    r = subprocess.run([sh, "path", "gate"], capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        sys.exit(r.returncode)
    os.environ["PATH"] = r.stdout.strip()


def load(path, only):
    # CISTATUS (audit D-0262): the first argument is the mutant list as a PATH in the repository
    # (the workflow input `mutants`: tools/mutants/<step>.py), never a bare step name — three
    # dispatches of 2026-10-30 named `ARGVAR2` and died here with a bare FileNotFoundError.
    if not os.path.isfile(path):
        sys.exit("mutate_ci: no mutant list at %r — give the PATH of the step's list in the repository, "
                 "tools/mutants/<step>.py (e.g. tools/mutants/ARGVAR2.py), not a bare step name" % path)
    mutants = runpy.run_path(path)["MUTANTS"]
    names = [m["id"].split()[0] for m in mutants]
    if len(set(names)) != len(names):
        sys.exit("mutate_ci: two mutants share a name in %s" % path)
    unknown = set(only) - set(names)
    if unknown:
        sys.exit("mutate_ci: no such mutant: %s" % ", ".join(sorted(unknown)))
    return [m for m in mutants if not only or m["id"].split()[0] in only]


def take_opt(argv, flag):
    """(value or None, the rest of argv) for `flag VALUE` anywhere in argv; a flag without a value exits."""
    rest, val, i = [], None, 0
    while i < len(argv):
        if argv[i] == flag:
            if i + 1 >= len(argv):
                sys.exit("mutate_ci: %s needs a value" % flag)
            val = argv[i + 1]
            i += 2
        else:
            rest.append(argv[i])
            i += 1
    return val, rest


def parse_impls(text):
    """The term types of `text` (blank or comma separated), in order, each once; every one must be in IMPLS."""
    names = []
    for n in text.replace(",", " ").split():
        if n not in IMPLS:
            sys.exit("mutate_ci: unknown term type %r (one of %s)" % (n, ", ".join(IMPLS)))
        if n not in names:
            names.append(n)
    if not names:
        sys.exit("mutate_ci: no term type given (one or more of %s)" % ", ".join(IMPLS))
    return names


def expand(names, impls):
    """The matrix: every (mutant, impl) pair, mutant by mutant. `impls` None (no --impls) = the pre-MUT3 matrix,
    one pair per mutant with impl None."""
    return [(n, i) for n in names for i in (impls or [None])]


def check_matrix(npairs, nmutants, nimpls):
    if npairs > MATRIX_MAX:
        sys.exit("mutate_ci: plan: %d mutants x %d term types = %d jobs, over GitHub's limit of %d jobs per matrix: "
                 "split the list by `ids` (at most %d mutants per run on %d term types) — nothing is cut silently"
                 % (nmutants, nimpls, npairs, MATRIX_MAX, MATRIX_MAX // nimpls, nimpls))


def stem(name, impl):
    """The file stem of a record: <name> without a term type (pre-MUT3), else <name>.<impl>."""
    return name if impl is None else "%s.%s" % (name, impl)


def is_generic(target, root="."):
    """A target that has a run on every term type: a test file that includes ../term_under_test.jl (warm.sh `_file`)."""
    if target.startswith("sh:"):
        return False
    try:
        with open(os.path.join(root, target), encoding="utf-8", errors="replace") as f:
            return bool(GENERIC.search(f.read()))
    except OSError:
        return False


def targets_for(impl, targets, root="."):
    """(targets to run, targets skipped) on `impl`: the reference type (and no --impl) runs every target; another
    type runs the term-generic ones only (see the header)."""
    if impl in (None, "reference"):
        return list(targets), []
    return [t for t in targets if is_generic(t, root)], [t for t in targets if not is_generic(t, root)]


def run_target(target, limit, impl="reference"):
    """(exit code or "hang", output) of one target in a fresh process GROUP: past the limit the whole
    group is killed — a test's own children (swipl) hold the output pipe open otherwise, and the
    read would wait for them."""
    env = dict(os.environ, LOGICKERNEL_TERM=impl or "reference")
    cmd = ["julia", "--project=.", "--startup-file=no", target]
    if target.startswith("sh:"):
        cmd = ["bash", "-c", target[3:]]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                         env=env, start_new_session=True)
    try:
        out, _ = p.communicate(timeout=limit)
        return p.returncode, out
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        out, _ = p.communicate()
        return "hang", out


def run_targets(targets, limit, impl="reference"):
    """mutate_drive.py's `run_targets`, each target in a fresh process: (result, log, line)."""
    def run1(t):
        rc, out = run_target(t, limit, impl)
        return judge(t, rc, out, os.getcwd())[0], out
    return _run_targets(targets, run1, os.getcwd())


def write(name, record, log):
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + ".json"), "w") as f:
        json.dump(record, f)
    with open(os.path.join(OUT, name + ".log"), "w") as f:
        f.write(log)


def plan(argv):
    impls_text, argv = take_opt(argv, "--impls")
    impls = None if impls_text is None else parse_impls(impls_text)
    mutants = load(argv[0], argv[1:])
    if not mutants:
        sys.exit("mutate_ci: the plan is empty")
    pairs = expand([m["id"].split()[0] for m in mutants], impls)
    check_matrix(len(pairs), len(mutants), len(impls or [None]))
    if impls is None:
        matrix = {"include": [{"name": n} for n, _ in pairs]}
    else:
        matrix = {"include": [{"name": n, "impl": i, "job": "mutant %s · %s" % (n, i)} for n, i in pairs]}
    print("matrix=" + json.dumps(matrix))
    print("count=%d" % len(mutants))
    if impls is not None:
        print("pairs=%d" % len(pairs))
        print("impls=" + " ".join(impls))
        print("impl_matrix=" + json.dumps({"include": [{"impl": i, "job": "Baseline (unmutated) · %s" % i}
                                                       for i in impls]}))
    # the list's own targets: what a run started by a push (no inputs) uses
    targets = runpy.run_path(argv[0]).get("TARGETS", [])
    if any(" " in t or "\n" in t for t in targets):
        sys.exit("mutate_ci: a target of TARGETS holds a blank")
    print("targets=" + " ".join(targets))
    return 0


def baseline(argv):
    impl, argv = take_opt(argv, "--impl")
    if impl is not None:
        parse_impls(impl)
    limit, targets = int(argv[0]), argv[1:]
    if not targets:
        sys.exit("mutate_ci: no target")
    run, skipped = targets_for(impl, targets)
    t0 = time.time()
    if not run:                      # nothing term-generic to run on this type: green, and said so
        write(stem("baseline", impl), {"name": "baseline", "impl": impl, "exit": 0, "na": True, "seconds": 0,
                                       "skipped": skipped}, "no term-generic target on %s\n" % impl)
        print("baseline", impl, NA)
        return 0
    rc, log, _ = run_targets(run, limit, impl or "reference")
    write(stem("baseline", impl), {"name": "baseline", "impl": impl, "exit": rc, "seconds": round(time.time() - t0),
                                   "skipped": skipped}, log)
    print("baseline", impl or "", "exit", rc)
    return 0 if rc == 0 else 1


def verdict_of(rc, declared, expect=""):
    """A pair's verdict from the targets' result `rc` (run_targets) — the rules of the header."""
    if rc == "noload":
        return "NO VERDICT (does not load)"
    if rc == "notest":
        return "NO VERDICT (no failing test)"
    if rc == 1:
        return "EQUIVALENT REFUTED" if declared else "caught"
    if rc == "hang":
        return "caught (hang)" if expect == "hang" else "TIMEOUT"
    if rc == 0:
        return "EQUIVALENT (declared)" if declared else "SURVIVED"
    return "INVALID"


def one(argv):
    impl, argv = take_opt(argv, "--impl")
    if impl is not None:
        parse_impls(impl)
    path, name, limit, targets = argv[0], argv[1], int(argv[2]), argv[3:]
    (m,) = load(path, [name])
    targets = m.get("targets") or targets
    if not targets:
        sys.exit("mutate_ci: no target")
    run, skipped = targets_for(impl, targets)
    key = stem(name, impl)
    with open(m["file"]) as f:
        src = f.read()
    record = {"name": name, "id": m["id"], "impl": impl, "equivalent": m.get("equivalent", ""), "skipped": skipped}
    if src.count(m["old"]) != 1:
        record.update(verdict="BADMATCH", seconds=0,
                      note="`old` occurs %d times in %s" % (src.count(m["old"]), m["file"]))
        write(key, record, "")
        print(key, "BADMATCH")
        return 0
    if not run:
        record.update(verdict=NA, seconds=0, first_failure="")
        write(key, record, "skipped: %s\n" % " ".join(skipped))
        print(key, NA)
        return 0
    with open(m["file"], "w") as f:
        f.write(src.replace(m["old"], m["new"]))
    t0 = time.time()
    rc, log, why = run_targets(run, limit, impl or "reference")
    verdict = verdict_of(rc, bool(m.get("equivalent")), m.get("expect"))
    why = "; ".join(x for x in (why, noload_hint(m, verdict)) if x)
    record.update(verdict=verdict, exit=rc, seconds=round(time.time() - t0), first_failure=why)
    write(key, record, log)
    print(key, verdict, "—", why or "-")
    return 0                                            # the verdict is data: `collect` judges


def blocking(v):
    return v.startswith(BLOCKING)


def pair_verdict(record, base, impl):
    """One pair's verdict as `collect` states it: the mutant's record, or NO VERDICT when there is none or when
    the unmutated tree is not green on this term type (a guard is proved against a green baseline)."""
    if base is None or base.get("exit") != 0:
        return "NO VERDICT (baseline %s on %s)" % ("missing" if base is None else "red", impl or "reference")
    if record is None:
        return "NO VERDICT"
    return record["verdict"]


def aggregate(impls, vs):
    """(verdict, impls text, blocks) of ONE mutant from its pairs' verdicts `vs` {impl: verdict}, `impls` in order.
    Caught only if every pair that ran is caught; the verdict of a blocked mutant is its worst pair's (the first
    of BLOCKING's order, then the first impl); the text names every group: "SURVIVED on alt; caught on:
    reference alt_interned"."""
    groups = {}
    for i in impls:
        groups.setdefault(vs[i], []).append(i or "reference")           # impl None = no --impl: the reference type
    bad = [v for v in groups if blocking(v)]
    text = "; ".join(
        ["%s on %s" % (v, " ".join(groups[v])) for v in bad] +
        ["%s on: %s" % (v, " ".join(groups[v])) for v in groups if not blocking(v)])
    if bad:
        worst = min(bad, key=lambda v: (min(k for k, b in enumerate(BLOCKING) if v.startswith(b)), impls.index(groups[v][0])))
        return worst, text, True
    ran = [v for v in groups if v != NA]
    if not ran:
        return "NO VERDICT (no target ran)", text, True
    if any(v.startswith("EQUIVALENT") for v in ran):
        return "EQUIVALENT (declared)", text, False
    return ("caught" if len(ran) > 1 else ran[0]), text, False


def collect(argv):
    impls_text, argv = take_opt(argv, "--impls")
    impls = None if impls_text is None else parse_impls(impls_text)
    # an empty COUNT is a failed Plan step (its output `count` was never written): say so
    if not argv[1].strip().isdigit():
        sys.exit("mutate_ci: collect: COUNT is %r — the Plan step gave no mutant count (it failed, "
                 "see its log: usually a mutants input that is not tools/mutants/<step>.py)" % argv[1])
    path, count, only = argv[0], int(argv[1]), argv[2:]
    mutants = load(path, only)
    if len(mutants) != count:
        sys.exit("mutate_ci: the plan had %d mutants, the list now gives %d" % (count, len(mutants)))
    keys = impls or [None]
    rows, pairs, blocked = [], [], []

    def read(name):
        p = os.path.join(OUT, name + ".json")
        if not os.path.isfile(p):
            return None
        with open(p) as f:
            return json.load(f)

    bases = {i: read(stem("baseline", i)) for i in keys}
    ok = {i: bases[i] is not None and bases[i].get("exit") == 0 for i in keys}
    base_ok = all(ok.values())
    for m in mutants:
        name = m["id"].split()[0]
        recs = {i: read(stem(name, i)) for i in keys}
        vs = {i: pair_verdict(recs[i], bases[i], i) for i in keys}
        v, where, blocks = aggregate(keys, vs)
        if blocks:
            blocked.append(name)
        what = m["id"][len(name):].strip()
        if m.get("equivalent"):
            what += " — declared equivalent, pending audit: " + m["equivalent"]
        fails = [(i, (recs[i] or {}).get("first_failure") or "") for i in keys]
        fails = [(i, f) for i, f in fails if f]
        fail = "" if not fails else (fails[0][1] if impls is None else "[%s] %s" % fails[0])    # the first deciding line
        secs = max([(recs[i] or {}).get("seconds", 0) for i in keys])
        what, fail = what.replace("|", "\\|"), fail.replace("|", "\\|")
        if impls is None:
            rows.append("| %s | %s | %s s | %s | %s |" % (name, v, secs, what, fail))
        else:
            rows.append("| %s | %s | %s s | %s | %s | %s |" % (name, v, secs, where, what, fail))
            for i in impls:
                if vs[i] != "caught":
                    pairs.append("| %s | %s | %s | %s s | %s |" % (
                        name, i, vs[i], (recs[i] or {}).get("seconds", 0),
                        ((recs[i] or {}).get("first_failure") or "").replace("|", "\\|")))
    secs_all = [b.get("seconds", 0) for b in bases.values() if b is not None]
    lines = ["## Mutation battery — %s" % path, "",
             "Baseline (unmutated targets): **%s**%s" % (
                 "green" if base_ok else "NOT GREEN — no verdict below counts",
                 "" if not secs_all else ", %s s" % max(secs_all)), ""]
    if impls is not None:
        lines += ["Baseline per term type: " + "; ".join(
            "%s %s" % (i, "missing" if bases[i] is None else ("green" if ok[i] else "NOT GREEN")) for i in impls), ""]
        lines += ["| mutant | verdict | time | impls | what it breaks | first failing test line |",
                  "|---|---|---|---|---|---|"]
    else:
        lines += ["| mutant | verdict | time | what it breaks | first failing test line |", "|---|---|---|---|---|"]
    lines += rows + [""]
    n = len(mutants)
    lines.append("**%d of %d decided; blocking: %s**" % (
        n - len(blocked), n, ", ".join(blocked) if blocked else "none"))
    if pairs:
        lines += ["", "Pairs that are not caught (mutant x term type):", "",
                  "| mutant | impl | verdict | time | first failing test line |", "|---|---|---|---|---|"] + pairs
    text = "\n".join(lines) + "\n"
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "verdicts.md"), "w") as f:
        f.write(text)
    sys.stdout.write(text)
    return 1 if blocked or not base_ok else 0


ANNOTATIONS_MAX, ANNOTATION_CHARS = 10, 4000          # GitHub: 10 notices per step; a short message


def annotate(argv):
    """verdicts.md as `::notice` workflow commands, the rows packed in order into at most
    ANNOTATIONS_MAX messages of at most ANNOTATION_CHARS characters each, numbered "verdicts i/n";
    a row that does not fit is cut, and every annotation is printed — none dropped."""
    with open(os.path.join(OUT, "verdicts.md")) as f:
        rows = [ln[:ANNOTATION_CHARS] for ln in f.read().splitlines() if ln.strip()]
    parts, cur = [], ""
    for ln in rows:
        if cur and len(cur) + 1 + len(ln) > ANNOTATION_CHARS:
            parts.append(cur)
            cur = ""
        cur = ln if not cur else cur + "\n" + ln
    parts.append(cur)
    if len(parts) > ANNOTATIONS_MAX:
        print("mutate_ci: annotate: %d parts, GitHub shows %d" % (len(parts), ANNOTATIONS_MAX), file=sys.stderr)
    esc = lambda t: t.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    for i, part in enumerate(parts, 1):
        print("::notice title=verdicts %d/%d::%s" % (i, len(parts), esc(part)))
    return 0 if len(parts) <= ANNOTATIONS_MAX else 1


if __name__ == "__main__":
    commands = {"plan": plan, "baseline": baseline, "one": one, "collect": collect, "annotate": annotate}
    if len(sys.argv) < 2 or sys.argv[1] not in commands:
        sys.exit("usage: mutate_ci.py plan|baseline|one|collect|annotate … (see the header)")
    if sys.argv[1] in ("baseline", "one"):      # the commands that start a Julia
        pin_julia()
    sys.exit(commands[sys.argv[1]](sys.argv[2:]))
