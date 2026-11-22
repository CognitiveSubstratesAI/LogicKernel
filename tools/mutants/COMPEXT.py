# ORIGINAL: COMP-EXT's mutant list ('$notrace'/1, '$predefine_foreign'/1, '$vmi_property'/2, '$spy'/1, '$nospy'/1); its counterpart is the port itself.
# tools/mutants/COMPEXT.py — the mutation battery of COMP-EXT (audit D-0784): src/pl-pro.jl `pl_notrace1_va`, src/pl-comp.jl
# `pl_predefine_foreign1_va`, `lookup_vmi`, `pl_vmi_property2_va`, src/pl-trace.jl `pl_spy`, `pl_nospy`, src/pl-proc.jl `get_procedure_find`'s
# GP_EXISTENCE_ERROR. Run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run).
# Format: tools/mutate_drive.py's (as NOTRACE2.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, `targets`.
# Every mutant is "aimed by <rows>": the rows of test/core_lang/test_compext_swipl.jl (cx01-cx64, the white-box testsets) that should fail. Verdicts: written by the battery, not yet run.
# NOT LISTED (each with its reason):
#   * `GP_NAMEARITY | GP_DEFINE` of `pl_predefine_foreign1_va`: the kernel's `get_procedure` takes a head as well (the DIVERGES of the header);
#     the rows are Name/Arity only, so the flag cannot be told apart by a row.
#   * NP-N4 (no PL_Q_NODEBUG) IS listed, but its kill is cx07's and cx12's reading of the debugging bit INSIDE the goal, which is the kernel's
#     PL_open_query behaviour: a survivor there is a finding on PL_open_query's NODEBUG handling, not an equivalent.
# TARGETS (audit D-0238): the rows file, the two predicates' older rows (test_notrace_swipl.jl runs `'$notrace'/2` and the debugger status
# that `'$notrace'/1` shares; test_bootpred3_swipl.jl the booted print_message/2 that the spy messages go through), test_debug_flag_swipl.jl
# (debug mode, which `'$spy'/1` switches on) and test/db/test_nth_clause_swipl.jl (pl-comp.c's registration table and lookups).
TS = [
    "test/core_lang/test_compext_swipl.jl",
    "test/core_lang/test_notrace_swipl.jl",
    "test/core_lang/test_bootpred3_swipl.jl",
    "test/core_lang/test_debug_flag_swipl.jl",
    "test/db/test_nth_clause_swipl.jl",
]
TARGETS = TS
PRO = "src/pl-pro.jl"
COMP = "src/pl-comp.jl"
TRACE = "src/pl-trace.jl"
PROC = "src/pl-proc.jl"
MUTANTS = [
    # ── '$notrace'/1 ──
    dict(id="NP-N1 the skip level is not restored after the goal (KILL cx08, cx09, cx10)",
         file=PRO, targets=TS,
         old="PL_Q_NODEBUG, ex)\n\n    ld.debugstatus_skiplevel = skipSave\n",
         new="PL_Q_NODEBUG, ex)\n\n    nothing\n"),
    dict(id="NP-N2 the tracing bit is not restored after the goal (KILL cx06, cx09, cx10)",
         file=PRO, targets=TS,
         old="    ld.debugstatus_tracing = traceSave\n",
         new="    nothing\n"),
    dict(id="NP-N3 a ball of the goal is swallowed: the call fails (KILL cx04, cx05, cx10)",
         file=PRO, targets=TS,
         old="    if !rval && ex[] != 0\n        return PL_raise_exception(ld, ex[]) ? FTRUE : FFALSE\n    end\n\n    return rval ? FTRUE : FFALSE\nend\n\n# PORT: pl-pro.c restoretrace",
         new="    return rval ? FTRUE : FFALSE\nend\n\n# PORT: pl-pro.c restoretrace"),
    dict(id="NP-N4 the goal is called without PL_Q_NODEBUG (KILL cx07, cx12)",
         file=PRO, targets=TS,
         old="    rval = callProlog(_query_gd(ld), ld, 0, A1, PL_Q_CATCH_EXCEPTION | PL_Q_NODEBUG, ex)\n",
         new="    rval = callProlog(_query_gd(ld), ld, 0, A1, PL_Q_CATCH_EXCEPTION, ex)\n"),
    dict(id="NP-N5 a failing goal succeeds (KILL cx02, cx09)",
         file=PRO, targets=TS,
         old="    end\n\n    return rval ? FTRUE : FFALSE\nend\n\n# PORT: pl-pro.c restoretrace",
         new="    end\n\n    return FTRUE\nend\n\n# PORT: pl-pro.c restoretrace"),
    # ── '$predefine_foreign'/1 ──
    dict(id="PF-1 P_FOREIGN is not set (KILL cx14, cx15, cx20, cx21 and the P_FOREIGN white-box checks)",
         file=COMP, targets=TS,
         old="    proc.definition.flags |= P_FOREIGN\n    return FTRUE\nend",
         new="    nothing\n    return FTRUE\nend"),
    dict(id="PF-2 an unknown procedure answers true without the flag path: a refused descriptor succeeds (KILL cx16, cx17, cx18, cx19)",
         file=COMP, targets=TS,
         old="    proc === nothing && return FFALSE\n    proc.definition.flags |= P_FOREIGN",
         new="    proc === nothing && return FTRUE\n    proc.definition.flags |= P_FOREIGN"),
    # ── lookup_vmi ──
    dict(id="VM-1 the VMI names are matched as the table spells them, upper-case (KILL cx22-cx39, cx48: the lower-case name is not found)",
         file=COMP, targets=TS,
         old="Symbol(lowercase(String(ci.name)))",
         new="Symbol(String(ci.name))"),
    dict(id="VM-2 the walk ends at the first instruction: only the first declared name is found (KILL cx22, cx24, cx29)",
         file=COMP, targets=TS,
         old="        sym_key(mk_sym(T, Symbol(lowercase(String(ci.name))))) == k && return ci\n    end\n    return nothing\n",
         new="        sym_key(mk_sym(T, Symbol(lowercase(String(ci.name))))) == k && return ci\n        break\n    end\n    return nothing\n"),
    # ── '$vmi_property'/2 ──
    dict(id="VM-3 break(B) is inverted (KILL cx22, cx25, cx26, cx28, cx30, cx39, cx40)",
         file=COMP, targets=TS,
         old="(ci.flags & VIF_BREAK) != 0) ? FTRUE : FFALSE",
         new="(ci.flags & VIF_BREAK) == 0) ? FTRUE : FFALSE"),
    dict(id="VM-4 argv names are taken one operand kind too far (KILL cx24, cx27, cx29, cx31-cx38)",
         file=COMP, targets=TS,
         old="mk_sym(T, _CA1_NAMES[Int(at)])",
         new="mk_sym(T, _CA1_NAMES[Int(at) + 1])"),
    dict(id="VM-5 the argv list is left open at its end (KILL cx23, cx24, cx27)",
         file=COMP, targets=TS,
         old="            return PL_unify_nil(ld, tail) ? FTRUE : FFALSE\n        else\n",
         new="            return FTRUE\n        else\n"),
    dict(id="VM-6 an unknown property is a type error, not a domain error (KILL cx42)",
         file=COMP, targets=TS,
         old="PL_error(ld, ERR_DOMAIN, mk_sym(T, :vmi_property), A2)",
         new="PL_error(ld, ERR_TYPE, mk_sym(T, :vmi_property), A2)"),
    dict(id="VM-7 a property that is no Name(Arg) is a domain error, not a type error (KILL cx43)",
         file=COMP, targets=TS,
         old="    PL_error(ld, ERR_TYPE, mk_sym(T, :vmi_property), A2)            # PL_type_error(\"vmi_property\", A2)\n",
         new="    PL_error(ld, ERR_DOMAIN, mk_sym(T, :vmi_property), A2)            # PL_type_error(\"vmi_property\", A2)\n"),
    dict(id="VM-8 the existence error names the property, not the instruction (KILL cx45, cx48, cx49, cx50)",
         file=COMP, targets=TS,
         old="PL_error(ld, ERR_EXISTENCE, mk_sym(T, :vmi), A1)",
         new="PL_error(ld, ERR_EXISTENCE, mk_sym(T, :vmi), A2)"),
    dict(id="VM-9 the property must have arity 2, not 1 (KILL cx22-cx39: nothing answers)",
         file=COMP, targets=TS,
         old="if na !== nothing && na[2] == 1\n        prop = na[1]",
         new="if na !== nothing && na[2] == 2\n        prop = na[1]"),
    # ── '$spy'/1 ──
    dict(id="SP-1 the spy point is not set (KILL cx51, cx64 and the message white box)",
         file=TRACE, targets=TS,
         old="def.flags |= SPY_ME",
         new="nothing"),
    dict(id="SP-2 `$spy` prints no message (KILL cx51, cx52, cx63, cx64, the message white box)",
         file=TRACE, targets=TS,
         old="            printMessage(ld, :informational, _message_term(ld, :spy, p)) || return FFALSE\n",
         new="            nothing\n"),
    dict(id="SP-3 `$spy` reports a point already set again (KILL cx52, the message white box)",
         file=TRACE, targets=TS,
         old="(def.flags & SPY_ME) == 0",
         new="true"),
    dict(id="SP-4 `$spy` does not switch the debug mode on (KILL cx51)",
         file=TRACE, targets=TS,
         old="return debugmode(ld, true, nothing, DBG_ALL) ? FTRUE : FFALSE",
         new="return FTRUE"),
    dict(id="SP-5 the spy message is named nospy (KILL cx51, cx52, cx63, cx64, the message white box)",
         file=TRACE, targets=TS,
         old="_message_term(ld, :spy, p)",
         new="_message_term(ld, :nospy, p)"),
    # ── '$nospy'/1 ──
    dict(id="SP-6 the spy point is not cleared (KILL cx51, cx64 and the SPY_ME white-box checks)",
         file=TRACE, targets=TS,
         old="def.flags &= ~SPY_ME",
         new="nothing"),
    dict(id="SP-7 `$nospy` prints no message (KILL cx51, cx52, cx63, cx64, the message white box)",
         file=TRACE, targets=TS,
         old="            return printMessage(ld, :informational, _message_term(ld, :nospy, p)) ? FTRUE : FFALSE\n",
         new="            return FTRUE\n"),
    dict(id="SP-8 the nospy message is named spy (KILL cx51, cx52, cx63, cx64, the message white box)",
         file=TRACE, targets=TS,
         old="_message_term(ld, :nospy, p)",
         new="_message_term(ld, :spy, p)"),
    dict(id="SP-9 `$nospy` reports a predicate that has no spy point (KILL cx52, cx53, the t_idle message white box)",
         file=TRACE, targets=TS,
         old="(def.flags & SPY_ME) != 0",
         new="true"),
    dict(id="SP-10 `$nospy` of an unknown predicate fails instead of raising (KILL cx54, cx55, cx56)",
         file=TRACE, targets=TS,
         old="get_procedure_find(gd, ld, p, GP_FIND | GP_EXISTENCE_ERROR)",
         new="get_procedure_find(gd, ld, p, GP_FIND)"),
    # ── get_procedure_find's GP_EXISTENCE_ERROR ──
    dict(id="GF-1 GP_EXISTENCE_ERROR raises nothing (KILL cx54, cx55, cx56)",
         file=PROC, targets=TS,
         old="    if p === nothing && (how & GP_EXISTENCE_ERROR) != 0\n        PL_error(ld, ERR_EXISTENCE, mk_sym(T, :procedure), descr)   # notfound: ERR_EXISTENCE, ATOM_procedure, descr\n",
         new="    if false\n        PL_error(ld, ERR_EXISTENCE, mk_sym(T, :procedure), descr)   # notfound: ERR_EXISTENCE, ATOM_procedure, descr\n"),
    dict(id="GF-2 the existence error names the stripped head, not the descriptor given (KILL cx56: m9:nosuch(_) loses its qualifier)",
         file=PROC, targets=TS,
         old="PL_error(ld, ERR_EXISTENCE, mk_sym(T, :procedure), descr)   # notfound: ERR_EXISTENCE, ATOM_procedure, descr",
         new="PL_error(ld, ERR_EXISTENCE, mk_sym(T, :procedure), head)   # notfound: ERR_EXISTENCE, ATOM_procedure, descr"),
]
