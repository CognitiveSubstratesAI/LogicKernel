# ORIGINAL: AV1's mutant list — no swipl-devel counterpart.
# tools/mutants/AV1.py — the mutation battery of AV1 (the word layer of attributed variables; audit D-0122, condition 1:
# "the catch-all reads ASSERT a known kind ... mutation-proved"), run ONCE, in CI (.github/workflows/mutation.yml; locally:
# tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional
# `equivalent` and `targets`. One mutant per guard (the five catch-alls of the design's risk 1, and `_h_const_cell!`'s) and per
# decision: each new outcome, each `needsRef` link, the index key, the chain, `bindConst`'s dispatch and the canBind sites AV1
# converted. Killed by test/core_lang/test_attvar_words.jl, which builds attributed variables by hand.
# NOT LISTED: the VM's DREF_ATTVAR admissions (H_RFUNCTOR, H_RLIST, H_LIST_FF, S_LIST) — no attributed variable can reach a
# clause head before AV2's put_attr/3, so no test drives them until AV3's rows (hk08: head unification wakes); msort/2's
# `needsRef` (put_sort_list): sorting an attributed variable compares it, which waits for AV5.
# The `old` strings were written BEFORE `tools/warm.sh fmt`: re-check them after it (mutate_drive.py refuses a string that does
# not occur exactly once).
T = ["test/core_lang/test_attvar_words.jl"]
TARGETS = T                                         # the baseline's targets (mutate_ci.py plan reads TARGETS)
P = "src/pl-prims.jl"
W = "src/pl-wam.jl"
I = "src/pl-inline.jl"
X = "src/pl-index.jl"
F = "src/pl-fli.jl"
A = "src/pl-attvar.jl"
MUTANTS = [
    # ---- the dereferences: an attributed variable's own outcome, and the asserted catch-all
    dict(id="AV1-D1 _deref_loc reads an attributed variable as a value", file=P, targets=T,
         old='''        elseif isAttVar(c)                          # an attributed variable (AV1)
            return (DU_ATTVAR, c, p)
        else                                        # a value-table word, asserted (AV1)
            _is_vword(c) || throw(_cell_word_error(p, c))
            return (DU_VALUE, c, p)''',
         new='''        else                                        # a value-table word, asserted (AV1)
            return (DU_VALUE, c, p)'''),
    dict(id="AV1-D2 _deref_loc's catch-all takes any word for a value-table word", file=P, targets=T,
         old='''            _is_vword(c) || throw(_cell_word_error(p, c))
            return (DU_VALUE, c, p)''',
         new='''            return (DU_VALUE, c, p)'''),
    dict(id="AV1-D3 _argp_deref_word reads an attributed variable as a value", file=W, targets=T,
         old='''        elseif isAttVar(c)                          # an attributed variable (AV1)
            return (DREF_ATTVAR, word(p))''',
         new='''        elseif false
            return (DREF_ATTVAR, word(p))'''),
    dict(id="AV1-D4 _argp_deref_word's catch-all takes any word for a value", file=W, targets=T,
         old='''            _is_vword(c) || throw(_cell_word_error(p, c))
            return (DREF_TERM, word(0))''',
         new='''            return (DREF_TERM, word(0))'''),
    dict(id="AV1-D5 _argp_deref_word's slot branch takes any word for a value (D-0150 item 4)", file=W, targets=T,
         old='''            (w == SLOT_VALUE || _is_vword(w)) || throw(_slot_word_error(w))   # asserted (D-0150)
''',
         new=''''''),
    # ---- linkValI: by reference for needsRef, the asserted catch-all
    dict(id="AV1-L1 _cell_link! copies an attributed variable's word", file=I, targets=T,
         old='''            if needsRef(c)                      # unbound or attributed: a reference to its cell
                ld.gstack[p] = makeRefG(q)''',
         new='''            if isVar(c)                         # unbound or attributed: a reference to its cell
                ld.gstack[p] = makeRefG(q)'''),
    dict(id="AV1-L2 _cell_link!'s catch-all copies any word", file=I, targets=T,
         old='''                (isAtomW(c) || _is_gcompound(c) || isTaggedIntW(c) || _is_vword(c)) ||
                    throw(_cell_word_error(q, c))   # (a known kind, asserted: AV1)''',
         new='''                nothing'''),
    dict(id="AV1-L3 _slot_link! copies an attributed variable's word", file=I, targets=T,
         old='''            if needsRef(c)                      # unbound or attributed: a reference to its cell
                ld.slots[to] = makeRefG(p)''',
         new='''            if isVar(c)                         # unbound or attributed: a reference to its cell
                ld.slots[to] = makeRefG(p)'''),
    dict(id="AV1-L4 _slot_link!'s catch-all reads any word as a value-table word", file=I, targets=T,
         old='''            elseif !_is_vword(c)                    # no word of a known kind (AV1)
                throw(_cell_word_error(p, c))''',
         new='''            elseif false
                throw(_cell_word_error(p, c))'''),
    dict(id="AV1-L5 _slot_link_loc! copies an attributed variable's word", file=F, targets=T,
         old='''    if k == DU_CELL || k == DU_ATTVAR                   # needsRef(w)''',
         new='''    if k == DU_CELL                                     # needsRef(w)'''),
    dict(id="AV1-L6 =.. copies an attributed variable's word into the new compound", file=P, targets=T,
         old='''            ld.gstack[p + i] = if hk == DU_CELL || hk == DU_ATTVAR   # *p++ = needsRef(*h) ? makeRefG(h) : *h (AV1)''',
         new='''            ld.gstack[p + i] = if hk == DU_CELL     # *p++ = needsRef(*h) ? makeRefG(h) : *h (AV1)'''),
    # ---- indexing
    dict(id="AV1-X1 an attributed variable has no index key (falls to the unreachable error)", file=X, targets=T,
         old='''    k == DU_ATTVAR && return word(0)                        # TAG_ATTVAR: 0, a wildcard (AV1)
''',
         new=''),
    dict(id="AV1-X2 is_var does not take an attributed variable for a variable", file=X, targets=T,
         old='''    return k == DU_CELL || k == DU_ATTVAR                  # canBind(*p)''',
         new='''    return k == DU_CELL                                    # canBind(*p)'''),
    # ---- the chain: register_attvar, reclaim_attvars, Undo!, the frozen release
    dict(id="AV1-C1 register_attvar does not link to the previous attvar", file=I, targets=T,
         old='''        ld.gstack[gp] = makeRefG(ld.attvar_attvars) # *gp = makeRefG(LD->attvar.attvars)''',
         new='''        ld.gstack[gp] = word(0)                     # *gp = makeRefG(LD->attvar.attvars)'''),
    dict(id="AV1-C2 Undo! keeps the chain's links above the new top", file=I, targets=T,
         old='''    reclaim_attvars(ld, ngtop)                  # reclaim_attvars(ngtop) (AV1)
''',
         new=''),
    dict(id="AV1-C3 reclaim_attvars drops the link AT the new top too", file=W, targets=T,
         old='''    while ld.attvar_attvars > after                 # while ( LD->attvar.attvars >= after )''',
         new='''    while ld.attvar_attvars >= after && ld.attvar_attvars != 0   # while ( LD->attvar.attvars >= after )'''),
    dict(id="AV1-C4 the frozen release keeps the chain's links above its target", file=I, targets=T,
         old='''        reclaim_attvars(ld, target)                 # (the attvar chain with it, as Undo!: AV1)
''',
         new=''),
    # ---- bindConst and the canBind sites converted
    dict(id="AV1-B1 bindConst overwrites an attributed variable as varBindConst", file=A, targets=T,
         old='''    if isVar(ld.gstack[p])                          # if ( isVar(*p) )''',
         new='''    if true                                         # if ( isVar(*p) )'''),
    dict(id="AV1-B2 h_const (a location) does not bind an attributed variable", file=W, targets=T,
         old='''    if k == DU_CELL || k == DU_ATTVAR               # canBind(*k) (an attributed variable: AV1)''',
         new='''    if k == DU_CELL                                 # canBind(*k) (an attributed variable: AV1)'''),
    dict(id="AV1-B3 h_const (a cell) does not bind an attributed variable", file=W, targets=T,
         old='''        if needsRef(k)                                              # canBind(*k) (AV1: or attributed)''',
         new='''        if isVar(k)                                                 # canBind(*k) (AV1: or attributed)'''),
    dict(id="AV1-B4 h_const's catch-all takes any word for a value-table word", file=W, targets=T,
         old='''            _is_vword(k) || throw(_cell_word_error(p, k))           # asserted (AV1)''',
         new='''            nothing                                                 # asserted (AV1)'''),
    dict(id="AV1-B5 PL_unify_atomic does not bind an attributed variable", file=F, targets=T,
         old='''    if k == DU_CELL || k == DU_ATTVAR                       # canBind(*p) (an attributed variable: AV1)''',
         new='''    if k == DU_CELL                                         # canBind(*p) (an attributed variable: AV1)'''),
]
