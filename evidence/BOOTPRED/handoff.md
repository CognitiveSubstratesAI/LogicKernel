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
1. [ ] handoff (this file)
2. [ ] `'$garbage_collect'/1`: pl-gc.jl block + `foreigns` entry in pl-ext.jl (small shared-file commit, after the function)
3. [ ] thread_self/1: pl-thread.jl block + `foreigns` entry
4. [ ] with_mutex/2: NEW src/pl-mutex.jl + include + `foreigns` entry
5. [ ] pl-dict.c: dict representation + six predicates, NEW src/pl-dict.jl (see DICT DESIGN below); PL_predicates_from_dict in `_PRED_TABLES` after attvar? (order: pl-ext.c REG_PLIST order, dict sits where upstream lists `dict`: check pl-ext.c:501-574 at the pin)
6. [ ] rows: evidence/BOOTPRED/gen_rows.py + driver + .out, test/core_lang/test_bootpred_swipl.jl
7. [ ] tools/mutants/BOOTPRED.py (>= 15), validated by a throwaway `python3 -I`
8. [ ] manifest entries (last-but-one), 9. [ ] docs/architecture.md block (last)

## DICT DESIGN (not started; to read before writing)
The kernel has NO dict support: the reader refuses `Tag{...}` (pl-read.jl:3633-3657, "R1's decision"), pl-list.jl extract_key has no dict arm, and
pl-ressymbol.jl reserves the atom `dict` as `FUNCTOR_dict`'s name. A dict is the compound `dict(Tag, V1, K1, V2, K2, ...)`, arity 2n+1, keys sorted by
their WORD value (upstream pl-dict.c: `dict_ordered`, `compareDictKeys`, `dict_lookup_ptr`, `PL_for_dict`). Open points for the writer of group 5:
- The sort order is by the key's cell word. The kernel's atom ids and the tagged-integer encoding are not swipl's, so any ORDER-dependent answer
  (get_dict/3 enumeration, dict_pairs) is compared SORTED in the rows (WRITER_RULES: unordered answers compare sorted).
- pl-dict.c is 2074 lines (`git -C ~/dev-zone/swipl-devel show cbf4e1896275:src/pl-dict.c`); the six pull in: `get_dict_ex`-free paths only
  `PRED_IMPL` bodies get_dict3, put_dict3, select_dict3, dict_create3, is_dict1/2 and their helpers (`get_name_ex`, `get_dict_ex`... `dict_order`,
  `PL_get_dict_ex`, `put_dict`, `dict_put`, `PL_put_dict`, `dict_lookup_ptr`, `termIsDict`). Cell-level access idiom: src/pl-list.jl
  `extract_key_cells` / `skip_list_cells` (ld.gstack, `_deref_loc`, `valPtr`, `_is_gcompound`, `lookupFunctorDef`).
- No dict syntax: the rows build dicts with dict_create/3 / put_dict/3 only, and print them with dict_pairs-free means (is_dict + get_dict).
- get_dict/3 with an unbound key is NON-DETERMINISTIC upstream (`CTX_CNTRL`): needs the NDET registration convention of the PL_predicates tables.

## Gate order at the end (for the dispatcher)
fmt (`warm.sh send` for committed files), inventory, check, rows on three term types, type discipline, pkgtest_way <file> one at a time, mutants branch
push, branch-gate, term grep, alloc pins x3 (pl-ext.jl changes), fresh-name gate push. Nothing has been run.

## Commits (hash, subject) -- updated after every group
(none yet)
