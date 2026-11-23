# ORIGINAL: G1-P's mutant list (is_pointer_like and its caller markPredicatesInEnvironments, pl-gc.c at swipl-devel 18168e62); the list itself is the kernel's own.
# tools/mutants/G1P.py — the mutation battery of G1-P: `is_pointer_like` (src/pl-gc.jl: the Int method = pl-gc.c:5871-5881, the NULL/Definition method) and its
# one call site in `markPredicatesInEnvironments!` (pl-gc.c:5915). NOTHING was run when this list was drafted: the kills are read off the rows of
# test/core_lang/test_gc_pointer_like.jl, the CI battery is the verdict. Run ONCE, in CI (.github/workflows/mutation.yml).
# Format: tools/mutate_drive.py's (as G1GCB.py): `id`, `file`, `old` (must occur EXACTLY once), `new`.
# Each id names its KILL by the rows of the new test:
#   INT  = the testset "is_pointer_like(::Int): the C expression" (hand-written rows from the C expression; swipl cannot call a static inline)
#   NULL = the testset "is_pointer_like(::Union{Nothing, Definition})"
#   WALK = the testset "markPredicatesInEnvironments! calls is_pointer_like on every frame's predicate": rows (a) dirty predicate records, (b) NULL
#          predicate does not throw and records nothing, (c) restored
# TARGETS (audit D-0238): `markPredicatesInEnvironments!` is reached by `pl_garbage_collect_clauses!` (src/pl-proc.jl), called by the tests through
# `garbage_collect_clauses/0` or `ix_gc!` (test/db/index_testlib.jl): test_index_swipl.jl, test_jit.jl, test_update_view_gc.jl, test/foreign/test_query.jl
# (the frame scan keeps d(2)), test_pr1_swipl.jl, test_event_swipl.jl, test_sys_swipl.jl (with test_sys_swipl.pl). A survivor of the new file alone proves
# nothing about the frame scan: those files see its effect on the erased clauses.
# NOT A MUTANT: the 32-bit mask `0x3` (the `#if SIZEOF_VOIDP == 4` arm) is not compiled on a 64-bit word: EQUIVALENT by the `@static`.
# Every `old` is counted EXACTLY once in its file by `python3 -I ~/code/lk-t27-scratch/oldscan.py G1P` from the repository root.
NEW = "test/core_lang/test_gc_pointer_like.jl"
TARGETS = [
    NEW,
    "test/db/test_index_swipl.jl",
    "test/db/test_jit.jl",
    "test/db/test_update_view_gc.jl",
    "test/foreign/test_query.jl",
    "test/core_lang/test_pr1_swipl.jl",
    "test/core_lang/test_event_swipl.jl",
    "test/core_lang/test_sys_swipl.jl",
]
GC = "src/pl-gc.jl"

def m(id, file, old, new):
    return dict(id=id, file=file, old=old, new=new, targets=TARGETS)

MUTANTS = [
    m("G1P-M1 mask 0x7 -> 0x3 (KILL INT: 12 and 4 are not pointer-like on a 64-bit word)",
      GC,
      "        0x7                                         # `#elif SIZEOF_VOIDP == 8`",
      "        0x3                                         # `#elif SIZEOF_VOIDP == 8`"),
    m("G1P-M2 NULL arm inverted: `ptr == 0 &&` (KILL INT: 0 and every aligned value)",
      GC,
      "    return ptr != 0 && (ptr & mask) == 0",
      "    return ptr == 0 && (ptr & mask) == 0"),
    m("G1P-M3 alignment arm inverted: `!= 0` (KILL INT: 8, 16, -8 are false; 1, 7 true)",
      GC,
      "    return ptr != 0 && (ptr & mask) == 0",
      "    return ptr != 0 && (ptr & mask) != 0"),
    m("G1P-M4 the NULL arm dropped (KILL INT: 0 is false)",
      GC,
      "    return ptr != 0 && (ptr & mask) == 0",
      "    return (ptr & mask) == 0"),
    m("G1P-M5 the alignment arm dropped (KILL INT: 1, 7, 9 are false)",
      GC,
      "    return ptr != 0 && (ptr & mask) == 0",
      "    return ptr != 0"),
    m("G1P-N1 Nothing method inverted: `=== nothing` (KILL NULL: nothing is false, a Definition true; WALK (a): nothing recorded)",
      GC,
      "is_pointer_like(ptr::Union{Nothing, Definition})::Bool = ptr !== nothing",
      "is_pointer_like(ptr::Union{Nothing, Definition})::Bool = ptr === nothing"),
    m("G1P-N2 Nothing method always true (KILL NULL: nothing is false; WALK (b): the NULL frame throws on `def::Definition`)",
      GC,
      "is_pointer_like(ptr::Union{Nothing, Definition})::Bool = ptr !== nothing",
      "is_pointer_like(ptr::Union{Nothing, Definition})::Bool = true"),
    m("G1P-W1 the walk does not call is_pointer_like (KILL WALK (b): the NULL frame throws on `def::Definition{T}`)",
      GC,
      "ddi = if is_pointer_like(def)\n                get(gd.procedures_dirty, def::Definition{T}, nothing)",
      "ddi = if true\n                get(gd.procedures_dirty, def::Definition{T}, nothing)"),
    m("G1P-W2 the walk calls the negation (KILL WALK (a): nothing recorded for a dirty predicate, (b): the NULL frame throws)",
      GC,
      "ddi = if is_pointer_like(def)\n                get(gd.procedures_dirty, def::Definition{T}, nothing)",
      "ddi = if !is_pointer_like(def)\n                get(gd.procedures_dirty, def::Definition{T}, nothing)"),
    m("G1P-W3 the walk records a wrong generation (KILL WALK (a): the frame's generation is not in the record)",
      GC,
      "                gen = generationFrame(fr)\n                ddi_add_access_gen!(ddi, gen)\n            end\n        end\n    end\n\n    markAccessedPredicates!(ld, gd)",
      "                gen = generationFrame(fr) + one(gen_t)\n                ddi_add_access_gen!(ddi, gen)\n            end\n        end\n    end\n\n    markAccessedPredicates!(ld, gd)"),
]
