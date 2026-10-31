# BOOTPRED: boot-needed predicates (audit D-0281) -- handoff

Worktree ~/code/lk-bootpred, branch wip/bootpred (off main faee65f). EDIT-ONLY writer: nothing here is compiled or run.
Pin: swipl-devel cbf4e1896275. Oracle: swipl 10.1.19.

## What the step is, as found upstream (corrections to the brief)
The brief's names are not the upstream functions; each is recorded here so the commit subjects cite the real ones.

| brief says | upstream (pin) | registration | kernel home |
|---|---|---|---|
| pl-dict.c's six | the six boot/init.pl calls (init.pl:1598, 3254, 4531-4610): `is_dict/1`, `is_dict/2`, `get_dict/3`, `select_dict/3`, `put_dict/3`, `dict_create/3` (loader_boot.md:209 "option processing"; boot_needs.tsv init.pl `pl-dict.c:6`). All PRED_IMPL in pl-dict.c's `BeginPredDefs(dict)` | PL_predicates_from_dict | NEW src/pl-dict.jl |
| thread_self/1 (pl-thread.c) | `pl_thread_self` pl-thread.c:2759-2763 -> `unify_thread_id` :2662-2672; FRG("thread_self", 1, pl_thread_self, ISO) pl-ext.c:186 | `foreigns` in src/pl-ext.jl | src/pl-thread.jl (existing, pl-thread.c) |
| with_mutex/2 (pl-thread.c) | `pl_with_mutex` is in **pl-mutex.c:758-773**, NOT pl-thread.c; FRG("with_mutex", 2, pl_with_mutex, META\|ISO) pl-ext.c:187; the meta declaration "+0" exists (pl-ext.jl:943, pl-ext.c:406) | `foreigns` | NEW src/pl-mutex.jl |
| garbage_collect/0 (pl-gc.c) | the C predicate is **`'$garbage_collect'/1`**, `pl_garbage_collect` pl-gc.c:4570-4584 (registered FRG pl-ext.c:168); `garbage_collect/0` is Prolog: boot/syspred.pl:1423-1424 `garbage_collect :- '$garbage_collect'(0).` (a loader/LB4 matter, not written here) | `foreigns` | src/pl-gc.jl (existing, pl-gc.c) |
| `'$style_check'/2` | NOT STARTED: waits for F1b (style flags). Nothing written. | | |

Recorded DIVERGES (single-thread forms; the upstream line is cited in each comment):
- thread_self/1: swipl answers `main` for the main thread (alias via `unify_thread_id`); the kernel has one thread, so it unifies `main`.
- with_mutex/2: upstream's own `#else` (no O_PLMT) branch pl-mutex.c:769-772 is `callProlog(NULL, goal, PL_Q_PASS_EXCEPTION, NULL)`; swipl 10.1.19 runs the O_PLMT branch (get_mutex + lock). The kernel takes the `#else` branch: with_mutex(M, G) is once(G); the mutex argument is not checked (get_mutex would raise on a bad mutex).
- `'$garbage_collect'/1`: no GC here (the kernel has no stack GC, src/pl-gc.jl header): true; upstream's `d` is read only under `#if O_DEBUG` (pl-gc.c:4573-4579), which swipl 10.1.19 release builds do not define, so the argument is not examined.

## Groups (commit order)
1. [x] handoff (this file) -- 38faa5d
2. [x] `'$garbage_collect'/1`: src/pl-gc.jl `pl_garbage_collect` -- b02d6a4
3. [x] thread_self/1: src/pl-thread.jl `pl_thread_self` -- e30b5ef
4. [x] with_mutex/2: NEW src/pl-mutex.jl `pl_with_mutex`, include after pl-pro.jl in src/LogicKernel.jl -- 04000d3
4b. [x] the three `foreigns` entries in src/pl-ext.jl (upstream order: `$garbage_collect` after context_module, thread_self and with_mutex last) -- 86a5ebf
4c. [x] rows bp01-bp26: test/core_lang/test_bootpred_swipl.jl (pinned, swipl 10.1.19, two runs byte-identical), evidence/BOOTPRED/{gen_rows.py,bootpred_driver.pl,bootpred_rows.pl,bootpred_rows.out} -- 8443f09
4d. [x] tools/mutants/BOOTPRED.py, 9 mutants for groups 2-4 (validated: old once, new != old, ids unique, targets exist) -- see git log
5. [x] pl-dict.c, NEW src/pl-dict.jl, sub-groups 5a (56cfd0c), include line (67f9cf5), 5b (ebf24af), 5c (ab07fcd), 5d (the commit carrying this handoff: select_dict, get_dict/3, `PL_predicates_from_dict`). Nothing compiled or run.
6. [ ] (HALF) the `PL_predicates_from_dict` table is in src/pl-dict.jl (6 entries, upstream order). STILL TO DO: add `PL_predicates_from_dict` at the END of `_PRED_TABLES` and `PL_predicates_from_dict...` at the END of `_FOREIGN_VA` in src/pl-ext.jl (pl-ext.c:536-574: `dict` follows attvar; gvar, locale and debug are left out of the kernel), and extend the comment above `_PRED_TABLES` ("... attvar — AV2, Y1; dict — BOOTPRED").
7. [ ] NOT STARTED: dict rows bp27+ (append cases to test/core_lang/test_bootpred_swipl.jl; regenerate with evidence/BOOTPRED/gen_rows.py; dicts built with dict_create/3 and put_dict/3 only; order-dependent answers compared SORTED, `timeout 20` on every swipl call, two byte-identical runs); dict mutants appended to tools/mutants/BOOTPRED.py (aim >= 6 from the dict code, every `old` once; ideas: dict_lookup_ptr `p < name` flip, put_dict `i_name < n_name` flip, put_dict unmodified-return, select_dict `d < f` return, unify_tags dyndict test, get_dict `i + 2 < arity` retry bound, PL_get_dict_ex Undo on duplicate, assign_in_dict `dp < q`; TARGETS = test_bootpred_swipl.jl and every test file that loads the table).
8. [ ] NOT STARTED: manifest block test/static_analysis_manifest.jl (APPENDED): entry points pl_garbage_collect, pl_thread_self, pl_with_mutex, pl_is_dict1_va, pl_is_dict2_va, pl_dict_create3_va, pl_put_dict3_va, pl_select_dict3_va, pl_get_dict3_va over T, and the `_enum_hash` entry `(Base.Enums._enum_hash, Tuple{LK._PL_dict_status_t, UInt64}, false)` (the new @enum in pl-dict.jl). 9. [ ] NOT STARTED: docs/architecture.md block (APPENDED, LAST).

### Dict sub-groups (upstream src/pl-dict.c at the pin, 2074 lines; `git -C ~/dev-zone/swipl-devel show cbf4e1896275:src/pl-dict.c > $SCRATCH/pl-dict.c.log`)
The six predicates and the helpers each pulls in (line numbers at the pin):
- 5a representation and is_dict: `dict_functor` :80, `is_dict_functor` :93, `is_dict_term` :104, `PL_is_dict` :837, `get_dict_ex` :120, `get_create_dict_ex` :148, `dict_lookup_ptr` :175 (binary search over the key/value pairs); PRED_IMPL `is_dict` 1 :1367, 2 :1377. FUNCTOR_dict is the reserved atom `dict` (pl-ressymbol.jl:108, `builtin_atom("dict")`): `lookupFunctorDef(ld.functors, builtin word of dict, 2n+1)`; check the neighbouring `lookupFunctorDef` call sites (pl-trace.jl:74) for the word of an atom.
- 5b ordering and creation: `dict_ordered` :219, `compare_dict_entry` :255, `dict_order` :267, `get_name_ex` :762, `get_name_value` :780, `PL_get_dict_ex` :866 (pairs from a list: Key-Value, Key=Value, Key:Value and Key(Value)), `dict_create` PRED_IMPL :1542. The key sort is by the key WORD (atom handle / tagged int); the kernel's words are not swipl's, so every order-dependent answer is compared sorted in the rows.
- 5c put_dict/3: `assign_in_dict` :343, `put_dict` :369 (merge two sorted runs), `copy_keys_dict` is NOT needed (put_dict/4 and dict_same_keys are outside the six); PRED_IMPL `put_dict` 3 :1673.
- 5d select_dict/3 and get_dict/3: `select_dict` :677 (+ `partial_unify_dict`/`unify_tags` :566-:633 as it calls them), PRED_IMPL select_dict :1853; get_dict/3 :1480 is NON-DETERMINISTIC (key unbound: enumerates the pairs; key bound: one lookup via `dict_lookup_ptr`) -- read :1400-:1495 and use the NDET convention of an existing non-deterministic PRED_DEF in the kernel (pl-list.jl or pl-proc.jl `retract/1`, NF2) -- `$get_dict_ex`/3 :1486 is outside the six but shares the code: port it only if the shared helper needs it.
Julia idiom for cells: src/pl-list.jl `extract_key_cells` (:262-295) and `skip_list_cells`: `ld.gstack`, `_deref_loc(ld, pos) -> (kind, word, pos)`, `valPtr(w)`, `_is_gcompound(w)`, `arityFunctor(ld.functors, ld.gstack[valPtr(w)])`, `makeRefG`, `ensureGlobalSpace(ld, n)`, `lookupFunctorDef`, `PL_unify`, `PL_error(ld, ERR_TYPE, …)`/`PL_type_error`. UNREAD by this writer: the word encoding of atoms and small integers per term type (`_atom_word!` pl-inline.jl:257, `isTaggedInt`) -- needed for the key comparison and for `type_error(dict-key, …)`.
Known upstream facts the rows rely on (swipl 10.1.19, to be re-queried): `is_dict(foo)` fails; `dict_create(D, Tag, [a-1, b=2, c:3, d(4)])`; a duplicate key raises `duplicate_key(Key)`; `put_dict(New, Dict, Out)` accepts a dict or a pair list as New; `select_dict(Sel, From, Rest)`.

## Findings for the audit
1. The brief's file for with_mutex/2 (pl-thread.c) and its name for the GC predicate (garbage_collect/0) differ from upstream: pl_with_mutex is in pl-mutex.c:758, the C predicate is `'$garbage_collect'/1` (pl-gc.c:4570, pl-ext.c:168); garbage_collect/0 is boot/syspred.pl:1423 (loaded with the boot tree, LB4). Commit subjects cite the real files.
2. with_mutex/2's kernel form is upstream's own non-O_PLMT branch (pl-mutex.c:769-772), but swipl 10.1.19 examines the mutex (`with_mutex(_, true)`: instantiation_error; `with_mutex(1.5, true)`: type_error(mutex, 1.5)); a behaviour difference, pinned in the test as a KNOWN DIFFERENCE (audit call).
3. The reader refuses dicts (pl-read.jl:3633, R1's decision) and the writer has no dict arm: dicts exist only through dict_create/3 and put_dict/3 until a later step; `print`/`write` of a dict shows the compound `dict(Tag, V, K, …)` (pl-write.jl not touched).

## Gate order at the end (for the dispatcher)
fmt (`warm.sh send` for committed files), inventory, check, rows on three term types, type discipline, pkgtest_way <file> one at a time, mutants branch
push, branch-gate, term grep, alloc pins x3 (pl-ext.jl changes), fresh-name gate push. Nothing has been run.

## Commits (hash, subject) -- updated after every group
38faa5d plan; b02d6a4 pl-gc.c pl_garbage_collect; e30b5ef pl-thread.c pl_thread_self; 04000d3 pl-mutex.c pl_with_mutex; 86a5ebf pl-ext.jl foreigns; 8443f09 rows bp01-bp26; BOOTPRED.py (9 mutants); then this handoff update.
Nothing is compiled or run. Branch wip/bootpred, never pushed.

## Dict port: design notes and UNVERIFIED items (coder 2; nothing is compiled)
- Layout as upstream: functor cell `dict`/(2N+1) at gstack[p]; tag at p+1; pair i (1-based) value at p+2i, key at p+2i+1; `arguments[k]` is position p+1+k. `ATOM_dict = builtin_atom("dict")`, `ATOM_dyndict = builtin_atom("dyndict")` (module consts in pl-dict.jl). Key order is by key WORD (kernel words), so enumeration order differs from swipl: sort every order-dependent row.
- Representation-only DIVERGES logged in comments: no dict_functors cache; dict_order sorts via `sortperm` and writes back; put_dict plans the merge and then allocates the exact size (upstream trims gTop); no Mark/Undo retry on overflow (ensureGlobalSpace raises); PL_get_dict_ex calls DiscardMark on success.
- New helpers in pl-dict.jl only (no shared file touched yet): `PL_duplicate_key_error` (own function, as `PL_existence_error3`, no ERR_DUPLICATE_KEY code), `_dict_link!` (linkValI of a location into a cell), `_dict_unify_key` (PL_unify_atomic for a key word).
- UNVERIFIED APIs (read at one site each, never compiled): `_PL_error_open`/`_PL_error_close!` 9-arg call as in PL_existence_error3; `PL_new_term_refs(ld, n)`; `PL_open_foreign_frame` returns 0 on failure; `PL_rewind_foreign_frame`; `bindConst(ld, q, w)` with a plain key word; `_value_word!(ld, w)` signature (pl-inline.jl ~:520); `Undo!` then `DiscardMark`; `sortperm` on `Vector{word}`; `mk_sym(T, :(=))`, `:(:)`, `:-`; `compareStandard_cells(ld, l1, l2, true) != 0` as upstream's `compareStandard(nv, in, true)`; `lengthList(ld, data, true)` raising for a partial list; JET may flag the Union uses of `d` and `keep`, and the unused `PL__ac`.
- Reader/writer: dicts are built only by dict_create/3 and put_dict/3; `print`/`write` show the compound `dict(Tag, V, K, ...)` (finding 3 above).
- Registered nowhere (outside the six): `$get_dict_ex/3` (pl_get_dict already takes `ex`), dict_pairs/3, put_dict/4, get_dict/5, del_dict/4, :</2, >:</2, b_set_dict etc.
- Context: coder 2 hit the 150k cap after 5d; the 5d commit carries this handoff because the cap hook allowed only a commit naming evidence/.
