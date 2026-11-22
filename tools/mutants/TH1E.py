# ORIGINAL: the TH1 engines mutant list — no swipl-devel counterpart.
# tools/mutants/TH1E.py — the mutation battery of the ENGINES of TH1 (pl-thread.c at 18168e62, src/pl-thread.jl: get_interactor,
# aliasThread!, destroy_interactor!, done_interactor!, engine_create/destroy/post/fetch/next, interactor_post_answer and its nolock
# part; src/os/pl-option.jl: the OPT_SIZE/OPT_INF branch), run ONCE, in CI (.github/workflows/mutation.yml; locally one mutant under
# debug is fine, no local list: D-0220). Format: tools/mutate_drive.py's (as EV1d.py): `id`, `file`, `old` (must occur EXACTLY once),
# `new`, optional `equivalent` and `targets`. (tools/mutants/TH1A.py is wip/th1a's, the event table: not this file.)
# Killed by test/core_lang/test_engines_swipl.jl (rows named in each id's KILL); the KILL lists are what the rows are EXPECTED to do
# (read, not run): the battery's verdict is the evidence. Written by a coding agent with NO Julia process: every `old` was checked to
# occur exactly once with a throwaway `python3 -I` script (a text count); RE-FIT any that `tools/warm.sh fmt` rewrapped.
# TARGETS (audit D-0238): the engine predicates and their helpers are called by test_engines_swipl.jl ONLY (the other files that name
# thread_self reach the main thread's `unify_thread_id` branch, which no mutant here touches).
# EQUIVALENT (declared, with the code reason): TH1E-E6b (the self test of engine_destroy: the engine that destroys itself is always
# `running`, so `th.running` alone raises: src/pl-thread.jl `pl_engine_destroy`), TH1E-E12b (the close of the query in destroy_interactor!:
# the engine's local data is dropped with `th.info = nothing` and nothing reads the closed or open query afterwards).
# NOT LISTED (with the reason; a survivor would prove nothing about dead code, D-0238):
#   * the `rc == YIELD_ENGINE_YIELD` branch and the default (unknown code) branch of interactor_post_answer_nolock: no query returns a
#     yield code until the VM yield lands (its own engine-core step); the yield rows (yl1, yl2) wait for it.
#   * `th.interactor_thread` / `thread_symbol` and `info.has_tid`: written, never read, until thread_property/2 reports them.
#   * `copy_debug_mode`: only a caller in debug or trace mode changes anything, and no row switches them (the debug step's).
#   * the TH_IS_INTERACTOR test of get_interactor: every handle that exists is an engine (no other thread records).
TARGETS = ["test/core_lang/test_engines_swipl.jl"]
T = "src/pl-thread.jl"
O = "src/os/pl-option.jl"
MUTANTS = [
    # ---- get_interactor
    dict(id="TH1E-E1 a handle with no engine and no NOMORE/DONE flag is still an engine (KILL en04, en06, en18)",
         file=T, targets=TARGETS,
         old="                if th.info !== nothing ||\n",
         new="                if true ||\n"),
    dict(id="TH1E-E1b an alias is never looked up in the thread table (KILL en50, en52, en19)",
         file=T, targets=TARGETS,
         old="                if serial != 0\n                    symbol = gd.thread.handles[serial].symbol::T",
         new="                if false\n                    symbol = gd.thread.handles[serial].symbol::T"),
    # ---- the answer: last answer, end, exception
    dict(id="TH1E-E2 the last answer does not set NOMORE: the next engine_next raises instead of failing (KILL en01, en02, en09, en15, en24)",
         file=T, targets=TARGETS,
         old="        done_interactor!(gd, th)\n        th.flags |= TH_INTERACTOR_NOMORE\n",
         new="        done_interactor!(gd, th)\n"),
    dict(id="TH1E-E2b the engine_next that finds NOMORE does not clear it (KILL en24)",
         file=T, targets=TARGETS,
         old="            th.flags &= ~TH_INTERACTOR_NOMORE\n            th.flags |= TH_INTERACTOR_DONE\n",
         new="            th.flags |= TH_INTERACTOR_DONE\n"),
    dict(id="TH1E-E2c the engine_next that finds NOMORE does not set DONE: the handle stops being an engine (KILL en24)",
         file=T, targets=TARGETS,
         old="            th.flags &= ~TH_INTERACTOR_NOMORE\n            th.flags |= TH_INTERACTOR_DONE\n",
         new="            th.flags &= ~TH_INTERACTOR_NOMORE\n"),
    dict(id="TH1E-E3 a failed engine is not finished: no done_interactor! (KILL the white-box row en32: engines_finished, h.info)",
         file=T, targets=TARGETS,
         old="    elseif rc == PL_S_FALSE\n        PL_close_query(eld, q)\n        th.interactor_query = 0\n        done_interactor!(gd, th)\n",
         new="    elseif rc == PL_S_FALSE\n        PL_close_query(eld, q)\n        th.interactor_query = 0\n"),
    dict(id="TH1E-E3b a failed engine keeps its query: the next engine_next resumes a closed query (KILL en33)",
         file=T, targets=TARGETS,
         old="    elseif rc == PL_S_FALSE\n        PL_close_query(eld, q)\n        th.interactor_query = 0\n",
         new="    elseif rc == PL_S_FALSE\n        PL_close_query(eld, q)\n"),
    dict(id="TH1E-E4 the engine's exception is not raised in the caller (KILL en30, en31)",
         file=T, targets=TARGETS,
         old="        ok = ex != 0 && PL_recorded(ld, er, ex) && PL_raise_exception(ld, ex)\n",
         new="        ok = ex != 0 && PL_recorded(ld, er, ex)\n"),
    dict(id="TH1E-E4b an engine that raised is not finished: no done_interactor! (KILL the white-box row en30)",
         file=T, targets=TARGETS,
         old="        er = PL_record(eld, PL_exception(eld, q))\n        PL_close_query(eld, q)\n        th.interactor_query = 0\n        done_interactor!(gd, th)\n",
         new="        er = PL_record(eld, PL_exception(eld, q))\n        PL_close_query(eld, q)\n        th.interactor_query = 0\n"),
    dict(id="TH1E-E7a a solution is answered with the goal's cell, not the template's (KILL en01, en14, en20, en21, en22)",
         file=T, targets=TARGETS,
         old="    if rc == PL_S_TRUE\n        r = PL_record(eld, th.interactor_argv)\n",
         new="    if rc == PL_S_TRUE\n        r = PL_record(eld, th.interactor_argv + 1)\n"),
    dict(id="TH1E-E7b the last solution is answered with the goal's cell, not the template's (KILL en01, en08, en09)",
         file=T, targets=TARGETS,
         old="    elseif rc == PL_S_LAST\n        r = PL_record(eld, th.interactor_argv)\n",
         new="    elseif rc == PL_S_LAST\n        r = PL_record(eld, th.interactor_argv + 1)\n"),
    dict(id="TH1E-E7c the answer is not unified with the caller's term (KILL every row that reads an answer: en01, en08, en20)",
         file=T, targets=TARGETS,
         old="    ok = t != 0 && PL_recorded(ld, r::record{T}, t) && PL_unify(ld, term, t)\n",
         new="    ok = t != 0 && PL_recorded(ld, r::record{T}, t)\n"),
    # ---- the running engine (the named DIVERGES of TH1)
    dict(id="TH1E-E12 an engine that is running can be resumed: no permission_error(resume) (KILL dv1)",
         file=T, targets=TARGETS,
         old="    if th.running                                   # DIVERGES (TH1): upstream hangs on the mutex\n",
         new="    if false                                   # DIVERGES (TH1): upstream hangs on the mutex\n"),
    dict(id="TH1E-E13 the running flag is not cleared when the engine returns: the next engine_next is refused (KILL en01, en08, en22)",
         file=T, targets=TARGETS,
         old="    finally\n        th.running = false\n    end\n",
         new="    finally\n        th.running = th.running\n    end\n"),
    # ---- engine_post
    dict(id="TH1E-E5 engine_post/2 accepts a second package (KILL en10)",
         file=T, targets=TARGETS,
         old="    if th.interactor_package === nothing && !th.running\n",
         new="    if !th.running\n"),
    dict(id="TH1E-E5b engine_post/3 accepts a package while one is pending (KILL en17)",
         file=T, targets=TARGETS,
         old="    if package !== nothing && th.interactor_package !== nothing\n        return PL_error(\n",
         new="    if false\n        return PL_error(\n"),
    dict(id="TH1E-E5c engine_post/2 to a running engine is accepted (KILL dv2)",
         file=T, targets=TARGETS,
         old="    if th.interactor_package === nothing && !th.running\n        th.interactor_package = PL_record(ld, A2)\n",
         new="    if th.interactor_package === nothing\n        th.interactor_package = PL_record(ld, A2)\n"),
    dict(id="TH1E-E5d engine_post/3 does not record the package: the engine fetches nothing (KILL en08, en09, en11)",
         file=T, targets=TARGETS,
         old="        th.interactor_package = PL_record(ld, package)\n",
         new="        nothing\n"),
    # ---- engine_fetch
    dict(id="TH1E-E9 the package is not erased after engine_fetch: a second fetch succeeds (KILL en16)",
         file=T, targets=TARGETS,
         old="            th.interactor_package = nothing         # PL_erase(th->interactor.package)\n",
         new="            nothing         # PL_erase(th->interactor.package)\n"),
    dict(id="TH1E-E9b engine_fetch with nothing delivered fails instead of raising existence_error (KILL en12, en13)",
         file=T, targets=TARGETS,
         old="    exv = PL_new_term_refs(ld, 2)\n    return (\n        exv != 0 && PL_unify_atom(ld, exv, mk_sym(T, :delivery)) &&\n",
         new="    exv = PL_new_term_refs(ld, 2)\n    return (\n        false && PL_unify_atom(ld, exv, mk_sym(T, :delivery)) &&\n"),
    # ---- engine_destroy and its helpers
    dict(id="TH1E-E6 an engine that is running (not the caller itself) can be destroyed (KILL dv3)",
         file=T, targets=TARGETS,
         old="    if (th.info !== nothing && th.info === ld.thread_info) || th.running\n",
         new="    if (th.info !== nothing && th.info === ld.thread_info)\n"),
    dict(id="TH1E-E6b engine_destroy of the calling engine itself is not tested separately (the running flag alone raises)",
         file=T, targets=TARGETS, equivalent="the engine that calls engine_destroy on itself is running (th.running is set around PL_next_solution), so `th.running` alone raises: src/pl-thread.jl pl_engine_destroy",
         old="    if (th.info !== nothing && th.info === ld.thread_info) || th.running\n",
         new="    if th.running\n"),
    dict(id="TH1E-E14 destroy_interactor! does not clear NOMORE/DONE: a destroyed engine stays an engine (KILL en18)",
         file=T, targets=TARGETS,
         old="    th.flags &= ~(TH_INTERACTOR_NOMORE | TH_INTERACTOR_DONE)\n    unalias_thread!(gd, th)\n",
         new="    unalias_thread!(gd, th)\n"),
    dict(id="TH1E-E8 an alias is not registered in the thread table (KILL en50, en51, en52)",
         file=T, targets=TARGETS,
         old="    gd.thread.thread_table[sym_key(name)] = th.serial     # addNewHTable(threadTable, name, info->symbol)\n",
         new="    nothing\n"),
    dict(id="TH1E-E15 destroy_interactor! does not remove the alias: the name stays taken (KILL en19)",
         file=T, targets=TARGETS,
         old="    th.flags &= ~(TH_INTERACTOR_NOMORE | TH_INTERACTOR_DONE)\n    unalias_thread!(gd, th)\n",
         new="    th.flags &= ~(TH_INTERACTOR_NOMORE | TH_INTERACTOR_DONE)\n"),
    dict(id="TH1E-E16 an alias already taken is not refused (KILL en51)",
         file=T, targets=TARGETS,
         old="    if haskey(gd.thread.thread_table, sym_key(name))\n",
         new="    if false\n"),
    dict(id="TH1E-E12b destroy_interactor! does not close the engine's open query (equivalent)",
         file=T, targets=TARGETS, equivalent="the engine's local data is dropped with `th.info = nothing` right after (src/pl-thread.jl destroy_interactor!), nothing reads the open query afterwards",
         old="        PL_close_query(eld, th.interactor_query)\n        th.interactor_query = 0\n    end\n    if th.info !== nothing\n        _destroy_engine!(gd, th)\n",
         new="        th.interactor_query = 0\n    end\n    if th.info !== nothing\n        _destroy_engine!(gd, th)\n"),
    dict(id="TH1E-E17 a destroyed engine is not counted as finished (KILL the white-box row en01 / en32)",
         file=T, targets=TARGETS,
         old="    _destroy_engine!(gd, th)\n    gd.thread.engines_finished += 1\n    return nothing\n",
         new="    _destroy_engine!(gd, th)\n    return nothing\n"),
    dict(id="TH1E-E18 an engine is not counted as created (KILL the white-box rows)",
         file=T, targets=TARGETS,
         old="    gd.thread.engines_created += 1\n",
         new="    nothing\n"),
    # ---- the options of $engine_create/3
    dict(id="TH1E-E19 stack_limit(inf) is not recognised: PL_get_size_ex(inf) raises (KILL en55)",
         file=O, targets=TARGETS,
         old="(spec.type & OPT_INF) != 0 && PL_is_inf(ld, val)",
         new="false && PL_is_inf(ld, val)"),
]
