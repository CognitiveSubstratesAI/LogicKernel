# ORIGINAL: the B1 mutant list for thread_statistics/3 — the port of pl-thread.c:7416-7459 (swipl-devel 18168e62); no swipl-devel counterpart.
# tools/mutants/B1.py — the mutation battery of `pl_thread_statistics` (src/pl-thread.jl:1472-1506) and of the 4-argument `pl_statistics_ld`'s `sld`
# use (src/pl-prims.jl:4421-4442), run ONCE, in CI (.github/workflows/mutation.yml; locally one mutant under debug is fine, no local list: D-0220).
# Format: tools/mutate_drive.py's (as GCSTUB1.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`; T3's
# `aimed_by` field repeats the `(aimed by ...)` of the id. Rows B1-1..B1-38 are the T3 candidates (evidence/B1/b1_t3_candidates.txt) reviewed by
# B1-2; B1-39..B1-41 are written by hand (the `sld` swaps T3 does not propose).
# KILL rows are rows of test/core_lang/test_b1_preds_swipl.jl: ts01-ts33 (main thread), te01-te16 (engines), rf01 (the refusal by name). The KILL lists are
# what the rows are EXPECTED to do (read, not run): the battery's verdict is the evidence. Written by a coding agent with NO Julia process.
# AIMED ROWS FOR THE `sld` SWAP (B1-2 added them, oracle-checked on the pin swipl 10.1.20): a type-only pin cannot tell the caller's ld from the
# target's, so the rows pin RELATIONS: te15 (an engine's `inferences` grow by what it ran: the swi_statistics path), te16 (an engine's `stacks` are
# below the caller's with a 100000-element list live: the qp_statistics list path), ts28/ts29 (the target's clock is refreshed: a later read after
# work is larger), ts30/ts31 (a LIST value for warnings/errors FAILS: the arm answers before qp_statistics), ts32/ts33 (warnings/errors are exactly 0).
# EQUIVALENT (declared, each with its code reason in the row): B1-11 (PL_error's arity is read only with a predicate name), B1-18 (programSpace is 0 for
# every ld), B1-28 and B1-29 (ThreadCPUTime(CPU_SYSTEM) is 0.0 over a field that starts at 0.0). If programSpace or the system clock ever get a real value,
# B1-18/28/29 become killable by te04/te03: re-open them then.
# DROPPED (T3 candidate, not killable by a row that agrees with swipl):
#   B1-12 (the `? FTRUE : FFALSE` of the permission_error branch, pl-thread.jl:1489): the branch needs a handle that passes get_thread (status >= RUNNING:
#     pl-thread.jl:830, pl-global.jl:180-181) with `thread_data == nothing` (cleared by pl-thread.jl:446 at the exit). swipl answers a destroyed or finished
#     engine with existence_error (te09, te10 pin it), so no swipl-agreeing row reaches it. If the first gate shows te09/te10 reaching it in the kernel,
#     get_thread must refuse the exited handle (an engine fix), and this row then dies by te09/te10.
# NOT REACHABLE BY A ROW, NOT A MUTANT: the 3-argument `pl_statistics_ld(ld, k, value)` wrapper passes `ld` itself (nothing to swap), and the swap
#   sld -> ld is an identity for statistics/2 (sld == ld), so the ~19 test files that call statistics/2 only for timing cannot kill it and are not listed.
# TARGETS (audit D-0238): the B1 file, and test/core_lang/test_gc_stats_swipl.jl (it reads the statistics keys through the same swi_statistics/qp_statistics
#   path). test/core_lang/test_thread_ops_swipl.jl and test_engines_swipl.jl were checked by grep: they exist but NEVER name statistics or thread_statistics
#   (0 hits), so they do not exercise the mutated code and are left out (the brief asked to add them if they did).
# MAY SURVIVE (the battery decides): B1-5 (the pending exception left after `tid == 0` falls through may be returned as the same failure).
P = "src/pl-thread.jl"
S = "src/pl-prims.jl"
T = [
    "test/core_lang/test_b1_preds_swipl.jl",
    "test/core_lang/test_gc_stats_swipl.jl",
]
TARGETS = T
MUTANTS = [
    dict(id="B1-1 bool L1476: `true` -> `false` (aimed by ts12, ts13, ts14)", file=P, targets=T,
         old="    ld::PL_local_data{T}, A1::term_t, A2::term_t, A3::term_t\n)::foreign_t where {T}\n    gd = _query_gd(ld)\n    tid = get_thread(gd, ld, A1, true)\n    tid == 0 && return FFALSE\n    info = _thread_info_of(gd, tid)",
         new="    ld::PL_local_data{T}, A1::term_t, A2::term_t, A3::term_t\n)::foreign_t where {T}\n    gd = _query_gd(ld)\n    tid = get_thread(gd, ld, A1, false)\n    tid == 0 && return FFALSE\n    info = _thread_info_of(gd, tid)", aimed_by="ts12, ts13, ts14"),
    dict(id="B1-2 cmp L1477: `==` -> `!=` (aimed by ts01, ts02, ts04)", file=P, targets=T,
         old="    gd = _query_gd(ld)\n    tid = get_thread(gd, ld, A1, true)\n    tid == 0 && return FFALSE\n    info = _thread_info_of(gd, tid)\n    tld = _thread_ld(ld, info)",
         new="    gd = _query_gd(ld)\n    tid = get_thread(gd, ld, A1, true)\n    tid != 0 && return FFALSE\n    info = _thread_info_of(gd, tid)\n    tld = _thread_ld(ld, info)", aimed_by="ts01, ts02, ts04"),
    dict(id="B1-3 logic L1477: `&&` -> `||` (aimed by ts01)", file=P, targets=T,
         old="    gd = _query_gd(ld)\n    tid = get_thread(gd, ld, A1, true)\n    tid == 0 && return FFALSE\n    info = _thread_info_of(gd, tid)\n    tld = _thread_ld(ld, info)",
         new="    gd = _query_gd(ld)\n    tid = get_thread(gd, ld, A1, true)\n    tid == 0 || return FFALSE\n    info = _thread_info_of(gd, tid)\n    tld = _thread_ld(ld, info)", aimed_by="ts01"),
    dict(id="B1-4 const L1477: `0` -> `1` (aimed by ts01, ts12)", file=P, targets=T,
         old="    gd = _query_gd(ld)\n    tid = get_thread(gd, ld, A1, true)\n    tid == 0 && return FFALSE\n    info = _thread_info_of(gd, tid)\n    tld = _thread_ld(ld, info)",
         new="    gd = _query_gd(ld)\n    tid = get_thread(gd, ld, A1, true)\n    tid == 1 && return FFALSE\n    info = _thread_info_of(gd, tid)\n    tld = _thread_ld(ld, info)", aimed_by="ts01, ts12"),
    dict(id="B1-5 stmt L1477: `tid == 0 && return FFALSE` -> `nothing` (aimed by ts12, ts13, ts14, ts15)", file=P, targets=T,
         old="    gd = _query_gd(ld)\n    tid = get_thread(gd, ld, A1, true)\n    tid == 0 && return FFALSE\n    info = _thread_info_of(gd, tid)\n    tld = _thread_ld(ld, info)",
         new="    gd = _query_gd(ld)\n    tid = get_thread(gd, ld, A1, true)\n    nothing\n    info = _thread_info_of(gd, tid)\n    tld = _thread_ld(ld, info)", aimed_by="ts12, ts13, ts14, ts15"),
    dict(id="B1-6 cond L1480: `tld === nothing` -> `true` (aimed by ts01)", file=P, targets=T,
         old="if tld === nothing",
         new="if true", aimed_by="ts01"),
    dict(id="B1-7 cond L1480: `tld === nothing` -> `false` (aimed by rf01)", file=P, targets=T,
         old="if tld === nothing",
         new="if false", aimed_by="rf01"),
    dict(id="B1-8 cmp L1480: `===` -> `!==` (aimed by ts01)", file=P, targets=T,
         old="if tld === nothing",
         new="if tld !== nothing", aimed_by="ts01"),
    dict(id="B1-9 cmp L1481: `===` -> `!==` (aimed by rf01)", file=P, targets=T,
         old="info === nothing && throw",
         new="info !== nothing && throw", aimed_by="rf01"),
    dict(id="B1-10 logic L1481: `&&` -> `||` (aimed by rf01)", file=P, targets=T,
         old="info === nothing && throw(",
         new="info === nothing || throw(", aimed_by="rf01"),
    dict(id="B1-11 const L1488: `0` -> `1` (aimed by none: EQUIVALENT)", file=P, targets=T,
         old="ld, \"\", 0, \"\", ERR_PERMISSION, mk_sym(T, :statistics",
         new="ld, \"\", 1, \"\", ERR_PERMISSION, mk_sym(T, :statistics", aimed_by="none: EQUIVALENT",
         equivalent="src/pl-error.jl:111: the `arity` argument of PL_error is read only inside `if !isempty(pred)` and this call passes pred = \"\" (the `0` is that arity), so no context term carries it"),
    dict(id="B1-13 cond L1493: `k !== nothing` -> `true` (aimed by ts09, ts10, ts11)", file=P, targets=T,
         old="k !== nothing",
         new="true", aimed_by="ts09, ts10, ts11"),
    dict(id="B1-14 cond L1493: `k !== nothing` -> `false` (aimed by ts28, ts29, ts30)", file=P, targets=T,
         old="k !== nothing",
         new="false", aimed_by="ts28, ts29, ts30"),
    dict(id="B1-15 cmp L1493: `!==` -> `===` (aimed by ts10, ts28)", file=P, targets=T,
         old="k !== nothing",
         new="k === nothing", aimed_by="ts10, ts28"),
    dict(id="B1-16 branch L1494: `_thr_is(k, :heapused)` -> `!_thr_is(k, :heapused)` (aimed by te15, te16, ts28)", file=P, targets=T,
         old="_thr_is(k, :heapused)",
         new="!_thr_is(k, :heapused)", aimed_by="te15, te16, ts28"),
    dict(id="B1-17 cond L1494: `_thr_is(k, :heapused)` -> `true` (aimed by ts28, ts29, te15, te16, ts30)", file=P, targets=T,
         old="_thr_is(k, :heapused)",
         new="true", aimed_by="ts28, ts29, te15, te16, ts30"),
    dict(id="B1-18 cond L1494: `_thr_is(k, :heapused)` -> `false` (aimed by none: EQUIVALENT)", file=P, targets=T,
         old="_thr_is(k, :heapused)",
         new="false", aimed_by="none: EQUIVALENT",
         equivalent="src/pl-prims.jl:4171: `programSpace(ld) = 0` for every local data, and `heapused` reads only programSpace (pl-prims.jl:4407, `program` at :4271), so the caller's and the target's ld give the same 0 (`false` leaves the heapused key on its target's ld)"),
    dict(id="B1-19 branch L1496: `_thr_is(k, :cputime) || _thr_is(k, :runtime)` -> `!(_thr_is(k, :cputime) || _thr_is(k, :run...` (aimed by ts28)", file=P, targets=T,
         old="_thr_is(k, :cputime) || _thr_is(k, :runtime)",
         new="!(_thr_is(k, :cputime) || _thr_is(k, :runtime))", aimed_by="ts28"),
    dict(id="B1-20 cond L1496: `_thr_is(k, :cputime) || _thr_is(k, :runtime)` -> `true` (aimed by ts30, ts31)", file=P, targets=T,
         old="_thr_is(k, :cputime) || _thr_is(k, :runtime)",
         new="true", aimed_by="ts30, ts31"),
    dict(id="B1-21 cond L1496: `_thr_is(k, :cputime) || _thr_is(k, :runtime)` -> `false` (aimed by ts28)", file=P, targets=T,
         old="_thr_is(k, :cputime) || _thr_is(k, :runtime)",
         new="false", aimed_by="ts28"),
    dict(id="B1-22 drop L1496: `_thr_is(k, :cputime) ||` -> `(removed)` (aimed by ts28)", file=P, targets=T,
         old="_thr_is(k, :cputime) || ",
         new="", aimed_by="ts28"),
    dict(id="B1-23 drop L1496: `|| _thr_is(k, :runtime)` -> `(removed)` (aimed by ts29)", file=P, targets=T,
         old=" || _thr_is(k, :runtime)",
         new="", aimed_by="ts29"),
    dict(id="B1-24 logic L1496: `||` -> `&&` (aimed by ts28, ts29)", file=P, targets=T,
         old="cputime) || _thr_is",
         new="cputime) && _thr_is", aimed_by="ts28, ts29"),
    dict(id="B1-25 stmt-assign L1497: `tld.statistics.user_cputime = ThreadCPUTi...` -> `nothing` (aimed by ts28, ts29)", file=P, targets=T,
         old="tld.statistics.user_cputime = ThreadCPUTime(CPU_USER)",
         new="nothing", aimed_by="ts28, ts29"),
    dict(id="B1-26 branch L1498: `_thr_is(k, :system_time)` -> `!_thr_is(k, :system_time)` (aimed by ts30, ts31)", file=P, targets=T,
         old="_thr_is(k, :system_time)",
         new="!_thr_is(k, :system_time)", aimed_by="ts30, ts31"),
    dict(id="B1-27 cond L1498: `_thr_is(k, :system_time)` -> `true` (aimed by ts30, ts31)", file=P, targets=T,
         old="_thr_is(k, :system_time)",
         new="true", aimed_by="ts30, ts31"),
    dict(id="B1-28 cond L1498: `_thr_is(k, :system_time)` -> `false` (aimed by none: EQUIVALENT)", file=P, targets=T,
         old="_thr_is(k, :system_time)",
         new="false", aimed_by="none: EQUIVALENT",
         equivalent="src/pl-thread.jl:109: ThreadCPUTime(CPU_SYSTEM) returns 0.0, and src/pl-global.jl:560 `ld_statistics()` starts system_cputime at 0.0: the refresh writes the value the field already holds"),
    dict(id="B1-29 stmt-assign L1499: `tld.statistics.system_cputime = ThreadCPU...` -> `nothing` (aimed by none: EQUIVALENT)", file=P, targets=T,
         old="tld.statistics.system_cputime = ThreadCPUTime(CPU_SYSTEM)",
         new="nothing", aimed_by="none: EQUIVALENT",
         equivalent="src/pl-thread.jl:109 and src/pl-global.jl:560: the assignment writes 0.0 over the 0.0 the field holds (statistics/2 writes the same value at src/pl-prims.jl:4474)"),
    dict(id="B1-30 branch L1500: `_thr_is(k, :warnings) || _thr_is(k, :errors)` -> `!(_thr_is(k, :warnings) || _thr_is(k, :er...` (aimed by ts08, ts22)", file=P, targets=T,
         old="_thr_is(k, :warnings) || _thr_is(k, :errors)",
         new="!(_thr_is(k, :warnings) || _thr_is(k, :errors))", aimed_by="ts08, ts22"),
    dict(id="B1-31 cond L1500: `_thr_is(k, :warnings) || _thr_is(k, :errors)` -> `true` (aimed by ts08, ts22)", file=P, targets=T,
         old="_thr_is(k, :warnings) || _thr_is(k, :errors)",
         new="true", aimed_by="ts08, ts22"),
    dict(id="B1-32 cond L1500: `_thr_is(k, :warnings) || _thr_is(k, :errors)` -> `false` (aimed by ts30, ts31)", file=P, targets=T,
         old="_thr_is(k, :warnings) || _thr_is(k, :errors)",
         new="false", aimed_by="ts30, ts31"),
    dict(id="B1-33 drop L1500: `_thr_is(k, :warnings) ||` -> `(removed)` (aimed by ts30)", file=P, targets=T,
         old="_thr_is(k, :warnings) || ",
         new="", aimed_by="ts30"),
    dict(id="B1-34 drop L1500: `|| _thr_is(k, :errors)` -> `(removed)` (aimed by ts31)", file=P, targets=T,
         old=" || _thr_is(k, :errors)",
         new="", aimed_by="ts31"),
    dict(id="B1-35 logic L1500: `||` -> `&&` (aimed by ts30, ts31)", file=P, targets=T,
         old="warnings) || _thr_is",
         new="warnings) && _thr_is", aimed_by="ts30, ts31"),
    dict(id="B1-36 const L1501: `0` -> `1` (aimed by ts32, ts33)", file=P, targets=T,
         old=", A3, 0) ? FTRUE",
         new=", A3, 1) ? FTRUE", aimed_by="ts32, ts33"),
    dict(id="B1-37 tern L1501: `FTRUE : FFALSE` -> `FFALSE : FTRUE` (aimed by ts06, ts07, ts32, ts33)", file=P, targets=T,
         old="0) ? FTRUE : FFALSE",
         new="0) ? FFALSE : FTRUE", aimed_by="ts06, ts07, ts32, ts33"),
    dict(id="B1-38 tern L1505: `FTRUE : FFALSE` -> `FFALSE : FTRUE` (aimed by ts01)", file=P, targets=T,
         old="tld) ? FTRUE : FFALSE",
         new="tld) ? FFALSE : FTRUE", aimed_by="ts01"),
    dict(id="B1-39 hand L4430 pl_statistics_ld: the swi_statistics form reads the CALLER's ld, not the target's `sld` (aimed by te15)", file=S, targets=T,
         old="swi_statistics(sld, key, result)",
         new="swi_statistics(ld, key, result)", aimed_by="te15"),
    dict(id="B1-40 hand L4436 pl_statistics_ld: the qp_statistics (list) form reads the CALLER's ld, not the target's `sld` (aimed by te16)", file=S, targets=T,
         old="qp_statistics(sld, key, v)",
         new="qp_statistics(ld, key, v)", aimed_by="te16"),
    dict(id="B1-41 hand L1505 pl_thread_statistics hands the CALLER's ld to pl_statistics_ld instead of the target's `tld` (aimed by te15, te16)", file=P, targets=T,
         old="return pl_statistics_ld(ld, A2, A3, tld) ? FTRUE : FFALSE",
         new="return pl_statistics_ld(ld, A2, A3, ld) ? FTRUE : FFALSE", aimed_by="te15, te16"),
]
