# DICT handoff (R2b, D-0290 item 1; Q10 writer flag 1) — branch wip/dict off origin/main 1286e62

## Verified missing on main (src/pl-dict.jl PL_predicates_from_dict registers only is_dict/1,2, dict_create/3,
## put_dict/3, get_dict/3, select_dict/3; its header comment lists the rest as NOT PORTED)
C-defined in pl-dict.c at the pin (cbf4e1896275, BeginPredDefs at pl-dict.c:2053), missing on main:
- called by boot files (boot_needs.tsv row boot/dicts.pl: `$get_dict_ex/3`, `get_dict/5`; grep of boot/*.pl at the pin):
  `$get_dict_ex/3` (dicts.pl:47,54), `get_dict/5` (dicts.pl, put_dict_path), `put_dict/4` (dicts.pl:95,113),
  `dict_pairs/3` (topvars.pl:230), `:</2` (init.pl:4554, autoload.pl:889, messages.pl:1888), `>:</2` (expand.pl:486)
- called by library/dicts.pl (same C file, the brief names them): `del_dict/4`, `dict_same_keys/2`, `$get_dict_kv/4,6,8`
- rest of the pl-dict.c table, no boot caller: `b_set_dict/3`, `nb_set_dict/3`, `nb_link_dict/3` (last group, optional;
  they assign into the dict cell with trail / copy: Tier-1-adjacent, see flags)
Defined by boot/dicts.pl in Prolog (not ours, LB4): `./3`, `eval_dict_function`, `get_dict_path`, `put_dict_path`,
`.put/1,2`, `.get/1,2`, and the dict-function expansion.
Also not ours: `is_most_general_dict`, `PL_for_dict` (C-only, no predicate), the reader's `Tag{...}` syntax and the
writer's dict arm (pl-read/pl-write: other owners).

## Plan (Julia site: append to src/pl-dict.jl, register in `PL_predicates_from_dict`; upstream pl-dict.c at the pin)
1. `$get_dict_ex/3` + `get_dict/5` — pl-dict.c:1486 (get_dict_ex pred), :1495 (get_dict/5); reuses pl_get_dict. ~1 commit
2. `put_dict/4` — :1746 (put_dict_ex helper path through put_dict/3's merge). ~1 commit
3. `dict_pairs/3` — :1580 (+ PL_for_dict / dict_get_pairs helpers, DICT_GET_* already on main). ~1-2 commits
4. `del_dict/4` — :1813. ~1 commit
5. `:</2`, `>:</2` — :1888 (unify_left_dict), :1917 (punify_dict). ~2 commits
6. `dict_same_keys/2`, `$get_dict_kv/4,6,8` — :1639, :2003-2017. ~1-2 commits
7. (optional) `b_set_dict/3`, `nb_set_dict/3`, `nb_link_dict/3` — :1785-1799. ~1 commit
8. Oracle rows test/core_lang/test_dict_*_swipl.jl (generator + driver + .out via swipl 10.1.19), per group. ~2-3 commits
9. tools/mutants/DICT.py (~2.5 per code commit, ~20-25 mutants). 1 commit
10. docs (docs/architecture.md appended block) LAST, manifest LAST. 2 commits
Estimate: ~14-17 commits, one stack (no split needed unless group 7 and rows grow).

## State
(nothing written yet beyond this plan)

## Flags for the audit / Tier-1 contact
(none yet)

## Gate order for the step (after the writer): fmt (via warm.sh send of committed files), inventory, check, rows on all
## three term types, test_type_discipline, pkgtest_way, mutants branch, branch-gate, term grep, gate push on a fresh name.
