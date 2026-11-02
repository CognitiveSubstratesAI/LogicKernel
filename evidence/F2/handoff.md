# F2 handoff — push_prolog_flag/2, pop_prolog_flag/1 (pl-prologflag.c)

Branch wip/f2 off wip/f1b a946760 (F2 is STACKED on F1b: it uses `set_flag_value`, `new_prolog_flag`, `clean_prolog_flag`,
`check_flag_write_access`, `deletePrologFlag!`, the `pushed` field and `FF_PUSH_ABSENT`, all F1b/F1a). Edit-only writer (WRITER_RULES.md).
Upstream: swipl-devel cbf4e1896275 src/os/pl-prologflag.c, extract in the writer's scratchpad. The sprint row says 1862-1960; the
functions of the area run :1818-1991 (the helpers above the predicates, the pop function to its closing brace).

## Functions of the range (upstream line -> Julia site, all src/os/pl-prologflag.jl unless named)
1. :387 `copy_prolog_flag` (F1b did not write it; push needs it) -> new, next to `clean_prolog_flag`'s neighbours (own section 'push and pop').
2. :1822 `put_saved_flag_value` -> new. Needs `PL_put_float` (src/pl-fli.jl; the kernel has `PL_put_int64`, `PL_put_atom`, not the float put): append it to pl-fli.jl.
3. :1849 `ensure_local_flag` -> new, a DIVERGES: the build is upstream's single-threaded one (`O_PLMT` undefined, file header, design D1): the function is
   `return f` there; the `FF_SHARED` refusal of push (a thread-local rule) is ported as is.
4. :1862 `push_prolog_flag` (PRED_IMPL, flags 0) -> `push_prolog_flag(gd, ld, key, value)` + `pl_push_prolog_flag2_va`.
5. :1929 `pop_prolog_flag` (PRED_IMPL, flags 0) -> `pop_prolog_flag(gd, ld, key)` + `pl_pop_prolog_flag1_va`. Uses `deletePrologFlag!` (F1a, written for it).
6. :3044-3045 registration: two `PL_extension` entries LAST in `PL_predicates_from_prologflag` (upstream order: after `$current_prolog_flag`/5).
`PL_current_prolog_flag` (:1992) is F1a, already there.

## Plan (commits)
1. This plan. 2. `UPSTREAM: pl-prologflag.c copy_prolog_flag put_saved_flag_value ensure_local_flag push_prolog_flag pop_prolog_flag (swipl-devel cbf4e1896275)` with
   PL_put_float and the file-header reword (the header says push/pop are left to F2). 3. rows (generator + driver + .out, test/core_lang/test_push_flag_swipl.jl).
4. tools/mutants/F2.py (>= 8). 5. docs/architecture.md block (appended). 6. manifest block (appended, LAST).

## Decisions
- The refusals of F1b stay: a push/pop of a flag whose side effect is refused by name (debug, encoding, ...) reaches `set_flag_value` and ends in `NotPortedError`, as
  upstream's push reaches that function. The arithmetic/ci_*/tabling-restraint flags are NOT checked by `set_flag_value` (upstream: by `set_prolog_flag_unlocked`), so push on
  them stores the table value only, as upstream does.
- Thread-local table (`register_local_flag`, `LD->prolog_flag.table`): left out; a pushed-absent flag is added to the one table (`entries`/`names`/`slot`, as `set_prolog_flag_unlocked` does).

## State at hand-back (writer 1, forced by the 150k cap; NOTHING compiled or run)
- Commits: 715c92a plan; 9264a6e the port (src/os/pl-prologflag.jl: copy_prolog_flag, put_saved_flag_value, ensure_local_flag, `_prolog_flag_table_get`,
  push_prolog_flag, pl_push_prolog_flag2_va, pop_prolog_flag, pl_pop_prolog_flag1_va; two entries LAST in PL_predicates_from_prologflag; file header reworded;
  src/pl-fli.jl `PL_put_float` appended); 0042993 rows pf01-pf42 (test/core_lang/test_push_flag_swipl.jl).
- UNCOMMITTED at the cap, committed with this handoff: rows pf43/pf44 added (evidence/F2/make_cases.py -> push_cases.json -> build_push_test.py -> test file;
  gen_push_rows.py re-pinned swipl 10.1.19, 45 lines, two byte-identical runs; push_template.jl says pf01-pf44). pf43 = a failed push on a flag that already has a
  frame leaves that frame intact (kill row of "copy has pushed values"); pf44 = a nest on an existing flag.
- LEFT: (1) tools/mutants/F2.py (>= 8; plan below, every `old` once: I counted with grep -c -F on the port commit, two anchors were found TWICE and need the multi-line
  forms given); (2) a throwaway python3 -I + runpy checker in the scratchpad (old once, new != old, ids unique, targets exist); (3) docs/architecture.md block (appended);
  (4) test/static_analysis_manifest.jl block (appended, LAST): copy_prolog_flag(prolog_flag{T}), put_saved_flag_value(PL_local_data{T}, Int, prolog_flag{T}),
  ensure_local_flag(T, prolog_flag{T}), push_prolog_flag(PL_global_data{T}, PL_local_data{T}, Int, Int), pop_prolog_flag(PL_global_data{T}, PL_local_data{T}, Int),
  pl_push_prolog_flag2_va / pl_pop_prolog_flag1_va (look at F1b's `pl_set_prolog_flag2_va` entry for the control_t form), `_prolog_flag_table_get`, PL_put_float(PL_local_data{T}, Int, Float64).
- MUTANT PLAN for F2.py (file P = src/os/pl-prologflag.jl unless named; TARGETS = ["test/core_lang/test_push_flag_swipl.jl"] for all; header: anchors need a re-fit after
  `warm.sh fmt`; id prefix F2-; format of tools/mutants/F1B.py: dict(id=, file=, old=, new=, targets=, equivalent=):
  A1 `    if (prev.flags & FF_PUSH_ABSENT) != 0` -> `    if false` (KILL pf13-pf17, pf20, pf22)
  A2 `        deletePrologFlag!(gd, w)\n` -> `        nothing\n` (pf13)
  A3 `    nf.pushed = absent\n` -> `    nf.pushed = nothing\n` (pf13)
  A4 `            f.pushed = saved\n` -> `            nothing\n` (pf01, pf04)
  A5 `            saved.pushed = f.pushed\n` -> `            nothing\n` (pf18, pf23, pf38, pf44)
  A6 `f.t, f.oneof, nothing)   # *copy = *f; copy->pushed = NULL` -> `f.t, f.oneof, f.pushed)   # *copy = *f; copy->pushed = NULL` (pf43: clean_prolog_flag(saved) then zeroes the real frame)
  A7 `        copy.t = PL_duplicate_record(f.t::record{T})` -> `        copy.t = nothing` (pf30)
  B1 `        return PL_put_float(ld, val, saved.f)` -> `... saved.f + 1.0)` (pf26)
  B2 `        return PL_recorded(ld, saved.t::record{T}, val)` -> `        return PL_put_atom(ld, val, saved.a)` (pf30)
  B3 `        return PL_put_int64(ld, val, Int(saved.i))` -> `... Int(saved.i) + 1)` (pf24)
  B4 `    if type == FT_BOOL || type == FT_ATOM` -> `    if type == FT_ATOM` (pf04)
  C1 `        if (f.flags & FF_SHARED) != 0` -> `        if false` (pf35, pf36)
  C2 `        check_flag_write_access(ld, f, k, UInt32(0)) || return false\n` -> `        nothing\n` (pf07, pf10, pf37)
  C3 `mk_sym(T, :push)` -> `mk_sym(T, :modify)` (pf35)
  D1 `    if f === nothing || f.pushed === nothing` -> `    if f === nothing` (pf02: TypeAssert on prev)
  D2 `        f.pushed = prev.pushed\n` -> `        f.pushed = nothing\n` (pf18, pf38, pf44)
  D3 `        rc = set_flag_value(gd, ld, f, m, k, value)\n` -> `        rc = true\n` (pf01)
  D4 `        rc = set_flag_value(gd, ld, f, m, k, restore)\n` -> `        rc = true\n` (pf01)
  D5 `ensure_local_flag(k::T, f::prolog_flag{T}) where {T} = f` -> `... = copy_prolog_flag(f)` (pf01: the write goes to a copy)
  D6 `FT_INTEGER | FF_PUSH_ABSENT` -> `FT_INTEGER` (pf13)
  D7 `new_prolog_flag(ld, value, FT_FROM_VALUE)` -> `new_prolog_flag(ld, value, FT_ATOM)` (pf13 type_error)
  D8 (TWO matches of the one line: use) `    push!(tab.names, k)\n    tab.slot[w] = length(tab.entries)\n    return true\n` -> without the slot line (pf13); check it occurs once
  D9 `PL_extension("pop_prolog_flag", 1,` -> `PL_extension("pop_prolog_flag", 2,` (pf01); D10 `mk_sym(T, :pushed_flag)` -> `mk_sym(T, :prolog_flag)` (pf02)
  E1 file src/pl-fli.jl: `    setSlotValue!(ld, t + 1, mk_gnd(T, f))\n` (once) -> `mk_gnd(T, f + 1.0)` (pf26)
  EQ1 (equivalent) `        clean_prolog_flag(f)\n        return true` in pop's absent branch -> `        return true`: the flag is unreachable after deletePrologFlag! (pl-prologflag.jl:178
      empties its slot; an enumeration holds a slot number), the frame it cleans has no oneof (made by new_prolog_flag).
  NOT LISTED: `of.references += 1` in copy_prolog_flag (anchor is TWICE in the file, :929 and :1531) and `clean_prolog_flag(saved)` in push's failure branch: the count is read only in
  clean_prolog_flag (:992-993) but a flag with a oneof that a later keep_flag cleans could see it: no row, so no verdict claimed.
- UNVERIFIED (nothing compiled): `PL_strip_module(gd, ld, A1, MODULE_parse(ld), key)` with a NEW term ref as `plain` (set_prolog_flag_ptr passes the key as both); `check_flag_write_access` with
  flags `UInt32(0)`; `PL_put_float`'s `mk_gnd(T, ::Float64)` word; the `&&` chain in the FF_SHARED branch (fmt will re-wrap); `_pf_query` on a database after a NotPortedError in the refused testset
  (a second query on the same gd); the rows' kernel answers (none run; the double_quotes/back_quotes/last_call rows read user-module defaults).
- FINDINGS for the audit (undecided): (1) one table, so a push/pop is process-wide where upstream's is per thread (DIVERGES comment in the code; file header: single-threaded build); (2) the arithmetic/ci_*/tabling-restraint
  flags are NOT checked by set_flag_value (upstream: by set_prolog_flag_unlocked), so a push on them stores the table value only, as upstream; (3) `PL_put_float` appended to pl-fli.jl (merge risk with another writer adding it);
  (4) push of an absent flag ignores user_flags (as upstream): NO swipl row, the user_flags=error + new key case has no swipl answer to pin (detail in the private register).
- Hook notes: the absence-claim hook fired on the phrase 'is absent' in a commit body; reworded ('first created by the push').

## State at hand-back (coder 2; NOTHING compiled or run)
- Commits after 971ffda: 54bbb25 tools/mutants/F2.py (26 mutants: A1-A7, B1-B4, C1-C3, D1-D10, E1, EQ1; checked with a throwaway
  python3 -I + runpy checker: every `old` once, new != old, ids unique, targets exist; the plan said 27, the list above is what the
  plan names); 8446f94 docs/architecture.md (an `## F2` section inserted BEFORE `## Still to come`; F1b's block sits at the file end
  inside the Still-to-come list, so the two do not neighbour); 76bed45 test/static_analysis_manifest.jl (nine entries, inserted
  directly after F1b's last entry `PL_get_int64_ex`, inside `_manifest_index`).
- Anchor notes: D8 uses the three-line form (the slot line occurs twice); C1's anchor ends in two spaces (the line carries a
  trailing comment, so fmt may re-flow it: re-fit); all targets are the one row file (no mutant touches set_flag_value, so
  test_set_flag_swipl.jl is not listed, said in the header).
- LEFT: the gate (GATE ORDER below); the audit's findings 1-4 above stay undecided.
- Merge risk: `PL_put_float` is appended to src/pl-fli.jl (after PL_put_integer) and a manifest entry for it sits in the F2 block;
  another writer adding the same function or entry makes a duplicate-definition or duplicate-entry at the rebase.
- UNVERIFIED (nothing compiled): the manifest argument types (Int for term_t, `Tuple{T, prolog_flag{T}}` for `ensure_local_flag`);
  `PL_put_float` calls `PL_nan()` (src/pl-arith.jl:124, defined; not read in a running image); the mutant anchors after fmt.

## GATE ORDER (F2; Tier 2, gates ON TOP OF the F1b/D stack: F2 uses F1b's set_flag_value, new_prolog_flag, clean_prolog_flag, check_flag_write_access and the `pushed` field)
1. Rebase wip/f2 onto the stack after F1b (src/os/pl-prologflag.jl, docs/architecture.md and test/static_analysis_manifest.jl take appended blocks; no pl-global.jl change here).
2. fmt: `tools/warm.sh send` of the committed files (fmt sees only the HEAD diff): src/os/pl-prologflag.jl, src/pl-fli.jl, test/core_lang/test_push_flag_swipl.jl, test/static_analysis_manifest.jl;
   re-fit the F2.py anchors that were re-flowed (checker: old once, new != old).
3. inventory, then `tools/warm.sh check`.
4. rows on all three term types: test/core_lang/test_push_flag_swipl.jl.
5. test/test_type_discipline.jl.
6. `tools/pkgtest_way.sh test/core_lang/test_push_flag_swipl.jl` (one at a time, ~3 GB).
7. push `mutants/F2` at the WIP SHA once the list exists; branch-gate; term grep (D-0164, over diff and message); then `gate/<fresh name>` and `mutants/F2` at the SAME SHA.
8. No alloc pins (no Tier-1 file, no pl-global.jl change).

## Gate agent 1 state (2026-11-02 ~15:00 UTC)
- Rebased ONCE onto origin/main 8ba3fae as wip/f2s (wip/f2r = same without the secrecy rewording, wip/f2r-bak = alias; wip/f2 = old stack, untouched). Conflicts: docs/architecture.md (kept BOOTPRED block then F2 block), static_analysis_manifest.jl (dropped the F1b line PL_get_int64_ex, already on main at the second table).
- Light work done: stale-pin hunt (no hit names push/pop_prolog_flag outside the F2 row file), term grep over the full history (one evidence line reworded in the history), authors checked.
- LEFT: daemon (three were up), fmt, inventory, check, Aqua+JET, rows x3, type discipline, pkgtest_way, push.
