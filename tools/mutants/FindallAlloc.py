# ORIGINAL: the findall/bagof allocation step's mutant list — no swipl-devel counterpart.
# tools/mutants/FindallAlloc.py — the mutation battery of the step that takes sync-2's +2 allocations per
# findall/3 and bagof/3 call away (audit D-0140; A-0091 item 4): the fast path's context record reused, `sym_first_byte`, the term interface's
# first byte of a symbol's text read in place, and call_internal_det_foreign's name test through it (pl-wam.c
# `stringAtom(def->functor->name)[0] == '$'` @ cbf4e189). Run ONCE, in CI (.github/workflows/mutation.yml;
# locally: tools/mutate.sh run). The format is tools/mutate_drive.py's.
#
# NOT MUTATED: AltTerm's `sym_first_byte` (test/core_lang/alt_term.jl) — the battery judges on the reference
# type (MUTATE_IMPL); its mutants are killed by test/core_lang/test_term_interface.jl on `alt` and
# `alt_interned`, hand-run before the gate (the conformance block's '' and 'é' cases).
ZERO = ["test/core_lang/test_zero_exports.jl"]
CONF = ["test/core_lang/test_term_interface.jl"]
CLEAN = ["test/core_lang/test_cleanup_swipl.jl"]
W = "src/pl-wam.jl"
D = "src/default_term.jl"
MUTANTS = [
    dict(id="FA1 the fast path's name test builds a String again (the pin: +1 per findall/bagof)", file=W,
         targets=ZERO,
         old='''        sym_first_byte(def.name) == UInt8('$')       # stringAtom(def->functor->name)[0] == '$\'''',
         new='''        startswith(sym_text(def.name), '$')       # stringAtom(def->functor->name)[0] == '$\''''),
    dict(id="FA2 sym_first_byte reads the second byte", file=D, targets=CONF + CLEAN,
         old='''    return GC.@preserve s unsafe_load(Base.unsafe_convert(Ptr{UInt8}, s))''',
         new='''    return GC.@preserve s unsafe_load(Base.unsafe_convert(Ptr{UInt8}, s), 2)'''),
    dict(id="FA3 the fast path tests another first byte (k39-k48: the contexts move back)", file=W,
         targets=CLEAN,
         old='''        sym_first_byte(def.name) == UInt8('$')       # stringAtom(def->functor->name)[0] == '$\'''',
         new='''        sym_first_byte(def.name) == UInt8('#')       # stringAtom(def->functor->name)[0] == '$\''''),
    dict(id="FA4 the fast path makes a new context record per call again (the pin: +1 per findall/bagof)", file=W,
         targets=ZERO,
         old='''        ctx = ld.queries[ld.query].fndet_context''',
         new='''        ctx = foreign_context{T}(FRG_FIRST_CALL, UInt(0), def)'''),
]
