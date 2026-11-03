# RDDICT gate agent 3 (Sonnet) - state file
Lane clone ~/code/lk-dict, branch gate/rddict at cbff230 + uncommitted working tree (the D-0390 fix). Every warm.sh call needs LOGICKERNEL_WARM_SECOND=1.

## Done (uncommitted edits)
- src/pl-dict.jl: pl_for_dict(ld, dict, func::F, closure::C, flags)::Int where {F, C} calls func(av+0, av+1, closure, i == pairs); struct PutPairClosure{T}; plain function put_pair_cb(key, value, ::PutPairClosure, ::Bool); call site in pl_dict_pairs3_va passes put_pair_cb and PutPairClosure(ld, head, tail, tmp). PutPairFn is gone.
- test/static_analysis_manifest.jl: (LK.pl_for_dict, Tuple{LD, Int, typeof(LK.put_pair_cb), LK.PutPairClosure{T}, Int}, false) and (LK.put_pair_cb, Tuple{Int, Int, LK.PutPairClosure{T}, Bool}, false).
- docs/architecture.md: the pre-existing wording about the set_prolog_flag var_tag arm reworded to "left out until F1b" (no allow marker used).
- tools/mutants/DICT.py: line 17 crash-term comment reworded; DICT-D1/D2 anchors re-fitted to the fmt-wrapped sort! lines in pl_dict_sort_indexes (they matched 0 times after agent 2's fmt: a stale anchor on main's DICT.py). Anchor checker (python3 -I, every old exactly once, TARGETS real test files): RDDICT 52/0 bad, DICT 25/0 bad.
