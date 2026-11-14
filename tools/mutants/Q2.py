# ORIGINAL: Q2's mutant list — no swipl-devel counterpart.
# tools/mutants/Q2.py — the mutation battery of Q2 (audit D-0710 item 3): the TRACE_ME flag of every procedure as pl-proc.c resetProcedure and pl-ext.c
# registerBuiltins give it (a name that does not start with `$` has it, in any module; PL_FA_NOTRACE and '$hide'/1 clear it; the system-mode
# compile sets HIDE_CHILDS), read by pl-trace.c isDebugFrame (prolog_frame_attribute(F, hidden, H)) and '$get_predicate_attribute'(P, trace, V). The
# format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. Written UNTESTED
# (nothing compiled): each `old` was checked to occur once in its file by a python count (no Julia).
# TARGETS (audit D-0238): the DBG1 rows (t61-t78 read the flag), the files that read frames with prolog_frame_attribute/3, test_procedures.jl (a new
# procedure's flags; resetProcedure!), test_source_file_swipl.jl (HIDE_CHILDS of a predicate the system mode defines).
# NOT LISTED: a mutant of registerBuiltins!'s `defflags` or of the `$` test of `lookupProcedure` that changes the flags of the SYSTEM module's
# built-ins trips registerBuiltins!'s `@assert def.flags == defflags` (upstream's `assert(def->flags == defflags)`) while the booted template is built, so
# the package does not load: that is the guard working (Q2-M5 is the one such mutant, kept as the regression of the removed module condition, its
# prediction a build failure and not a row).
TD = ["test/core_lang/test_dbg1_swipl.jl"]
TW = TD + ["test/core_lang/test_wrap_swipl.jl", "test/core_lang/test_autoload_trap.jl", "test/db/test_procedures.jl"]
TARGETS = TW   # the baseline's (mutate_ci.py plan reads TARGETS)
PRC = "src/pl-proc.jl"
EXT = "src/pl-ext.jl"
TRC = "src/pl-trace.jl"
CMP = "src/pl-comp.jl"


def m(id, old, new, targets=TW, equivalent=None, file=PRC):
    d = dict(id=id, file=file, old=old, new=new, targets=targets)
    if equivalent is not None:
        d["equivalent"] = equivalent
    return d


MUTANTS = [
    m("Q2-M1 builtin_pred_flags ignores PL_FA_NOTRACE: trace/0, notrace/0, tracing/0 keep TRACE_ME (KILL t76: the attribute reads 1, swipl 0)",
      "    (regflags & PL_FA_NOTRACE) != 0 && (flags &= ~TRACE_ME)\n", "", file=EXT),
    m("Q2-M2 resetProcedure! never sets TRACE_ME (KILL test_procedures: a reset predicate named without `$` has SPY_ME only)",
      "    userpred && (flags |= TRACE_ME)                     # if ( userpred ) flags |= TRACE_ME\n", ""),
    m("Q2-M3 resetProcedure! keeps TRACE_ME of a `$` name (KILL test_procedures: the reset `$` predicate keeps TRACE_ME)",
      "    flags = def.flags & (SPY_ME | P_DIRTYREG)           # flags0", "    flags = def.flags & (SPY_ME | P_DIRTYREG | TRACE_ME)  # flags0"),
    m("Q2-M4 setAttrDefinition never clears an attribute: '$hide'/1 leaves TRACE_ME (KILL t77: notrace/1 and user:exception/3 read 1; t78: q2h's frame is visible, its attribute 1)",
      "    if val\n        def.flags |= attr\n    else\n        def.flags &= ~attr\n    end\n    return true\nend",
      "    if val\n        def.flags |= attr\n    end\n    return true\nend"),
    m("Q2-M5 lookupProcedure gives TRACE_ME in a user module only (the module condition D-0710 item 3 removes): BUILD FAILURE, registerBuiltins!'s assertion trips on the first system built-in (every target red)",
      "    userpred = sym_first_byte(name) != 0x24                     # resetProcedure:",
      "    userpred = (m.flags & M_SYSTEM) == 0 && sym_first_byte(name) != 0x24 # resetProcedure:"),
    m("Q2-M6 lookupProcedure gives TRACE_ME to a `$` name outside the system modules (KILL t73: the `$` user predicate's frame reads hidden=false, swipl true; test_procedures)",
      "    userpred = sym_first_byte(name) != 0x24                     # resetProcedure:",
      "    userpred = sym_first_byte(name) != 0x24 || (m.flags & M_SYSTEM) == 0   # resetProcedure:"),
    m("Q2-M7 isDebugFrame: a system predicate under a user predicate (no last call) is hidden like one under a system predicate (KILL t72: catch/3's frame reads hidden=true, swipl false)",
      "            return ((pf.predicate::Definition{T}).flags & HIDE_CHILDS) == 0     # user calls system / system calls system",
      "            return false     # user calls system / system calls system", file=TRC),
    m("Q2-M8 the system-mode compile sets P_LOCKED but not HIDE_CHILDS: a predicate boot/*.pl defines is a user predicate to isDebugFrame (KILL t61: catch/3's frame reads hidden=false, swipl true; t65: `$bags:findall_loop/4`)",
      "                    (def.flags & P_LOCKED) == 0 && (def.flags |= HIDE_CHILDS | P_LOCKED)",
      "                    (def.flags & P_LOCKED) == 0 && (def.flags |= P_LOCKED)",
      targets=TW + ["test/db/test_source_file_swipl.jl"], file=CMP),
]
