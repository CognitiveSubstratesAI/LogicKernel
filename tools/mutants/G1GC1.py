# ORIGINAL: G1GC1's mutant list; the code is a port of pl-gc.c (statistics, scheduler, blockGC) plus the kernel's own stack checker (no swipl-devel counterpart).
# tools/mutants/G1GC1.py -- the mutation battery of G1-GC piece 1: the stack checker of src/pl-gc.jl (`_check_global_word!`, `_check_global_cells!`,
# `_check_ref_chains!`, `_check_vbox!`, `_check_trail!`, `_check_attvar_chain!`, `_check_local_records!`, `stack_violations`, `check_stacks!`,
# `PL_check_stacks`), the G1-1 statistics and scheduler (`gc_percentage`, the ring index helpers, `gc_stat_aggregate!`, `gc_stat_start!`, `gc_stat_end!`,
# `last_gc_stats`, `gc_avg`, `unify_gc_reason`, `unify_gc_stats`, `pl_dgc_statistics5_va`, `considerGarbageCollect`, `call_tune_gc_hook`, `blockGC`/`unblockGC`,
# the virtual-signal bits) and the wiring of the keys of statistics/2 and `qp_statistics` in src/pl-prims.jl. NOTHING was run when this list was drafted: the
# kills below are read off the rows, the CI battery is the verdict. Run ONCE, in CI (.github/workflows/mutation.yml). Format: tools/mutate_drive.py's:
# `id`, `file`, `old` (EXACTLY once), `new`, `targets`, optional `equivalent`.
# Each id names its KILL: CK = test/core_lang/test_gc_checker.jl (the corruption rows: one testset per check name), GS = test/core_lang/test_gc_stats_swipl.jl
# (the white-box G1-1 rows and the `$gc_statistics` rows), SYS = test/core_lang/test_sys_swipl.jl (the statistics keys read through statistics/2:
# runtime, garbage_collection, stack_shifts, its t2/t6/t25/t26 rows).
# TARGETS (audit D-0238): the checker is reached by test_gc_checker.jl only (git grep of stack_violations/check_stacks! over test/); the G1-1 functions run in
# GS (its own rows) and, through the wiring of src/pl-prims.jl, also in SYS; test_arg/at/colon_body, test_cont_run, test_bootpred3 and test_tabling_state read
# inferences/localused/errors/warnings/table_space_used only, which this step did not touch.
# NOT MUTATED (they survive by design, no row can see them): the `state[p] == 0x02` shortcut of `_check_ref_chains!` (speed only), the `r.cells` counters (the
# `n >= gTop` row is too weak to kill them), the stack code test `!= TRAIL_GLOBAL`, `c.unlinked`, the fliframe/query/lTop/aTop rows of `_check_local_records!`
# (no corruption row), the attributed-variable chain branches other than the range test.
# Every `old` was counted EXACTLY once in its file by oldscan (python3 -I) at the tip of wip/g1gc-1 when this file was written (no Julia ran); `new` != `old`; no
# duplicate id. RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
CK = "test/core_lang/test_gc_checker.jl"
GS = "test/core_lang/test_gc_stats_swipl.jl"
SYS = "test/core_lang/test_sys_swipl.jl"
TARGETS = [CK, GS, SYS]                      # the union of every mutant's targets (mutate_ci.py plan reads TARGETS)
F = "src/pl-gc.jl"
P = "src/pl-prims.jl"
TC = [CK]
TG = [GS]
TW = [GS, SYS]


def m(id, old, new, targets, file=F, eq=None):
    d = dict(id=id, file=file, old=old, new=new, targets=targets)
    if eq:
        d["equivalent"] = eq
    return d


MUTANTS = [
    # ---- the checker (CK)
    m("G1GC1-K1", "        allow_marks || _viol!(", "        true || _viol!(", TC),                                   # arg-cell MARK row
    m("G1GC1-K2", "(w0 & BOTH_MASK) != 0 && !allow_marks &&", "false && !allow_marks &&", TC),   # functor-cell MARK row
    m("G1GC1-K3", "function check_stacks!(ld::PL_local_data; allow_marks::Bool=false)::Int\n    r = _check_stacks(ld, allow_marks)",
      "function check_stacks!(ld::PL_local_data; allow_marks::Bool=false)::Int\n    r = _check_stacks(ld, false)", TC),
    m("G1GC1-K4", "function stack_violations(ld::PL_local_data; allow_marks::Bool=false)::Vector{String}\n    r = _check_stacks(ld, allow_marks)",
      "function stack_violations(ld::PL_local_data; allow_marks::Bool=false)::Vector{String}\n    r = _check_stacks(ld, false)", TC),
    m("G1GC1-K5", "    elseif te == (TAG_REFERENCE | STG_GLOBAL)\n        q = valPtr(w)\n        if q < 1 || q > gtop",
      "    elseif te == (TAG_REFERENCE | STG_GLOBAL)\n        q = valPtr(w)\n        if q < 0 || q > gtop", TC),
    m("G1GC1-K6", "    elseif te == (TAG_REFERENCE | STG_GLOBAL)\n        q = valPtr(w)\n        if q < 1 || q > gtop",
      "    elseif te == (TAG_REFERENCE | STG_GLOBAL)\n        q = valPtr(w)\n        if q < 1", TC),
    m("G1GC1-K7", "    elseif te == (TAG_COMPOUND | STG_GLOBAL)\n        q = valPtr(w)\n        if q < 1 || q > gtop",
      "    elseif te == (TAG_COMPOUND | STG_GLOBAL)\n        q = valPtr(w)\n        if q < 1", TC),
    m("G1GC1-K8", "            if !isFunctor(f & ~BOTH_MASK)", "            if false", TC),
    m("G1GC1-K9", "        if i < 1 || i > length(ld.vtable)", "        if i < 1", TC),
    m("G1GC1-K10", "    if gtop < 0 || gtop > length(ld.gstack)\n        _viol!(r, \"gstack-top\"", "    if gtop < 0\n        _viol!(r, \"gstack-top\"", TC),
    m("G1GC1-K11", "            elseif p + n > gtop", "            elseif false", TC),
    m("G1GC1-K12", "            if state[p] == 0x01", "            if state[p] == 0x07", TC),
    m("G1GC1-K13", "            if q == p ", "            if false ", TC),
    m("G1GC1-K14", "    if length(ld.vbox) != nv", "    if false", TC),
    m("G1GC1-K15", "        if got != want", "        if false", TC),
    m("G1GC1-K16", "        if b <= prev", "        if false", TC),
    m("G1GC1-K17", "            p = _trail_pos(e)\n            if p < 1 || p > gtop", "            p = _trail_pos(e)\n            if p < 1", TC),
    m("G1GC1-K18", "            if p < 1 || p > gtop\n                _viol!(\n                    r,\n                    \"trail\",\n                    string(\n                        \"trail[\",\n                        i,\n                        \"] = \",\n                        _hexw(e),\n                        \": saved value at \"",
      "            if p < 1\n                _viol!(\n                    r,\n                    \"trail\",\n                    string(\n                        \"trail[\",\n                        i,\n                        \"] = \",\n                        _hexw(e),\n                        \": saved value at \"", TC),
    m("G1GC1-K19", "            if i == 1 || isTrailVal(tr[i - 1])", "            if false", TC),
    m("G1GC1-K20", "            elseif i > 1 && !isTrailVal(tr[i - 1]) && p <= _trail_pos(tr[i - 1])", "            elseif false", TC),
    m("G1GC1-K21", "        if p < 1 || p > gtop\n            _viol!(r, \"attvar-chain\"", "        if p < 1\n            _viol!(r, \"attvar-chain\"", TC),
    m("G1GC1-K22", "if c.mark.globaltop < 0 || c.mark.globaltop > gtop", "if c.mark.globaltop < 0", TC),
    m("G1GC1-K23", "if c.mark.trailtop < 0 || c.mark.trailtop > ntr", "if c.mark.trailtop < 0", TC),
    m("G1GC1-K24", "        throw(StackInvariantError(r.msgs))", "        return -1", TC),
    m("G1GC1-K25", "function PL_check_stacks(ld::PL_local_data)::Bool\n    return false", "function PL_check_stacks(ld::PL_local_data)::Bool\n    return true", TC),

    # ---- G1-1: the ring, the aggregate, the start and end of a collection (GS)
    m("G1GC1-S1", "stat.gc_time / (stat.gc_time + stat.prolog_time)", "stat.gc_time / stat.prolog_time", TG),
    m("G1GC1-S2", "i + 1 == GC_STAT_WINDOW_SIZE ? 0 : i + 1", "i + 1 == GC_STAT_WINDOW_SIZE + 1 ? 0 : i + 1", TG),
    m("G1GC1-S3", "i > 0 ? i - 1 : GC_STAT_WINDOW_SIZE - 1", "i > 0 ? i - 1 : GC_STAT_WINDOW_SIZE - 2", TG),
    m("G1GC1-S4", "this.global_before = gb ÷ GC_STAT_WINDOW_SIZE", "this.global_before = gb", TG),
    m("G1GC1-S5", "this.reason = rs ", "this.reason = rs ÷ GC_STAT_WINDOW_SIZE ", TG),
    m("G1GC1-S6", "this.gc_time = gt / GC_STAT_WINDOW_SIZE", "this.gc_time = gt", TG),
    m("G1GC1-S7", "    stats.aggr_index = STAT_NEXT_INDEX(stats.aggr_index)", "    stats.aggr_index = stats.aggr_index", TG),
    m("G1GC1-S8", "if stats.last_index == 0 && this.global_before != 0", "if stats.last_index == 0", TG),
    m("G1GC1-S9", "        reason = stats.request", "        reason = UInt64(0)", TG),
    m("G1GC1-S10", "    stats.request = 0", "    stats.request = stats.request", TG),
    m("G1GC1-S11", "stats.totals.global_gained += this.global_before - this.global_after", "stats.totals.global_gained += this.global_after - this.global_before", TG),
    m("G1GC1-S12", "stats.totals.trail_gained += this.trail_before - this.trail_after", "stats.totals.trail_gained += this.trail_after - this.trail_before", TG),
    m("G1GC1-S13", "stats.totals.collections += 1", "stats.totals.collections += 0", TG),
    m("G1GC1-S14", "stats.totals.time += this.gc_time", "stats.totals.time -= this.gc_time", TG),
    m("G1GC1-S15", "if gc_percentage(this) > 0.2", "if gc_percentage(this) > 0.5", TG),
    m("G1GC1-S16", "if gc_percentage(this) > 0.2", "if gc_percentage(this) > 0.0", TG),
    m("G1GC1-S17", "last_gc_stats(stats::gc_stats)::gc_stat = stats.last[STAT_PREV_INDEX(stats.last_index) + 1]",
      "last_gc_stats(stats::gc_stats)::gc_stat = stats.last[stats.last_index + 1]", TG),
    m("G1GC1-S18", "    d /= GC_STAT_WINDOW_SIZE\n", "", TG),
    m("G1GC1-S19", "gr = Int((r >> 8) & 0xff)", "gr = Int((r >> 9) & 0xff)", TG),
    m("G1GC1-S20", "ur = Int((r >> 36) & 0xff)", "ur = Int((r >> 40) & 0xff)", TG),
    m("G1GC1-S21", "        if this.global_before != 0\n            PL_unify_list(", "        if true\n            PL_unify_list(", TG),
    m("G1GC1-S22", "        index = STAT_PREV_INDEX(index)", "        index = STAT_NEXT_INDEX(index)", TG),
    m("G1GC1-S23", "PL_put_int64(ld, tmp, this.global_after) && PL_unify_arg(ld, 3, head, tmp)", "PL_put_int64(ld, tmp, this.global_before) && PL_unify_arg(ld, 3, head, tmp)", TG),
    m("G1GC1-S24", "PL_unify_float(ld, A3, gc_percentage(last))", "PL_unify_float(ld, A3, gc_percentage(aggr))", TG),
    m("G1GC1-S25", "PL_unify_float(ld, A4, gc_percentage(aggr))", "PL_unify_float(ld, A4, gc_percentage(last))", TG),
    m("G1GC1-S26", "PL_unify_float(ld, av + 1, gc_percentage(last))", "PL_unify_float(ld, av + 1, gc_percentage(aggr))", TG),
    m("G1GC1-S27", "PL_unify_float(ld, av + 2, gc_percentage(aggr))", "PL_unify_float(ld, av + 2, gc_percentage(last))", TG),

    # ---- G1-1: considerGarbageCollect, blockGC, the signal bits (GS)
    m("G1GC1-C1", "    if truePrologFlag(ld, PLFLAG_GC)", "    if true", TG),
    m("G1GC1-C2", "        if pendingGcSignal(ld, SIG_GC)", "        if false", TG),
    m("G1GC1-C3", "            if pol.gc\n", "            if true\n", TG),
    m("G1GC1-C4", "if used > pol.factor * pol.gced_size + low", "if used >= pol.factor * pol.gced_size + low", TG),
    m("G1GC1-C5", "if used > pol.factor * pol.gced_size + low", "if used > pol.gced_size + low", TG),
    m("G1GC1-C6", "elseif space < limit ÷ 8 && used > pol.gced_size + limit ÷ 32", "elseif space < limit ÷ 8 || used > pol.gced_size + limit ÷ 32", TG),
    m("G1GC1-C7", "elseif space < limit ÷ 8 && used > pol.gced_size + limit ÷ 32", "elseif space < limit ÷ 8 && used > pol.gced_size", TG),
    m("G1GC1-C8", "if ld.gc.inferences == ld.statistics.inferences && !ld.exception_processing", "if ld.gc.inferences == ld.statistics.inferences", TG),
    m("G1GC1-C9", "if ld.gc.inferences == ld.statistics.inferences && !ld.exception_processing", "if false", TG),
    m("G1GC1-C10", "pol.gced_size = used ", "pol.gced_size = 0 ", TG),
    m("G1GC1-C11", "s === :global ? GC_GLOBAL_REQUEST : GC_TRAIL_REQUEST", "s === :global ? GC_TRAIL_REQUEST : GC_GLOBAL_REQUEST", TG),
    m("G1GC1-B1", "function blockGC(ld::PL_local_data, flags::Int)::Nothing\n    if (flags & ALLOW_GC) == 0",
      "function blockGC(ld::PL_local_data, flags::Int)::Nothing\n    if (flags & ALLOW_GC) != 0", TG),
    m("G1GC1-B2", "function unblockGC(ld::PL_local_data, flags::Int)::Nothing\n    if (flags & ALLOW_GC) == 0",
      "function unblockGC(ld::PL_local_data, flags::Int)::Nothing\n    if (flags & ALLOW_GC) != 0", TG),
    m("G1GC1-B3", "ld.shift_status.blocked += 1", "ld.shift_status.blocked += 2", TG),
    m("G1GC1-B4", "ld.gc.status.blocked -= 1", "ld.gc.status.blocked -= 0", TG),
    m("G1GC1-G1", "ld.gc.sig_pending |= UInt64(1) << (sig - SIG_PROLOG_OFFSET)", "ld.gc.sig_pending |= UInt64(1) << (sig - SIG_PROLOG_OFFSET + 1)", TG),
    m("G1GC1-G2", "ld.gc.sig_pending &= ~(UInt64(1) << (sig - SIG_PROLOG_OFFSET))", "ld.gc.sig_pending &= (UInt64(1) << (sig - SIG_PROLOG_OFFSET))", TG),

    # ---- the wiring of statistics/2 and qp_statistics (GS, SYS)
    m("G1GC1-W1", "(st.user_cputime - ld.gc.stats.totals.time) * 1000.0", "st.user_cputime * 1000.0", TW, P),
    m("G1GC1-W2", "v[2] = stats.totals.trail_gained + stats.totals.global_gained", "v[2] = stats.totals.global_gained", TW, P),
    m("G1GC1-W3", "v[3] = trunc(Int64, stats.totals.time * 1000.0)", "v[3] = trunc(Int64, stats.totals.time * 100.0)", TW, P),
    m("G1GC1-W4", "v[4] = last.trail_after + last.global_after", "v[4] = last.global_after", TW, P),
    m("G1GC1-W5", "v[2] = ld.shift_status.local_shifts", "v[2] = ld.shift_status.trail_shifts", TW, P),
    m("G1GC1-W6", "v[3] = trunc(Int64, ld.shift_status.time * 1000.0)", "v[3] = trunc(Int64, ld.shift_status.time * 100.0)", TW, P),
    m("G1GC1-W7", "        v.f = ld.gc.stats.totals.time", "        v.f = ld.shift_status.time", TW, P),
    m("G1GC1-W8", "        v.i = ld.gc.stats.totals.collections", "        v.i = 0", TW, P),
    m("G1GC1-W9", "        v.i = ld.gc.stats.totals.trail_gained + ld.gc.stats.totals.global_gained", "        v.i = ld.gc.stats.totals.global_gained", TW, P),
    m("G1GC1-W10", "        v.i = ld.shift_status.global_shifts", "        v.i = ld.shift_status.local_shifts", TW, P),
    m("G1GC1-W11", "    elseif key === :local_shifts\n        v.i = ld.shift_status.local_shifts", "    elseif key === :local_shifts\n        v.i = ld.shift_status.trail_shifts", TW, P),
]
