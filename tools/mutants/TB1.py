# ORIGINAL: TB1's mutant list; swipl-devel has no mutant list.
# tools/mutants/TB1.py — the mutation battery of TAB1 TB1 (the variant tables of src/pl-tabling.jl = pl-tabling.c: the node cache of start nodes,
# the pointers to tries `TRIE_PTR_TAG`/`triePtrValue`/`valueTriePtr`/`value_trie` and `trie_serial!`, `variant_table`, `get_answer_table`,
# `unify_trie_ret`, the table-status family, `unify_skeleton`, the `$tbl_*` predicates of the variant tables, `tbl_implementation`, the release
# functions). Run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as TB0.py, PIN1.py):
# `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. NOT RUN YET (written edit-only on wip/tb1 after 6acfd472,
# 2026-11-10, nothing compiled): every KILL below is read off the rows of test/core_lang/test_tabling_variant_swipl.jl at wip/tb1 6acfd472; the first
# hand-run replaces this header with the true verdicts. Each id names its KILL, the assertion that must fail:
#   TV = test/core_lang/test_tabling_variant_swipl.jl. Its rows are the `_TV_PRE_CASES` (tvb01-tvb06, run BEFORE any table) and `_TV_CASES` (tvv01-tvv06
#   `$tbl_existing_variant_table`, tvs01-tvs08 the status, tvp01-tvp05 `$tbl_table_pi`, tvt01-tvt08 the tries, tvl01-tvl07 the variant table,
#   tvi01-tvi08 `$tbl_implementation`, tvn01-tvn07 `$tnot_implementation`), each compared with its pinned swipl answer at TV:330-337 and TV:367-370
#   (`@test k == p`); a Julia exception out of the code (a BoundsError, a NotPortedError of a refusal) is no answer: it errors the testset, which is a kill.
#   The white-box @tests: TV:340-346 (the variant table exists, is `gd.tries[ld.tabling.variant_table]`, TRIE_ISVARIANT, `value_count == 2`, every trie
#   `serial >= 1`), TV:348-356 (the answer tries: flags TABLE|SET|COMPLETE, `registry`, `variant != 0`, `isTriePtrValue`, `valueTriePtr`, `value_trie`,
#   `is_variant_trie`), TV:358-360 (`WL_GROUND` for the ground table, `nothing` for the other).
#   TT = test_tabling_state_swipl.jl (TT:337 pins `(DV_DELETED, DL_UNDEFINED) == (-1, 1)`), TM = test_tabling_min_swipl.jl (the tabling attributes, the
#   `$tbl_trienode` rows: it does not call a TB1 function, listed for `is_tabled` whose flag its attribute rows set), TB = test/db/test_boot_image_swipl.jl
#   (TB:161, the count of the foreign predicates the kernel lacks: a changed registration changes the count).
# DEFERRED KILL (audit D-0374 item 2, as PIN1.py): a row declared `equivalent="DEFERRED KILL: owner ..."` has no killing assertion yet: no test file reads
# what the mutant changes. It must SURVIVE the battery; when the owner step adds the row, the declaration goes. The deferred ones and the row each owner adds:
#   * the node cache of start nodes (`start_node_id`, `get_start_node`, `set_start_node`): its user is `tbl_complete_answer_clause` (pl-tabling.c) = TB3; no row
#     reads it before. Row for TB3: `set_start_node(ld, tr, id, nid)` on the variant table, then `get_start_node(ld.tabling.start_nodes, id) == nid`,
#     `tr.nodes[nid].flags & TN_PINNED != 0`, an id past the end answers 0 and the entries between are 0 (TB1-N2, N3).
#   * `reset_answer_table`, `release_variant_table_node`, `tbl_release_node`: called by the abolish (TB5) and the trie's release_node (TR1's stack); no TB1 row
#     reaches them. Row for TB5: `reset_answer_table(atrie, 0)` on a complete answer trie with answers and read `TRIE_COMPLETE`, `worklist`, the answer count;
#     `release_variant_table_node` on a variant table's node and read `atrie.variant == 0` (TB1-L1, L4).
#   * `table_status`: no caller before TB3 (git grep at 6acfd472: only the definition), TB1-F6.
#   * the refusal sites of a later step (TH1 the shared tables, TB2 the worklist branch of reset_answer_table (owner TB5 since batch 3), TB4 the delay information, TB6 the
#     IDG, TB8 the tripwires): no TB1 row reaches a refusal (the rows are the branches TB1 ports).
#   * ROWS TB1's own test could add (the dispatcher decides whether TB1 or the owner does): a literal row `@test LK.TRIE_PTR_TAG == 0x7` (TB1-R2: the tag is
#     consumed by `isTriePtrValue` and `triePtrValue` alike, so a changed value is invisible to a round trip), `@test variants.registry === gd.tries` and
#     `ld.tabling.node_pool.name == "private_table_space"` after a lookup (TB1-V5; TB1-V3 is a kill, CI 43111712333), a table of TWO variables (`tv_r(_, _)`: skeleton `ret(V0, V1)`, and
#     `tv_r(X, X)`: `ret(V0)`) for `unify_trie_ret`'s argument loop (TB1-T3), `$tbl_variant_table/6`, `$tbl_abstract_table/6`, `$tbl_moded_variant_table/6`
#     on an EXISTING complete table (they find it and answer without the refused create path: TB1-P7), and the node count of the variant table after a failed
#     lookup (`$tbl_existing_variant_table` must not create a node: TB1-G9).
# TARGETS (audit D-0238): TV (every mutant of a variant-table function), TT (DV_DELETED), TM (`is_tabled`), TB (the foreign-predicate registration).
# NOT listed: test_static_analysis.jl (the CI's static job, not a mutation target) and the dispatch manifest (test/static_analysis_manifest.jl names the
# TB1 functions by signature: a mutant here keeps every signature). A neighbour that reads these functions: none (git grep -F at wip/tb1 6acfd472 over src/ and test/).
# Every `old` was counted EXACTLY once in its file at wip/tb1 by a python3 -I script (no Julia ran). RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
TV = "test/core_lang/test_tabling_variant_swipl.jl"
TT = "test/core_lang/test_tabling_state_swipl.jl"
TM = "test/core_lang/test_tabling_min_swipl.jl"
TB = "test/db/test_boot_image_swipl.jl"
TARGETS = [TV, TT, TM, TB]                # the baseline's targets (mutate_ci.py plan reads TARGETS): every file a mutant lists
TAB = "src/pl-tabling.jl"
# the first lines of the two predicates whose body is the same text, told apart by the function name
HDR1 = ("(\n    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}\n)::foreign_t where {T}\n"
        "    gd = _query_gd(ld)\n    ld.tabling.variant_table == 0 && return FFALSE\n")
MUTANTS = [
    # ── constants and the pointers to tries (pl-trie.h:201-211; TB1's DV_DELETED = -1) ──
    dict(id="TB1-C1 DV_DELETED is 1 (KILL TT:337 `(LK.DV_DELETED, LK.DL_UNDEFINED) == (-1, 1)`; -1 keeps it apart from a trie's serial, which is >= 1)",
         file=TAB, targets=[TT, TV],
         old="const DV_DELETED = -1\n",
         new="const DV_DELETED = 1\n"),
    dict(id="TB1-R1 isTriePtrValue masks two bits, `& 0x3` (KILL TV:353 `isTriePtrValue(w)`; the value is then read as a symbol: value_trie throws at tvv01, TV:355)",
         file=TAB, targets=[TV],
         old="isTriePtrValue(w::word)::Bool = (w & UInt64(0x7)) == TRIE_PTR_TAG\n",
         new="isTriePtrValue(w::word)::Bool = (w & UInt64(0x3)) == TRIE_PTR_TAG\n"),
    dict(id="TB1-R2 TRIE_PTR_TAG is 0x5 (no row reads the tag's value: `isTriePtrValue` and `triePtrValue` both read the constant, the round trip TV:354 is unchanged)",
         file=TAB, targets=[TV],
         old="const TRIE_PTR_TAG = UInt64(0x7)\n",
         new="const TRIE_PTR_TAG = UInt64(0x5)\n",
         equivalent="DEFERRED KILL: owner TB1's test (a literal row `@test LK.TRIE_PTR_TAG == 0x7`, pl-trie.h:201-211): the tag is read only through `TRIE_PTR_TAG` "
                    "in `isTriePtrValue` (src/pl-tabling.jl:464) and `triePtrValue` (:469-472), so the value round trip TV:353-355 holds for any tag; the only other "
                    "reader of a node value, `value_trie` (:492-497), meets a symbol atom whose low three bits are not read by a TB1 row"),
    dict(id="TB1-R3 triePtrValue shifts the serial by two, `<< 2` (KILL TV:354 `valueTriePtr(gd.tries, w) === atrie`: serial 2 reads back as trie 1, the variant table)",
         file=TAB, targets=[TV],
         old="    return (UInt64(tr.serial) << 3) | TRIE_PTR_TAG\n",
         new="    return (UInt64(tr.serial) << 2) | TRIE_PTR_TAG\n"),
    dict(id="TB1-R5 triePtrValue asserts nothing (EQUIVALENT: its one caller registers the trie right before)",
         file=TAB, targets=[TV],
         old="    @assert tr.serial != 0\n",
         new="    nothing\n",
         equivalent="src/pl-tabling.jl:733-736: get_answer_table calls `trie_serial!(gd, atrie)` (:733) and then `node.value = triePtrValue(atrie)` (:736), the only "
                    "caller (git grep -F triePtrValue at wip/tb1: the definition :469, the call :736, TV:354's `valueTriePtr`), so `tr.serial != 0` always holds at the assertion (:470)"),
    dict(id="TB1-S1 trie_serial! registers only an already registered trie, `!= 0` (KILL TV:343 `_tv_tables!`: the first answer trie keeps serial 0 and triePtrValue's assertion throws; TV:346 `all(serial >= 1)`)",
         file=TAB, targets=[TV],
         old="    if tr.serial == 0\n        push!(gd.tries, tr)\n",
         new="    if tr.serial != 0\n        push!(gd.tries, tr)\n"),
    dict(id="TB1-S2 trie_serial! numbers the trie one past its place, `length + 1` (KILL TV:354 `valueTriePtr(gd.tries, w) === atrie`: the registry index is out of range, BoundsError)",
         file=TAB, targets=[TV],
         old="        tr.serial = length(gd.tries)\n",
         new="        tr.serial = length(gd.tries) + 1\n"),
    # ── variant_table (pl-tabling.c variant_table) ──
    dict(id="TB1-V1 variant_table creates the table when it exists and not when it does not, `!= 0` (KILL tvb04: the first lookup reads `gd.tries[0]`, BoundsError; tvb01-tvb06 follow)",
         file=TAB, targets=[TV],
         old="    if ld.tabling.variant_table == 0\n        t = trie_create(T)\n",
         new="    if ld.tabling.variant_table != 0\n        t = trie_create(T)\n"),
    dict(id="TB1-V2 the variant table is not flagged TRIE_ISVARIANT (KILL TV:344 `(variants.flags & TRIE_ISVARIANT) != 0` and TV:358 `is_variant_trie(variants)`)",
         file=TAB, targets=[TV],
         old="        t.flags |= TRIE_ISVARIANT\n",
         new="        t.flags |= UInt32(0)\n"),
    dict(id="TB1-V3 the variant table keeps no registry (KILL: the TV testset 'variant tables as swipl's' (TV:327) ends in an exception, `Error During Test`; CI battery 43111712333 "
            "caught it that way. A trie value that is a pointer to a trie is read through the owning trie's `registry` (`valueTriePtr(tr.registry, w)`, src/pl-trie.jl:167 and :1659; "
            "src/pl-tabling.jl:624): with the default empty registry the read fails. Declared EQUIVALENT before the first run: that was wrong)",
         file=TAB, targets=[TV],
         old="        t.registry = gd.tries\n        ld.tabling.variant_table = t.serial\n",
         new="        ld.tabling.variant_table = t.serial\n"),
    dict(id="TB1-V4 the variant table is not registered (`trie_symbol` dropped): its serial is 0 (KILL tvb04: `gd.tries[ld.tabling.variant_table]`, index 0, BoundsError; TV:346)",
         file=TAB, targets=[TV],
         old="        trie_symbol(gd, t)\n",
         new="        nothing\n"),
    dict(id="TB1-V5 the private pool is made only when there is one, `!== nothing` (no row reads `ld.tabling.node_pool` after a lookup: statistics(table_space_used) is 0 with a pool or none)",
         file=TAB, targets=[TV],
         old="    if ld.tabling.node_pool === nothing\n        ld.tabling.node_pool = new_alloc_pool(\"private_table_space\"",
         new="    if ld.tabling.node_pool !== nothing\n        ld.tabling.node_pool = new_alloc_pool(\"private_table_space\"",
         equivalent="DEFERRED KILL: owner TB3 (the first charge of the pool by an answer trie's nodes: `alloc_from_pool`, src/pl-allocpool.jl, has no caller before it): "
                    "TT:142-147 charges a pool it makes itself and the table_space_used rows of test_sys_swipl.jl read 0 for a pool of size 0 and for none "
                    "(src/pl-prims.jl: `pool === nothing ? 0 : pool.size`); row to add: after a lookup `ld.tabling.node_pool.name == \"private_table_space\"`"),
    # ── get_answer_table (pl-tabling.c get_answer_table) ──
    dict(id="TB1-G1 get_answer_table treats a call with variables as ground, `!isempty(vars)` (KILL tvv01: the ground variant answers `ret(...)` with an empty `vars`, AssertionError of unify_trie_ret; tvv02, TV:359)",
         file=TAB, targets=[TV],
         old="        if isempty(vars)                            # TBD: only needed first time\n",
         new="        if !isempty(vars)                           # TBD: only needed first time\n"),
    dict(id="TB1-G2 a ground table's worklist is WL_DYNAMIC, not WL_GROUND (KILL TV:359 `atries[1].worklist == LK.WL_GROUND`; tvt02: `$is_answer_trie` answers dynamic for the ground table, pin normal)",
         file=TAB, targets=[TV],
         old="                atrie.worklist = WL_GROUND\n",
         new="                atrie.worklist = WL_DYNAMIC\n"),
    dict(id="TB1-G3 a ground table with a worklist object is not marked ground (no worklist object before TB2)",
         file=TAB, targets=[TV],
         old="                wl.ground = true\n",
         new="                nothing\n",
         equivalent="DEFERRED KILL: owner TB2 (the worklists: `tbl_worklist` is made by `tbl_add_worklist`, refused by name at src/pl-tabling.jl:767 until TB2): "
                    "the branch `wl isa tbl_worklist` (:723) is reached by no TB1 row because no table has a worklist object; row for TB2: a ground call that "
                    "makes a worklist, then `wl.ground`"),
    dict(id="TB1-G4 the skeleton of a ground call is the atom `fresh`, not `ret` (KILL tvv01 and tvs03: the pinned skeleton is `ret`)",
         file=TAB, targets=[TV],
         old="            PL_unify_atom(ld, ret, mk_sym(T, :ret)) || return nothing\n",
         new="            PL_unify_atom(ld, ret, mk_sym(T, :fresh)) || return nothing\n"),
    dict(id="TB1-G5 a table is a map when not moded and a set when moded (KILL TV:348 `(flags & (ISTABLE | ISSET | COMPLETE)) == (ISTABLE | ISSET | COMPLETE)`)",
         file=TAB, targets=[TV],
         old="((flags & AT_MODED) != 0 ? TRIE_ISMAP : TRIE_ISSET)",
         new="((flags & AT_MODED) != 0 ? TRIE_ISSET : TRIE_ISMAP)"),
    dict(id="TB1-G6 a new answer table knows no variant node, `variant = 0` (KILL TV:351 `atrie.variant != 0`; tvp01 and tvs03: `$tbl_table_pi` and `unify_skeleton` fail without the node)",
         file=TAB, targets=[TV],
         old="        atrie.variant = nid\n",
         new="        atrie.variant = 0\n"),
    dict(id="TB1-G7 a new answer table has no registry (KILL TV:350 `atrie.registry === gd.tries`)",
         file=TAB, targets=[TV],
         old="        atrie.registry = gd.tries\n        trie_serial!(gd, atrie)\n",
         new="        trie_serial!(gd, atrie)\n"),
    dict(id="TB1-G8 the variant table's value count is not incremented for a new table (KILL TV:345 `variants.value_count == 2`)",
         file=TAB, targets=[TV],
         old="        variants.value_count += 1                   # TRIE_COUNT_INC(variants, value_count)\n",
         new="        nothing                                     # TRIE_COUNT_INC(variants, value_count)\n"),
    dict(id="TB1-G9 the lookup creates the variant node for every call, `AT_CREATE` not asked (a valueless node is left by tvv03-tvv06: no row counts the nodes)",
         file=TAB, targets=[TV],
         old="        rc, nid = trie_lookup_abstract(\n            ld, variants, 0, -(t + 1), (flags & AT_CREATE) != 0, sa, vars\n        )",
         new="        rc, nid = trie_lookup_abstract(\n            ld, variants, 0, -(t + 1), true, sa, vars\n        )",
         equivalent="DEFERRED KILL: owner TB5 (abolish empties the variant table and a node count is then read; TB1's own test could add the row, "
                    "`trie_property`-style node count of the variant table after tvv03): the node without a value answers `nothing` at src/pl-tabling.jl:738-739 "
                    "(`elseif (flags & AT_CREATE) != 0 ... else return nothing`), so tvv03-tvv06 still answer `no`, and the walk of tvl06/tvl07 (trie_gen over the "
                    "variant table) lists nodes with a value (to be confirmed by the first run: if tvl07 sees a valueless node, the declaration goes)"),
    # ── unify_trie_ret / ret_functor (pl-tabling.c) ──
    dict(id="TB1-T1 the skeleton's functor is `rec/N`, not `ret/N` (KILL tvv02 and tvs04: the pinned skeleton is `ret(V0)`)",
         file=TAB, targets=[TV],
         old="    return lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :ret)), arity)\n",
         new="    return lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :rec)), arity)\n"),
    dict(id="TB1-T2 unify_trie_ret does not unify the skeleton with `ret`, answers true (KILL tvv02: Sk stays unbound, pin `ret(V0)`; tvs04)",
         file=TAB, targets=[TV],
         old="    return PL_unify(ld, ret, w)\n",
         new="    return true\n"),
    dict(id="TB1-T3 unify_trie_ret puts the FIRST variable in every argument (no row has a call with two variables: every variable table of TV has one)",
         file=TAB, targets=[TV],
         old="        ld.gstack[p + i] = makeRefG(vp)\n",
         new="        ld.gstack[p + i] = makeRefG(vars[1])\n",
         equivalent="DEFERRED KILL: owner TB1's test (a tabled predicate of two arguments, `tv_r(X, Y)`: skeleton `ret(V0, V1)`, and `tv_r(X, X)`: `ret(V0)`): the loop at "
                    "src/pl-tabling.jl:632-634 runs once in every row of TV (`tv_p(_)` has one variable; the ground `tv_p(1)` has none and takes the `ret` atom, :744-746)"),
    # ── the status family (pl-tabling.c unify_fresh, complete_or_invalid_status, unify_table_status, table_status) ──
    dict(id="TB1-F1 unify_fresh (non-create) unifies `complete` (KILL tvs08: the status of the variant table is `fresh`; tvs08 is the row that reaches unify_fresh)",
         file=TAB, targets=[TV],
         old="    return PL_unify_atom(ld, t, mk_sym(T, :fresh))\n",
         new="    return PL_unify_atom(ld, t, mk_sym(T, :complete))\n"),
    dict(id="TB1-F2 complete_or_invalid_status answers `invalid` (KILL tvs01, tvs02, tvv01: the status of a complete table is `complete`)",
         file=TAB, targets=[TV],
         old='\n    return mk_sym(T, :complete)\n',
         new='\n    return mk_sym(T, :invalid)\n'),
    dict(id="TB1-F3 unify_complete_or_invalid answers a fresh status only without `create` (EQUIVALENT: the status is never `fresh`)",
         file=TAB, targets=[TV],
         old="    if sym_key(status) == sym_key(mk_sym(T, :fresh)) && create\n",
         new="    if sym_key(status) == sym_key(mk_sym(T, :fresh)) && !create\n",
         equivalent="src/pl-tabling.jl:775-779: complete_or_invalid_status returns `complete` (the IDG that makes `invalid` or `fresh` is refused by name, TB6, :776), so the first "
                    "conjunct `sym_key(status) == sym_key(:fresh)` of :787 is false for every table and the second is not read"),
    dict(id="TB1-F4 unify_table_status asks `TRIE_COMPLETE` unset (KILL tvs01, tvs02, tvv01: a complete table is answered `fresh`; tvs08: the variant table is answered `complete`)",
         file=TAB, targets=[TV],
         old="    if (atrie.flags & TRIE_COMPLETE) != 0\n        return unify_complete_or_invalid(ld, t, atrie, def, create)\n",
         new="    if (atrie.flags & TRIE_COMPLETE) == 0\n        return unify_complete_or_invalid(ld, t, atrie, def, create)\n"),
    dict(id="TB1-F5 unify_table_status answers a dynamic table `fresh` (no table is dynamic: nothing sets WL_DYNAMIC)",
         file=TAB, targets=[TV],
         old="            return PL_unify_atom(ld, t, mk_sym(T, :dynamic))\n        end\n\n        @assert wl",
         new="            return PL_unify_atom(ld, t, mk_sym(T, :fresh))\n        end\n\n        @assert wl",
         equivalent="DEFERRED KILL: owner TB6 (incremental and dynamic tabling, the step that ports the writer of `WL_DYNAMIC`; git grep -F WL_DYNAMIC at wip/tb1 6acfd472: "
                    "the constant (src/pl-tabling.jl:33), its three readers (:806, :824, :1115) and no writer): no table has `worklist == WL_DYNAMIC`, so the branch at :806 is "
                    "reached by no row; the owner adds a row of a dynamic table's status (and `$is_answer_trie` answering `dynamic`, :1115)"),
    dict(id="TB1-F6 table_status asks `TRIE_COMPLETE` unset (no caller before TB3)",
         file=TAB, targets=[TV],
         old="    if (atrie.flags & TRIE_COMPLETE) != 0\n        return complete_or_invalid_status(ld, atrie, false)\n",
         new="    if (atrie.flags & TRIE_COMPLETE) == 0\n        return complete_or_invalid_status(ld, atrie, false)\n",
         equivalent="DEFERRED KILL: owner TB3 (the first caller of `table_status`, pl-tabling.c `tbl_..` completion; git grep -F `table_status(` at wip/tb1 6acfd472: the "
                    "definition src/pl-tabling.jl:817 and `unify_table_status`/`$tbl_table_status` names only): row for TB3: `table_status(ld, atrie)` of a complete, a "
                    "fresh and an incomplete table"),
    # ── unify_skeleton (pl-tabling.c unify_skeleton) and `$tbl_table_status/4` ──
    dict(id="TB1-U1 unify_skeleton fails for a table with a variant node, `variant == 0` (KILL tvs03 and tvs04: `$tbl_table_status/4` fails, the pin has r(complete, user:tv_p(..), ret..))",
         file=TAB, targets=[TV],
         old="    if atrie.variant != 0\n        ok, _ = unify_trie_term(",
         new="    if atrie.variant == 0\n        ok, _ = unify_trie_term("),
    dict(id="TB1-U2 unify_skeleton asks the table's skeleton with no skeleton term, `0` for `skeleton` (KILL tvs03: the skeleton stays unbound, the pin is `ret`; tvs04 `ret(V0)`)",
         file=TAB, targets=[TV],
         old="return get_answer_table(ld, def, wrapper, skeleton, flags | AT_NOCLAIM) !==\n                   nothing",
         new="return get_answer_table(ld, def, wrapper, 0, flags | AT_NOCLAIM) !==\n                   nothing"),
    dict(id="TB1-U3 unify_skeleton always unifies a fresh wrapper, not the caller's (KILL tvs03 and tvs04: the caller's `wv` stays unbound, so the Wrapper argument is unbound, the pin is `user:tv_p(..)`)",
         file=TAB, targets=[TV],
         old="    wrapper == 0 && (wrapper = PL_new_term_ref(ld))\n",
         new="    wrapper = PL_new_term_ref(ld)\n"),
    dict(id="TB1-U4 `$tbl_table_status/4` does not unify its wrapper argument (KILL tvs03 and tvs04: the Wrapper argument stays unbound, the pin is `user:tv_p(..)`)",
         file=TAB, targets=[TV],
         old="unify_skeleton(ld, atrie, wv, A4) && PL_unify(ld, A3, wv)",
         new="unify_skeleton(ld, atrie, wv, A4) && true"),
    # ── the `$tbl_*` predicates over the variant tables ──
    dict(id="TB1-P1 `$tbl_global_variant_table/1` succeeds (KILL tvb02 and tvl02: the pin is `no`, there is no shared variant table)",
         file=TAB, targets=[TV],
         old="function pl_tbl_global_variant_table1_va(\n    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}\n)::foreign_t where {T}\n    return FFALSE\n",
         new="function pl_tbl_global_variant_table1_va(\n    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}\n)::foreign_t where {T}\n    return FTRUE\n"),
    dict(id="TB1-P2 `$tbl_local_variant_table/1` does not fail before the variant table exists (KILL tvb01: `gd.tries[0]`, BoundsError, the pin is `no`)",
         file=TAB, targets=[TV],
         old="function pl_tbl_local_variant_table1_va" + HDR1,
         new="function pl_tbl_local_variant_table1_va" + HDR1.replace("ld.tabling.variant_table == 0 && return FFALSE\n", "nothing\n")),
    dict(id="TB1-P3 `$tbl_variant_table/1` does not fail before the variant table exists (KILL tvb03: BoundsError, the pin is `no`)",
         file=TAB, targets=[TV],
         old="function pl_tbl_variant_table1_va" + HDR1,
         new="function pl_tbl_variant_table1_va" + HDR1.replace("ld.tabling.variant_table == 0 && return FFALSE\n", "nothing\n")),
    dict(id="TB1-P4 `$tbl_table_status/2` goes on with no trie (KILL tvs05 and tvs06: `get_trie` raised, atrie is `nothing`, the call reads it: MethodError instead of the pinned type_error / instantiation_error)",
         file=TAB, targets=[TV],
         old="    atrie === nothing && return FFALSE\n\n    return unify_table_status(ld, A2, atrie, nothing, false) ? FTRUE : FFALSE\n",
         new="    return unify_table_status(ld, A2, atrie, nothing, false) ? FTRUE : FFALSE\n"),
    dict(id="TB1-P5 `$tbl_table_status/2` asks for `create` (KILL tvs08 expected: the fresh variant table reaches unify_fresh(create), since TAB1 stack batch 3 item 9 a real call (`_unify_fresh_create`, TB2) that makes the worklist, where the pin answers `fresh` and creates nothing; CONFIRM at the gate, the refusal this row once relied on is gone)",
         file=TAB, targets=[TV],
         old="    return unify_table_status(ld, A2, atrie, nothing, false) ? FTRUE : FFALSE\n",
         new="    return unify_table_status(ld, A2, atrie, nothing, true) ? FTRUE : FFALSE\n"),
    dict(id="TB1-P7 `$tbl_variant_table/6` does not unify its Trie argument (no row calls /6, /abstract or /moded: the create path is a real call since batch 3 item 9, owner TB2)",
         file=TAB, targets=[TV],
         old="    return unify_trie(gd, ld, Trie, atrie) &&\n           unify_table_status(ld, status, atrie, def, true)\n",
         new="    return unify_table_status(ld, status, atrie, def, true)\n",
         equivalent="DEFERRED KILL: owner TB2 (start_tabling, boot/tabling.pl, the only caller of `$tbl_variant_table/6`, `$tbl_abstract_table/6` and `$tbl_moded_variant_table/6`): "
                    "no TV row calls the three (src/pl-tabling.jl:895-927; TV's tables are made white-box by `get_answer_table`, TV:343); a call that finds an EXISTING complete "
                    "table does not reach the refused create path: TB1's test could add it (rows with Closure = a `get_closure_predicate` of tv_p) or TB2 does"),
    dict(id="TB1-P8 `$tbl_table_pi/2` puts the arity plus one in the indicator (KILL tvp01 and tvp02: the pin is `user:tv_p/1`; tvp04)",
         file=TAB, targets=[TV],
         old="    PL_put_integer(ld, r + 1, arity)\n",
         new="    PL_put_integer(ld, r + 1, arity + 1)\n"),
    dict(id="TB1-P10 `$tbl_table_pi/2` goes on for a table with no variant node (no row: the variant table's own indicator has no pinned answer)",
         file=TAB, targets=[TV],
         old="    atrie.variant == 0 && return FFALSE\n\n    av = PL_new_term_refs(ld, 3)\n",
         new="    av = PL_new_term_refs(ld, 3)\n",
         equivalent="DEFERRED KILL: no owner step (the pin of swipl 10.1.20 gives no answer for `'$tbl_table_pi'(VT, _)` with VT the variant table, handoff3 left the row out: "
                    "pl-tabling.c reads a NULL `atrie->data.variant`); the only answer trie with `variant == 0` is a table whose variant node was released (TB5: "
                    "`release_variant_table_node` sets it, src/pl-tabling.jl:569-570): row for TB5 after an abolish that keeps the trie"),
    dict(id="TB1-P11 `$is_answer_trie/2` answers `dynamic` for a normal table (KILL tvt02: the pin is `normal`)",
         file=TAB, targets=[TV],
         old="            return PL_unify_atom(ld, A2, mk_sym(T, :normal)) ? FTRUE : FFALSE\n",
         new="            return PL_unify_atom(ld, A2, mk_sym(T, :dynamic)) ? FTRUE : FFALSE\n"),
    dict(id="TB1-P12 `$is_answer_trie/2` takes any trie for an answer trie, `== 0` (KILL tvt05: the variant table is no answer trie, the pin is `no`; tvt02: an answer trie is refused)",
         file=TAB, targets=[TV],
         old="    if atrie !== nothing && (atrie.flags & TRIE_ISTABLE) != 0\n",
         new="    if atrie !== nothing && (atrie.flags & TRIE_ISTABLE) == 0\n"),
    dict(id="TB1-P13 the registration of `$is_answer_trie` is for arity 3 (KILL tvt01-tvt06: the arity-2 predicate does not exist; TB:161 counts the foreign predicates)",
         file=TAB, targets=[TV, TB],
         old="PL_extension(\"\\$is_answer_trie\", 2, pl_is_answer_trie2_va, PL_FA_VARARGS)",
         new="PL_extension(\"\\$is_answer_trie\", 3, pl_is_answer_trie2_va, PL_FA_VARARGS)"),
    # ── tbl_implementation, is_tabled (pl-tabling.c) ──
    dict(id="TB1-I1 is_tabled reads the flag unset, `== 0` (KILL tvn01 and tvn02: a tabled predicate gets the permission_error; tvn03 does not)",
         file=TAB, targets=[TV, TM],
         old="is_tabled(def::Definition)::Bool =\n    def.tabling !== nothing && (def.tabling.flags & TP_TABLED) != 0\n",
         new="is_tabled(def::Definition)::Bool =\n    def.tabling !== nothing && (def.tabling.flags & TP_TABLED) == 0\n"),
    dict(id="TB1-I2 tbl_implementation answers the goal as given when the module differs, `!=` (KILL tvi04: `tv_p(_)` in user is answered qualified; the pin is plain `tv_p(V0)`)",
         file=TAB, targets=[TV],
         old="    if def.module_ == mi\n",
         new="    if def.module_ != mi\n"),
    dict(id="TB1-I3 tbl_implementation does not refuse a predicate that is not tabled, `is_tabled` for `!is_tabled` (KILL tvn01: a tabled predicate is refused, tvn03: a plain one is answered)",
         file=TAB, targets=[TV],
         old="    if must_be_tabled && !is_tabled(def)\n",
         new="    if must_be_tabled && is_tabled(def)\n"),
    dict(id="TB1-I4 tbl_implementation does not raise a type error for a non-callable (KILL tvi06 and tvn07: `1` is type_error(callable, 1); the dropped line reads `f[1]` of `nothing`)",
         file=TAB, targets=[TV],
         old="    f === nothing && return PL_type_error(ld, \"callable\", g0)\n",
         new="    nothing\n"),
    dict(id="TB1-I5 `$tnot_implementation/2` does not insist the predicate is tabled, `false` (KILL tvn03-tvn07: the pins are permission_error(tnot, non_tabled_procedure, ..))",
         file=TAB, targets=[TV],
         old="    return tbl_implementation(ld, PL__t0, PL__t0 + 1, true) ? FTRUE : FFALSE\n",
         new="    return tbl_implementation(ld, PL__t0, PL__t0 + 1, false) ? FTRUE : FFALSE\n"),
    # ── the node cache of start nodes (pl-tabling.c start_node_id, get_start_node, set_start_node): its user is TB3 ──
    dict(id="TB1-N2 set_start_node does not pin the node (no row reads the cache)",
         file=TAB, targets=[TV],
         old="    tr.nodes[nid].flags |= TN_PINNED\n",
         new="    nothing\n",
         equivalent="DEFERRED KILL: owner TB3 (as TB1-N3: the pin keeps an abolish from pruning a cached start node, TB5 reads it too): row `tr.nodes[nid].flags & TN_PINNED != 0` "
                    "after `set_start_node` (src/pl-tabling.jl:436-453); no TB1 row calls `set_start_node`"),
    dict(id="TB1-N3 set_start_node leaves the new entries as `resize!` made them, no `fill!` (no row reads the cache: the entries of a Vector{Int} grown by resize! are undefined)",
         file=TAB, targets=[TV],
         old="        fill!(view(a, (old + 1):Int(id)), 0)\n",
         new="        nothing\n",
         equivalent="DEFERRED KILL: owner TB3 (as TB1-N2): row for TB3: set_start_node(id = 5) in an empty cache, then `get_start_node(a, 3) == 0`, the entries between are 0 "
                    "(src/pl-tabling.jl:444-447)"),
    # ── reset_answer_table and the release functions (pl-tabling.c): called by the abolish (TB5) and the trie's release_node ──
    dict(id="TB1-L1 reset_answer_table leaves the table complete (no row calls it)",
         file=TAB, targets=[TV],
         old="    atrie.flags &= ~TRIE_COMPLETE\n\n    atrie.IDG === nothing || tbl_refuse(\n        T,\n        :reset_answer_table",
         new="    nothing\n\n    atrie.IDG === nothing || tbl_refuse(\n        T,\n        :reset_answer_table",
         equivalent="DEFERRED KILL: owner TB5 (abolish_all_tables: reset_answer_table is reached through `release_variant_table_node` from the trie's release_node, TR1's stack, "
                    "and TB5's abolish; src/pl-tabling.jl:537, :568): row for TB5: a complete table, then reset, then `TRIE_COMPLETE` is unset, `worklist === nothing`, no answers"),
    dict(id="TB1-L3 reset_answer_table's flags argument is read nowhere (EQUIVALENT: RAT_CLEANUP and 0 give the same reset)",
         file=TAB, targets=[TV],
         old="reset_answer_table(gd, atrie, variant_table.magic == TRIE_CMAGIC ? RAT_CLEANUP : 0)",
         new="reset_answer_table(gd, atrie, variant_table.magic == TRIE_CMAGIC ? 0 : RAT_CLEANUP)",
         equivalent="src/pl-tabling.jl:537-554: the body of reset_answer_table never reads its `flags` parameter (the RAT_CLEANUP, RAT_BULK paths of pl-tabling.c are the "
                    "worklist, IDG and tracked-table branches, refused by name here, :543-549), so the argument :568 passes does not change the result"),
    dict(id="TB1-L4 release_variant_table_node leaves the answer trie's variant link (no row calls it)",
         file=TAB, targets=[TV],
         old="        @assert atrie.variant == nid\n        atrie.variant = 0\n",
         new="        @assert atrie.variant == nid\n",
         equivalent="DEFERRED KILL: owner TB5 (as TB1-L1): row for TB5: release the variant node of a table, then `atrie.variant == 0` (src/pl-tabling.jl:559-574)"),
]
