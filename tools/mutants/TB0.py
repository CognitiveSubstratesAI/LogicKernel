# ORIGINAL: TB0's mutant list — no swipl-devel counterpart.
# tools/mutants/TB0.py — the mutation battery of TAB1 TB0 (the table state: src/pl-allocpool.jl = pl-allocpool.c; the freed-object lists
# `tbl_alloc`/`tbl_free`/`free_tbl_free_objects` and the sentinels of pl-tabling.c; `initTabling!` and `setMonotonicMode`; the table structs
# of pl-incl.jl/pl-global.jl; the four flags un-refused in src/os/pl-prologflag.jl `set_flag_value` (table_monotonic, table_space,
# table_compile_threshold, table_drop_intermediate); `statistics(table_space_used)` in src/pl-prims.jl). Run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as PIN1.py, D1f.py): `id`, `file`, `old` (must
# occur EXACTLY once), `new`, optional `equivalent` and `targets`. NOT RUN YET (written edit-only on wip/tb0, 2026-11-09, nothing compiled):
# every KILL below is read off the rows of wip/tb0 6d4bc882 (rows R1-R10 added there); the first hand-run replaces this header with the true verdicts.
# Each id names its KILL, the assertion that must fail (file:line at wip/tb0 6d4bc882):
#   TT = test/core_lang/test_tabling_state_swipl.jl; its first testset (TT:125-177) runs the pinned rows of `_TS_ROWS` (TT:51-68) through
#   `@test _ts_query(...) == want` at TT:133 (the row is named; an exception out of the VM, as G1's NotPortedError, is caught by `_ts_query` and
#   answers "threw <type>", a failing @test), then the white-box @tests TT:136-152; the pool testset is TT:179-199, the freed
#   objects TT:201-237, the state/initTabling!/setMonotonicMode/sentinel/literal testset TT:239-305, the allocation pins TT:316-341.
#   TS = test/core_lang/test_set_flag_swipl.jl (since TB0 it names none of the four flags: `_SF_REFUSED` TS:576-585 lost them), TP = test_prolog_flag_swipl.jl
#   (its oracle rows `t_defaults`/`t_count` read the four defaults, but only with the V10.1.20 oracle on PATH), TY = test_sys_swipl.jl (`t4`, `t96`
#   of test_sys_swipl.pl:23, :127 pin `statistics(table_space_used, V)` = 0 in the .out), TD = test_debug_flag_swipl.jl (the flag table, F1c's list).
# BOOT-PATH MUTANTS (D-0456 item 2, PIN1 part 2): the ids marked [BOOT] mutate `initPrologFlags!`'s flag table (src/os/pl-prologflag.jl:1962,
# :2106-2108), which `PL_global_data{T}()` copies from a template built ONCE per process (src/gd_template.jl). The warm daemon CANNOT judge them (a
# revised module leaves the booted template as it was: they survive there, or poison the daemon). ONLY `tools/mutate_ci.py one` (a fresh
# process, ~390 s per mutant, reference type) or the CI battery judges them. The other mutants are code run per call (alloc_pool, the lists,
# initTabling!, setMonotonicMode, the setters, statistics, sentinels) or per LD (`_bare_local_data`, built fresh by `PL_local_data{T}(gd)`, not
# copied from the template): the warm daemon may judge those, but the battery is CI.
# NEW KILL ROWS R1-R10: DONE at wip/tb0 6d4bc882 (edit-only, none run; each former "NEW ROW" mutant now names its row below; STRUCTURAL: none, every value is
# derived from the code or probed with swipl 10.1.20). The list as asked:
#   R1 TT pool: the resource_error's name (`PL_resource_error(ld, pool.name)`): read `ld.exception_term` as `_aw_formal` does, expect resource_error(test_pool)   [P6]  DONE 6d4bc882: TT:188 `_ts_formal`
#   R2 TT pool: `@test_throws AssertionError LK.free_to_pool(p, p.size + 1)`   [P9]  DONE 6d4bc882: TT:195
#   R3 TT freed: tbl_alloc/tbl_free the kinds WORKLIST_SET and WORKLIST, then free_tbl_free_objects empties ALL FOUR lists   [F8, F11]  DONE 6d4bc882: TT:216-228
#   R4 TT freed: `free_tbl_free_objects(ld, false)` AFTER `(ld, true)` leaves `closed` true (upstream sets it only when `closed`)   [F9]  DONE 6d4bc882: TT:233-234
#   R5 TT state: dirty ALL ten restraint fields before `initTabling!`, expect all ten back   [I2]  DONE 6d4bc882: TT:262-277
#   R6 TT state: a DIRECT `LK.tbl_restraint{_TS}()` row (the constructor's defaults are hidden at a fresh LD by `initTabling!`, called last by `_bare_local_data`)   [I1 doc]  DONE 6d4bc882: TT:259-261
#   R7 TT flags: `set_prolog_flag(table_space|table_drop_intermediate, 0)` succeeds (0 is no `size_t` error)   [G4, G8]  DONE 6d4bc882: the row `t_zero`, TT:65 (and the unchanged-after-a-failed-set rows `t_*_after`, TT:62-64)
#   R8 TT flags: after `t_thresh_neg`, `ld.table_flags_compile_threshold` is still 32 (the failed set changes nothing)   [G9]  DONE 6d4bc882: the row `t_thresh_after`, TT:62
#   R9 TT white-box literals: `(TF_MONOTONIC_LAZY, CLUSTER_ANSWERS, CLUSTER_SUSPENSIONS, SCC_NEG_NONE, SCC_NEG_DELAY, SCC_NEG_SIMPLIFY, TBL_FREE_COMPONENT.. TBL_FREE_CLUSTER,
#        TBL_FREE_KINDS, WLFS_FREE_NONE.., CAND_UNDECIDED.., DV_DELETED, DL_UNDEFINED)` == upstream's values (pl-tabling.h:42-51, :66-76; pl-tabling.c:288-296, :160-162,
#        :402-407; the PIN1-R1 pattern), and `tbl_component{_TS}()`'s status/neg_status = (SCC_ACTIVE, SCC_NEG_NONE)   [C3, C5, K3, K4]  DONE 6d4bc882: TT:293-304
#   R10 TT stat: `statistics(table_space_used, V)` after `LK.alloc_from_pool(ld, ld.tabling.node_pool, 100)` answers 100 (no predicate charges the pool until TR1)   [S3]  DONE 6d4bc882: TT:142-147
# TARGETS (audit D-0238): the step's own file TT; TS (set_prolog_flag/2's code path, `set_flag_value`); TP (the flag table rows); TD (the flag table, F1c's list);
# TY for `statistics(table_space_used)`. NOT listed: test_gd_template.jl (digests a template against its copy, both mutated alike), test_lb7_swipl.jl and
# test_firstboot_swipl.jl (`apply_options_to_flags!` rewrites `table_space` from the options, src/pl-init.jl:665, and no row reads the other three), test_static_analysis.jl
# (the CI's static job, not a mutation target). A neighbour that reads `ld.tabling` or `table_flags_*`: none (grepped test/ and src/ 2026-11-09).
# PIN1's declared survivors T3/T4/I5 (tools/mutants/PIN1.py on main, owner TAB1): RE-CHECKED against `git diff 0990857a HEAD -- src/os/pl-prologflag.jl` — TB0 does
# not touch `tbl_is_restraint_flag`, `keep_flag` or the order in `set_prolog_flag_unlocked`, and adds no row that sets or reads a `max_*` flag, so their `equivalent:`
# text stays TRUE with the line numbers moved by TB0's +17 lines above them: pl-prologflag.jl:1517 -> :1534, `tbl_is_restraint_flag` :1444 -> :1461, and
# test_set_flag_swipl.jl `_SF_REFUSED` TS:576-587 -> :576-585 (run at TS:593-601). T3/T4/I5 STAY declared (re-read 2026-11-09: no test sets a `*_action` flag, TB0's rows read the restraint STRUCT only); the lines are restated in tools/mutants/PIN1.py (DONE, TS:599 for the @test_throws, pl-prologflag.jl:1534-1535).
# Every `old` was counted EXACTLY once in its file at wip/tb0 6d4bc882 by a python3 -I script (the 41 here and the 23 of PIN1.py) (no Julia ran). RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
TT = "test/core_lang/test_tabling_state_swipl.jl"
TS = "test/core_lang/test_set_flag_swipl.jl"
TP = "test/core_lang/test_prolog_flag_swipl.jl"
TD = "test/core_lang/test_debug_flag_swipl.jl"
TY = "test/core_lang/test_sys_swipl.jl"
TCORE = [TT, TS, TP]                      # every mutant that no flag-table row can see differently
TFLAG = [TT, TS, TP, TD]                  # the boot-path flag defaults: the files that read the flag table
TARGETS = [TT, TS, TP, TD, TY]            # the baseline's targets (mutate_ci.py plan reads TARGETS): every file a mutant lists
POOL = "src/pl-allocpool.jl"
TAB = "src/pl-tabling.jl"
PF = "src/os/pl-prologflag.jl"
INC = "src/pl-incl.jl"
GL = "src/pl-global.jl"
PRIMS = "src/pl-prims.jl"
SPACE = ('        elseif name == "table_space"\n'
         "            # DIVERGES: `i > SIZE_MAX` cannot happen for an `Int64`; `shared_table_space` is TH1's (the kernel has no such flag).\n"
         "            if i < 0\n")
MUTANTS = [
    # ── pl-allocpool.jl: alloc_from_pool / free_to_pool / free_alloc_pool (pl-allocpool.c:41-93) ──
    dict(id="TB0-P1 alloc_from_pool refuses a charge that exactly fills the pool, `<` for `<=` (KILL TT:185 `alloc_from_pool(ld, p, 40) && p.size == 100`: the limit itself fits)",
         file=POOL, targets=[TT],
         old="        if pool.size + bytes <= pool.limit\n",
         new="        if pool.size + bytes < pool.limit\n"),
    dict(id="TB0-P2 alloc_from_pool stores the charge instead of adding it, `size = bytes` (KILL TT:185: after 60 and 40 the size is 40, not 100; TT:326-327 too)",
         file=POOL, targets=[TT],
         old="            pool.size += bytes\n",
         new="            pool.size = bytes\n"),
    dict(id="TB0-P3 alloc_from_pool raises no resource_error over the limit (KILL TT:187 `_ts_pending(ld)`; TT:339 `@allocated(_ts_overrun(ld, full)) > 0`: no error term is built)",
         file=POOL, targets=[TT],
         old="            PL_resource_error(ld, pool.name)\n            return false\n",
         new="            return false\n"),
    dict(id="TB0-P6 alloc_from_pool raises the resource_error of another name (KILL TT:188 `_ts_formal(ld) == 'resource_error(test_pool)'`, row R1: the exception's formal is read, `resource_error(table_space)` differs; no predicate reaches the overrun until TR1)",
         file=POOL, targets=[TT],
         old="            PL_resource_error(ld, pool.name)\n            return false\n",
         new='            PL_resource_error(ld, "table_space")\n            return false\n'),
    dict(id="TB0-P7 free_to_pool adds the bytes back instead of subtracting them (KILL TT:191 `p.size == 70`; TT:327 `p.size == 0`)",
         file=POOL, targets=[TT],
         old="        pool.size -= bytes\n",
         new="        pool.size += bytes\n"),
    dict(id="TB0-P8 free_to_pool's assertion is strict, `bytes < pool.size` (KILL TT:320 `@test _ts_ok(() -> _ts_charge!(ld, p))`, the warm call frees exactly what it charged and the strict assertion throws: a failing @test, no error out of the testset; TT:326 `na == 0` and TT:327 `p.size == 0` fail too)",
         file=POOL, targets=[TT],
         old="        @assert bytes <= pool.size\n",
         new="        @assert bytes < pool.size\n"),
    dict(id="TB0-P9 free_to_pool has no assertion that the bytes were charged (KILL TT:195 `@test_throws AssertionError LK.free_to_pool(p, p.size + 1)`, row R2; TT:196 `p.size == 100` fails too)",
         file=POOL, targets=[TT],
         old="        @assert bytes <= pool.size\n",
         new="        nothing\n"),
    dict(id="TB0-P10 free_alloc_pool does not mark the pool freed (KILL TT:198 `@test p.freed`)",
         file=POOL, targets=[TT],
         old="    pool.freed = true\n",
         new="    pool.freed = false\n"),
    # ── pl-tabling.jl: the freed-object lists (pl-tabling.c:396-452) ──
    dict(id="TB0-F1 tbl_free keeps TBL_FREE_MAX + 1 objects, `<=` for `<` (KILL TT:210 `length(...cluster) == LK.TBL_FREE_MAX == 16`)",
         file=TAB, targets=[TT],
         old="    if length(list) < TBL_FREE_MAX && !fo.closed\n",
         new="    if length(list) <= TBL_FREE_MAX && !fo.closed\n"),
    dict(id="TB0-F2 tbl_free keeps objects after the thread is closed (KILL TT:232 `fo.closed && isempty(fo.cluster)` after `free_tbl_free_objects(ld, true)`; TT:236 too)",
         file=TAB, targets=[TT],
         old="    if length(list) < TBL_FREE_MAX && !fo.closed\n",
         new="    if length(list) < TBL_FREE_MAX\n"),
    dict(id="TB0-F4 tbl_alloc takes the OLDEST freed object, `popfirst!` (KILL TT:211 `tbl_alloc(ld, kind) === cs[16]`: last freed, first reused; TT:224 and TT:335-336 too)",
         file=TAB, targets=[TT],
         old="    return pop!(list)\n",
         new="    return popfirst!(list)\n"),
    dict(id="TB0-F7 free_tbl_free_objects keeps the freed clusters (KILL TT:228 `all(isempty, (component, worklist_set, worklist, cluster))`, and TT:232)",
         file=TAB, targets=[TT],
         old="    empty!(fo.cluster)\n",
         new="    nothing\n"),
    dict(id="TB0-F8 free_tbl_free_objects keeps the freed worklists (KILL TT:228, row R3: the worklist and worklist-set kinds are freed at TT:221-226 and `all(isempty, four lists)` reads them)",
         file=TAB, targets=[TT],
         old="    empty!(fo.worklist)\n",
         new="    nothing\n"),
    dict(id="TB0-F9 free_tbl_free_objects(ld, false) clears `closed` again, `fo.closed = closed` (KILL TT:234 `@test fo.closed` after a (false) call that follows (true), row R4, TT:233)",
         file=TAB, targets=[TT],
         old="    closed && (fo.closed = true)\n",
         new="    fo.closed = closed\n"),
    dict(id="TB0-F11 the worklist kind's list is the cluster list (KILL TT:221 and TT:222, row R3: `tbl_free` of a worklist into the cluster vector throws, `_ts_ok` false; TT:220 and TT:224 fail too)",
         file=TAB, targets=[TT],
         old="tbl_free_list(fo::tbl_free_objects, ::Val{TBL_FREE_WORKLIST}) = fo.worklist\n",
         new="tbl_free_list(fo::tbl_free_objects, ::Val{TBL_FREE_WORKLIST}) = fo.cluster\n"),
    # ── pl-tabling.jl: initTabling! (pl-tabling.c:12696-12706); it runs LAST in `_bare_local_data`, so a fresh LD shows ITS values ──
    dict(id="TB0-I1 initTabling! sets max_scc_subgoals to 0, not unlimited (KILL TT:257 `(max_incomplete_subgoals, max_scc_subgoals) == (-1, -1)`, and TT:276 after the reset)",
         file=TAB, targets=[TT],
         old="    r.max_scc_subgoals = -1\n",
         new="    r.max_scc_subgoals = 0\n"),
    dict(id="TB0-I2 initTabling! leaves max_incomplete_subgoals as it is (KILL TT:276 `_ts_restraint(r) == _TS_RESTRAINT_DEFAULTS`, row R5: TT:264-273 dirty all ten fields, `max_incomplete_subgoals` stays 3)",
         file=TAB, targets=[TT],
         old="    r.max_incomplete_subgoals = -1\n",
         new="    nothing\n"),
    dict(id="TB0-I4 _bare_local_data does not call initTabling! (EQUIVALENT: the constructor `tbl_restraint{T}()`, src/pl-global.jl:376-379, builds the same ten defaults, `error` and -1; the call at pl-global.jl:802 repeats them)",
         file=GL, targets=[TT],
         equivalent="pl-global.jl:376-379 (`tbl_restraint{T}()` builds `error` for the five actions and -1 for the five sizes, the values of initTabling!, src/pl-tabling.jl) and pl-global.jl:422 (`ld_tabling{T}()` calls it): the call at pl-global.jl:802 sets what the constructor already holds, so no fresh LD differs; the reset by a LATER `initTabling!(ld)` call is TT:275-276 (row R5) and the constructor's defaults are TT:260-261 (row R6)",
         old="    initTabling!(ld)                            # the restraints at their defaults (pl-tabling.c initTabling; TAB1 TB0)\n",
         new="    nothing\n"),
    # ── pl-tabling.jl: setMonotonicMode (pl-tabling.c:11471-11485) ──
    dict(id="TB0-M1 `eager` sets TF_MONOTONIC_LAZY instead of clearing it (KILL TT:280 `setMonotonicMode(ld, eager) && (flags & TF_MONOTONIC_LAZY) == 0`)",
         file=TAB, targets=[TT],
         old="        ld.tabling.flags &= ~TF_MONOTONIC_LAZY\n",
         new="        ld.tabling.flags |= TF_MONOTONIC_LAZY\n"),
    dict(id="TB0-M3 an unknown atom is no domain_error: setMonotonicMode answers true (KILL TT:284 `!setMonotonicMode(ld, foo) && _ts_pending(ld)`; TT:133 rows t_mono_bad, f(domain_error(table_monotonic,foo),eager))",
         file=TAB, targets=[TT],
         old="        return PL_error(ld, ERR_DOMAIN, mk_sym(T, :table_monotonic), value)\n",
         new="        return true\n"),
    # ── pl-prologflag.jl: the setters of the four flags (pl-prologflag.c:1399, :1447-1474) ──
    dict(id="TB0-G1 table_monotonic is refused again, `_flag_not_ported` for the setMonotonicMode call (KILL TT:133 row t_mono: the NotPortedError raised out of the query is caught by `_ts_query`, the answer 'threw NotPortedError' is not f(lazy,eager))",
         file=PF, targets=TCORE,
         old="            setMonotonicMode(ld, a) || return false\n",
         new='            _flag_not_ported(k, "setMonotonicMode (tabling)")\n'),
    dict(id="TB0-G2 set_flag_value ignores setMonotonicMode's refusal, drops `|| return false` (KILL TT:133 row t_mono_bad: the flag then holds `foo`, the row pins `eager`)",
         file=PF, targets=TCORE,
         old="            setMonotonicMode(ld, a) || return false\n",
         new="            setMonotonicMode(ld, a)\n"),
    dict(id="TB0-G3 table_space accepts -1, the range check is `i < -1` (KILL TT:133 row t_space_neg: representation_error(size_t) is pinned)",
         file=PF, targets=TCORE,
         old=SPACE,
         new=SPACE.replace("if i < 0", "if i < -1")),
    dict(id="TB0-G4 table_space refuses 0, `i <= 0` (KILL TT:133 row t_zero, TT:65 f(0,0), row R7: the refused 0 answers 'exception')",
         file=PF, targets=TCORE,
         old=SPACE,
         new=SPACE.replace("if i < 0", "if i <= 0")),
    dict(id="TB0-G5 the pool of table_space is not named private_table_space (KILL TT:140 `node_pool.name == \"private_table_space\"`)",
         file=PF, targets=TCORE,
         old='                ld.tabling.node_pool = new_alloc_pool("private_table_space", Int(i))\n',
         new='                ld.tabling.node_pool = new_alloc_pool("table_space", Int(i))\n'),
    dict(id="TB0-G6 a second set of table_space leaves the limit of the existing pool (KILL TT:152 `pool.limit == 42`)",
         file=PF, targets=TCORE,
         old="                ld.tabling.node_pool.limit = Int(i)\n",
         new="                ld.tabling.node_pool.limit = ld.tabling.node_pool.limit\n"),
    dict(id="TB0-G8 table_drop_intermediate refuses 0, `i <= 0` (KILL TT:133 row t_zero, TT:65 f(0,0), row R7: the refused 0 answers 'exception'; the default 0 is not a set)",
         file=PF, targets=TCORE,
         old='        elseif name == "table_drop_intermediate"\n            if i < 0\n',
         new='        elseif name == "table_drop_intermediate"\n            if i <= 0\n'),
    dict(id="TB0-G9 table_compile_threshold goes on after the representation_error, no `return false` (KILL TT:133 row t_thresh_after, TT:62 `32`, row R8: the stored -1 is read back whatever the VM does with the true answer and its pending exception, else 'exception' and also not 32)",
         file=PF, targets=TCORE,
         old='        elseif name == "table_compile_threshold"\n            if i < 0\n'
             '                PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :size_t))\n                return false\n            end\n',
         new='        elseif name == "table_compile_threshold"\n            if i < 0\n'
             '                PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :size_t))\n            end\n'),
    dict(id="TB0-G10 table_compile_threshold is stored in the drop_intermediate field (KILL TT:136 `table_flags_compile_threshold == 5` and TT:137)",
         file=PF, targets=TCORE,
         old="            ld.table_flags_compile_threshold = Int(i)\n",
         new="            ld.table_flags_drop_intermediate = Int(i)\n"),
    # ── BOOT-PATH: the defaults of the flag table (pl-prologflag.c:2582, :2587-2592; initTabling's table_monotonic). Judged ONLY by `tools/mutate_ci.py one` or CI ──
    dict(id="TB0-B1 [BOOT] table_monotonic starts as `lazy` (KILL TT:133 row t_defaults: f(1073741824,32,0,eager); TP oracle row t_defaults too)",
         file=PF, targets=TFLAG,
         old='    setPrologFlag(gd, "table_monotonic", FT_ATOM, "eager")\n',
         new='    setPrologFlag(gd, "table_monotonic", FT_ATOM, "lazy")\n'),
    dict(id="TB0-B2 [BOOT] table_space starts at 2^29, not 2^30 (KILL TT:133 row t_defaults: 1073741824)",
         file=PF, targets=TFLAG,
         old='    setPrologFlag(gd, "table_space", FT_INTEGER, 1 << 30)\n',
         new='    setPrologFlag(gd, "table_space", FT_INTEGER, 1 << 29)\n'),
    dict(id="TB0-B3 [BOOT] table_compile_threshold starts at 31, not TABLE_COMPILE_THRESHOLD 32 (KILL TT:133 row t_defaults: the second field is 32)",
         file=PF, targets=TFLAG,
         old='    setPrologFlag(gd, "table_compile_threshold", FT_INTEGER, 32)\n',
         new='    setPrologFlag(gd, "table_compile_threshold", FT_INTEGER, 31)\n'),
    dict(id="TB0-B4 [BOOT] table_drop_intermediate starts at 1, not 0 (KILL TT:133 row t_defaults: the third field is 0)",
         file=PF, targets=TFLAG,
         old='    setPrologFlag(gd, "table_drop_intermediate", FT_INTEGER, 0)\n',
         new='    setPrologFlag(gd, "table_drop_intermediate", FT_INTEGER, 1)\n'),
    # ── pl-prims.jl: statistics(table_space_used) (pl-prims.c:6260) ──
    dict(id="TB0-S1 table_space_used answers the pool's LIMIT, not its size (KILL TT:133 row t_used_after: limit 1000000, size 0 expected; TT:145 `t_used` == 100 after a charge of 100)",
         file=PRIMS, targets=[TT, TY],
         old="        v.i = pool === nothing ? 0 : pool.size\n",
         new="        v.i = pool === nothing ? 0 : pool.limit\n"),
    dict(id="TB0-S3 table_space_used is always 0, as before TB0 (KILL TT:145 `_ts_query(t_used) == '100'`, row R10: TT:144 charges 100 to the pool, no predicate does until TR1)",
         file=PRIMS, targets=[TT, TY],
         old="        v.i = pool === nothing ? 0 : pool.size\n",
         new="        v.i = 0\n"),
    # ── pl-incl.jl: the constants and the struct defaults ──
    dict(id="TB0-C2 TF_MONOTONIC_LAZY is bit 3 (KILL TT:283 `setMonotonicMode(ld, eager) && t.flags == 0x8`: the bit is shared with the pinned 0x8)",
         file=INC, targets=[TT],
         old="const TF_MONOTONIC_LAZY = UInt32(0x0001)\n",
         new="const TF_MONOTONIC_LAZY = UInt32(0x0008)\n"),
    dict(id="TB0-C3 TF_MONOTONIC_LAZY is bit 2 (KILL TT:294 `TF_MONOTONIC_LAZY === UInt32(0x0001)`, row R9; pl-tabling.h:50)",
         file=INC, targets=[TT],
         old="const TF_MONOTONIC_LAZY = UInt32(0x0001)\n",
         new="const TF_MONOTONIC_LAZY = UInt32(0x0002)\n"),
    dict(id="TB0-C5 a new tbl_component starts SCC_MERGED, not SCC_ACTIVE (KILL TT:304 `(c.status, c.neg_status) == (SCC_ACTIVE, SCC_NEG_NONE) == (0, 0)`, row R9)",
         file=INC, targets=[TT],
         old="    COMPONENT_MAGIC, SCC_ACTIVE, SCC_NEG_NONE, 0, nothing,",
         new="    COMPONENT_MAGIC, SCC_MERGED, SCC_NEG_NONE, 0, nothing,"),
    # ── pl-tabling.jl: the sentinels and modes of pl-tabling.c:283-300 ──
    dict(id="TB0-K1 WL_GROUND is even, so it is no sentinel (KILL TT:287 `WL_IS_SPECIAL(WL_GROUND)`; TT:302 `(WL_GROUND, WL_DYNAMIC) == (0x21, 0x41)`)",
         file=TAB, targets=[TT],
         old="const WL_GROUND = 0x21\n",
         new="const WL_GROUND = 0x20\n"),
    dict(id="TB0-K3 DL_UNDEFINED is 0, the NULL delay list (KILL TT:301 `(DV_DELETED, DL_UNDEFINED) == (1, 1)`, row R9; TT:289 follows the constant and does not see it)",
         file=TAB, targets=[TT],
         old="const DL_UNDEFINED = 1\n",
         new="const DL_UNDEFINED = 0\n"),
    dict(id="TB0-K4 WLFS_FREE_ALL is WLFS_KEEP_COMPLETE (KILL TT:299 `(WLFS_FREE_NONE, WLFS_KEEP_COMPLETE, WLFS_FREE_ALL, WLFS_DISCARD_INCOMPLETE) == (0, 1, 2, 4)`, row R9: the consumer is TB2/TB3, a literal row is TB0's, as PIN1-R1; DV_DELETED (TT:301), CAND_* (TT:300), SCC_NEG_* (TT:296), TBL_FREE_* (TT:297-298), CLUSTER_* (TT:295) are the same rows)",
         file=TAB, targets=[TT],
         old="const WLFS_FREE_ALL = 0x0002\n",
         new="const WLFS_FREE_ALL = 0x0001\n"),
]
