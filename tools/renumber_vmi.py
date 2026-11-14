#!/usr/bin/env python3
# ORIGINAL: LogicKernel tooling (D-0644 item 1); no swipl-devel counterpart.
# tools/renumber_vmi.py — derive every VM opcode number from the ORDER of `_CODE_TABLE` in src/pl-vmi.jl.
#
#   python3 -I tools/renumber_vmi.py            # write mode: renumber the constants and every text that quotes one
#   python3 -I tools/renumber_vmi.py --check    # no writes; exit 1 on ANY mismatch (the guard)
#   python3 -I tools/renumber_vmi.py --root DIR # a tree other than the repository this script lives in (tools/test_renumber_vmi.sh)
#
# THE RULE (audit D-0644 item 1): the order of `_CODE_TABLE` follows pl-vmi.c's VMI order at the pin (index 0 = the
# first row, `I_NOP`); the number of an opcode is its row index; this script derives the numbers and the check that
# `_CODE_TABLE` order == number stays the guard. A merge in the engine-core slot is therefore never resolved hunk by hunk
# on the numbers: the merged TABLE is put into pl-vmi.c's order (rows by hand), then this script runs over it.
#   * wip/ar1 renumbers A_* 164..188, I_RESET..I_SHIFTCP 189..193, TR4's S_TRIE_GEN..T_CHECKWAKEUP 194..221;
#   * wip/tb7m renumbers S_INCR_DYNAMIC 161, S_WRAP..I_SHIFTCP 162-169, TR4 170-197 (a draft for the TB6/TB7 side only).
#   Both cannot hold; the merge order is batch 3, then AR1, then TB5-TB7. The merge of the later branch (the TB5-TB7 branch
#   onto AR1's) and the merge of AR1 onto the TB5-TB7 branch both RUN this script over the merged table: they merge the
#   `const` lines and the table ROWS (the table in pl-vmi.c's order), the script writes the numbers.
#
# WHAT IT REWRITES (and only this):
#   1. src/pl-vmi.jl: every `const NAME = code(N)` -> N = the row index of NAME in `_CODE_TABLE`.
#   2. src/**/*.jl and test/**/*.jl: any other `NAME = code(N)` quoting an opcode name of the table (a fixture, a copy).
#   3. tools/mutants/*.py `old`/`new` texts: `NAME = code(N)` in an `old=` line becomes the derived number (an `old` text
#      must match the source); in the `new=` line that follows, the number keeps its OFFSET from the `old` number of the same
#      name (a mutant that writes code(162) for a constant that is code(161) writes derived+1 after the renumber). A `new`
#      with no `old` number to take the offset from is UNRESOLVED: reported, nonzero exit, never guessed.
# WHAT IT DOES NOT TOUCH: prose (docs/, comments, mutant ids that say "code 173"), counts derived from the table
# (`length(tail) == 41`, the boot-image foreign count): those are re-measured at the gate. It LISTS the lines of src/, test/,
# and tools/mutants/ (not docs/: its tables quote pl-vmi.c line numbers) that name an opcode next to a 3-digit number so a human reads them ("prose" lines, never an error).
#
# ERRORS (always nonzero, nothing written in write mode): a constant with no table row, a table row with no constant, a
# name declared twice (constant or row), two constants with one number (the collision a bad merge leaves), a constant line
# that is not `const NAME = code(N)`. --check also fails when a constant's number differs from its row index, or a quoted
# number in a scanned file differs from the derived one.
import os
import re
import sys

CONST_RE = re.compile(r"^const ([A-Z][A-Z0-9_]*) = code\((\d+)\)(\s*)$", re.M)
ROW_RE = re.compile(r"^\s*code_info\(:([A-Z][A-Z0-9_]*),", re.M)
QUOTE_RE = re.compile(r"\b([A-Z][A-Z0-9_]*)(\s*=\s*code\()(\d+)(\))")
OLD_RE = re.compile(r"^\s*old\s*=")
NEW_RE = re.compile(r"^\s*new\s*=")


def parse_vmi(text):
    consts = [(m.group(1), int(m.group(2))) for m in CONST_RE.finditer(text)]
    tbl = text.find("const _CODE_TABLE = (")
    if tbl < 0:
        return consts, None, ["no `const _CODE_TABLE = (` in pl-vmi.jl"]
    end = text.find("\n)\n", tbl)
    rows = [m.group(1) for m in ROW_RE.finditer(text[tbl:end if end > 0 else len(text)])]
    return consts, rows, []


def derive(text):
    """-> (number-of-name dict, errors)."""
    consts, rows, errs = parse_vmi(text)
    if rows is None:
        return {}, errs
    seen = {}
    for name, n in consts:
        if name in seen:
            errs.append("constant %s declared twice (code(%d) and code(%d))" % (name, seen[name], n))
        seen[name] = n
    seenr = set()
    for name in rows:
        if name in seenr:
            errs.append("_CODE_TABLE row %s declared twice" % name)
        seenr.add(name)
    for name in sorted(set(seen) - seenr):
        errs.append("constant %s has no _CODE_TABLE row" % name)
    for name in sorted(seenr - set(seen)):
        errs.append("_CODE_TABLE row %s has no constant" % name)
    bynum = {}
    for name, n in consts:
        bynum.setdefault(n, []).append(name)
    for n, names in sorted(bynum.items()):
        if len(names) > 1:
            errs.append("collision: code(%d) is declared by %s" % (n, ", ".join(names)))
    nconst_lines = len(re.findall(r"^const [A-Z][A-Z0-9_]* = code\(", text, re.M))
    if nconst_lines != len(consts):
        errs.append("%d `const NAME = code(...)` lines are not of the form `const NAME = code(N)`" % (nconst_lines - len(consts)))
    want = {name: i for i, name in enumerate(rows)}
    return want, errs


def rewrite_vmi(text, want):
    def sub(m):
        return "const %s = code(%d)%s" % (m.group(1), want[m.group(1)], m.group(3))
    return CONST_RE.sub(sub, text)


def rewrite_quotes(text, want, is_mutant_list, report):
    """Rewrite `NAME = code(N)` quotes; returns (new text, number of unresolved)."""
    unresolved = 0
    if not is_mutant_list:
        def sub(m):
            if m.group(1) not in want:
                return m.group(0)
            return "%s%s%d%s" % (m.group(1), m.group(2), want[m.group(1)], m.group(4))
        return QUOTE_RE.sub(sub, text), 0
    out = []
    pend = {}  # name -> old number quoted in the `old=` line (before the rewrite)
    for ln, line in enumerate(text.split("\n"), 1):
        if OLD_RE.match(line):
            pend = {}

            def sub_old(m):
                name = m.group(1)
                if name not in want:
                    return m.group(0)
                pend[name] = int(m.group(3))
                return "%s%s%d%s" % (name, m.group(2), want[name], m.group(4))
            line = QUOTE_RE.sub(sub_old, line)
        elif NEW_RE.match(line):
            def sub_new(m):
                nonlocal unresolved
                name = m.group(1)
                if name not in want:
                    return m.group(0)
                if name not in pend:
                    unresolved += 1
                    report("line %d: `new` quotes %s = code(%s) with no `old` number of %s to take the offset from" % (ln, name, m.group(3), name))
                    return m.group(0)
                return "%s%s%d%s" % (name, m.group(2), want[name] + (int(m.group(3)) - pend[name]), m.group(4))
            line = QUOTE_RE.sub(sub_new, line)
            pend = {}
        else:
            # a quote outside an old=/new= line (positional lists, comments): the derived number, as an `old`
            def sub_any(m):
                if m.group(1) not in want:
                    return m.group(0)
                return "%s%s%d%s" % (m.group(1), m.group(2), want[m.group(1)], m.group(4))
            line = QUOTE_RE.sub(sub_any, line)
        out.append(line)
    return "\n".join(out), unresolved


def scan_files(root):
    """-> list of (relative path, is_mutant_list) for the files a quote can live in (never pl-vmi.jl itself)."""
    found = []
    for sub in ("src", "test"):
        for d, _, fs in os.walk(os.path.join(root, sub)):
            for f in sorted(fs):
                if f.endswith(".jl"):
                    found.append((os.path.relpath(os.path.join(d, f), root), False))
    md = os.path.join(root, "tools", "mutants")
    if os.path.isdir(md):
        for f in sorted(os.listdir(md)):
            if f.endswith(".py"):
                found.append((os.path.join("tools", "mutants", f), True))
    return sorted(found)


def prose_lines(root, names):
    if not names:
        return []
    pat = re.compile(r"\b(" + "|".join(sorted(names, key=len, reverse=True)) + r")\b[^\n]{0,60}?(?<![:\-\d])\b(\d{3})\b")
    hits = []
    for sub in ("src", "test", "tools/mutants"):
        base = os.path.join(root, sub)
        for d, _, fs in os.walk(base):
            for f in sorted(fs):
                if not f.endswith((".jl", ".py", ".md")):
                    continue
                p = os.path.join(d, f)
                rel = os.path.relpath(p, root)
                if rel == os.path.join("src", "pl-vmi.jl"):
                    continue
                try:
                    lines = open(p, encoding="utf-8", errors="replace").read().split("\n")
                except OSError:
                    continue
                for i, line in enumerate(lines, 1):
                    m = pat.search(line)
                    if m and not QUOTE_RE.search(line):
                        hits.append("%s:%d: %s" % (rel, i, line.strip()[:110]))
    return hits


def main(argv):
    check = "--check" in argv
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if "--root" in argv:
        root = os.path.abspath(argv[argv.index("--root") + 1])
    vmi = os.path.join(root, "src", "pl-vmi.jl")
    text = open(vmi, encoding="utf-8").read()
    want, errs = derive(text)
    if errs:
        for e in errs:
            print("renumber_vmi: ERROR " + e)
        print("renumber_vmi: the table and the constants disagree; nothing written")
        return 1
    bad = 0
    consts, _, _ = parse_vmi(text)
    for name, n in consts:
        if want[name] != n:
            bad += 1
            if check:
                print("renumber_vmi: src/pl-vmi.jl: %s = code(%d), _CODE_TABLE order says %d" % (name, n, want[name]))
    newtext = rewrite_vmi(text, want)
    if not check and newtext != text:
        open(vmi, "w", encoding="utf-8").write(newtext)
    changed = ["src/pl-vmi.jl"] if newtext != text else []
    unresolved = 0
    for rel, is_ml in scan_files(root):
        p = os.path.join(root, rel)
        t = open(p, encoding="utf-8").read()
        if "code(" not in t:
            continue
        msgs = []
        nt, unr = rewrite_quotes(t, want, is_ml, msgs.append)
        for mm in msgs:
            print("renumber_vmi: UNRESOLVED %s %s" % (rel, mm))
        unresolved += unr
        if nt != t:
            changed.append(rel)
            if check:
                bad += 1
                print("renumber_vmi: %s quotes an opcode number the table does not give" % rel)
            else:
                open(p, "w", encoding="utf-8").write(nt)
    for line in prose_lines(root, set(want)):
        print("renumber_vmi: prose (read by a human): " + line)
    if check:
        print("renumber_vmi --check: %d opcodes, %d mismatches, %d unresolved" % (len(want), bad, unresolved))
        return 1 if (bad or unresolved) else 0
    print("renumber_vmi: %d opcodes; rewrote %d file(s)%s; %d unresolved" % (len(want), len(changed), (": " + ", ".join(changed)) if changed else "", unresolved))
    return 1 if unresolved else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
