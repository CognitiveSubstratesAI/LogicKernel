# ORIGINAL: AV2's mutant list — no swipl-devel counterpart.
# tools/mutants/AV2.py — the mutation battery of AV2 (the attribute store of attributed variables: pl-attvar.c's
# put_new_attvar, find_attr, put_att_value, put_attr, get_attr, del_attr, the eight predicates and the FLI), run ONCE,
# in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's. One mutant per
# trailed assignment, per list walk decision, per predicate branch and per error; killed by
# test/core_lang/test_attvar_store.jl (white-box, the rows.tsv rows, the live rows).
# NOT LISTED: `make_new_attvar`'s `gp[1] = ATOM_nil` — its one caller, put_attrs/2, overwrites the list cell at once,
# so no answer can see it (equivalent: src/pl-attvar.jl make_new_attvar, then pl_put_attrs2_va's `*vp = …`).
# The `old` strings were written BEFORE `tools/warm.sh fmt`: re-check them after it (mutate_drive.py refuses a string
# that does not occur exactly once).
T = ["test/core_lang/test_attvar_store.jl"]
TARGETS = T
A = "src/pl-attvar.jl"
P = "src/pl-prims.jl"
E = "src/pl-error.jl"
MUTANTS = [
    dict(id="AV2-P1 attvar/1 takes a plain variable for attributed", file=A, targets=T,
         old="    return k == DU_ATTVAR ? FTRUE : FFALSE                  # if ( isAttVar(*p) ) succeed: attvar/1",
         new="    return (k == DU_ATTVAR || k == DU_CELL) ? FTRUE : FFALSE"),
    dict(id="AV2-N1 put_new_attvar binds the variable untrailed", file=A, targets=T,
         old="    _bind_const!(ld, p, makeRefG(gp))                       # Trail(p, makeRefG(gp)): put_new_attvar",
         new="    ld.gstack[p] = makeRefG(gp)"),
    dict(id="AV2-N2 put_new_attvar copies the value word instead of linking it", file=A, targets=T,
         old="    ld.gstack[at + 3] = _link_val_loc!(ld, value)           # at[3] = linkValI(value)",
         new="    ld.gstack[at + 3] = value[2]"),
    dict(id="AV2-C1 the chain is not extended (link_attvar)", file=A, targets=T,
         old="    register_attvar(ld, gp)                                 # register_attvar(gp)",
         new="    nothing"),
    dict(id="AV2-F1 find_attr matches any name", file=A, targets=T,
         old="                if _deref_loc(ld, f + 1)[2] == name         #     deRef2(&f->arguments[0], n); if ( *n == name )",
         new="                if true"),
    dict(id="AV2-F2 find_attr reports no [] cell (NULL) at the list's end", file=A, targets=T,
         old="            return (false, l)                               #   *vp = l; return false",
         new="            return (false, 0)"),
    dict(id="AV2-R1 put_attr replaces untrailed", file=A, targets=T,
         old="        TrailAssignment!(ld, vp)                            #   TrailAssignment(vp): put_attr, replaced\n",
         new=""),
    dict(id="AV2-V1 put_att_value appends untrailed", file=A, targets=T,
         old="    TrailAssignment!(ld, vp)                                # TrailAssignment(vp): put_att_value\n",
         new=""),
    dict(id="AV2-G1 get_attr unifies the attribute's NAME", file=A, targets=T,
         old="                    return unify_ptrs_cells(ld, -(value + 1), f + 2)",
         new="                    return unify_ptrs_cells(ld, -(value + 1), f + 1)"),
    dict(id="AV2-D1 del_attr drops the rest of the list", file=A, targets=T,
         old="                    ld.gstack[prev] = ld.gstack[f + 3]      #       *prev = f->arguments[2]",
         new="                    ld.gstack[prev] = ld.atom_nil_w"),
    dict(id="AV2-D2 del_attr removes untrailed", file=A, targets=T,
         old="                    TrailAssignment!(ld, prev)              #       TrailAssignment(prev): del_attr\n",
         new=""),
    dict(id="AV2-D3 del_attr/2 keeps an attvar with no attributes", file=A, targets=T,
         old="                ld.gstack[av] = word(0)                     #       setVar(*av): del_attr/2",
         new="                nothing"),
    dict(id="AV2-D4 del_attrs/1 unbinds untrailed", file=A, targets=T,
         old="        TrailAssignment!(ld, av)                            #   TrailAssignment(av): del_attrs/1\n",
         new=""),
    dict(id="AV2-A1 put_attr/3 makes a NEW attvar of an attributed variable", file=A, targets=T,
         old="    if k == DU_CELL                                         # if ( isVar(*av) ): put_attr/3",
         new="    if k == DU_CELL || k == DU_ATTVAR"),
    dict(id="AV2-A2 put_attr/3's uninstantiation names the 2nd argument", file=A, targets=T,
         old='        return PL_error(ld, "put_attr", 3, "", ERR_UNINSTANTIATION, 1, A1) ? FTRUE : FFALSE',
         new='        return PL_error(ld, "put_attr", 3, "", ERR_UNINSTANTIATION, 2, A1) ? FTRUE : FFALSE'),
    dict(id="AV2-S1 put_attrs/2 drops the given list", file=A, targets=T,
         old="    ld.gstack[vp] = _link_val_loc!(ld, _deref_loc(ld, -(A2 + 1)))   # *vp = linkValI(valTermRef(A2))",
         new="    ld.gstack[vp] = ld.atom_nil_w"),
    dict(id="AV2-U1 $attv_unify/2 assigns untrailed", file=A, targets=T,
         old="        TrailAssignment!(ld, av)                            #   TrailAssignment(av): $attv_unify\n",
         new=""),
    dict(id="AV2-L1 PL_get_attr refers to the attvar cell, not its list", file=A, targets=T,
         old="        ld.slots[a + 1] = makeRefG(valPtr(w))               #   *valTermRef(a) = makeRefG(valPAttVar(*p))",
         new="        ld.slots[a + 1] = makeRefG(valPtr(w) - 1)"),
    dict(id="AV2-O1 unify_with_occurs_check skips an attributed variable's occurs test", file=P, targets=T,
         old="    if k1 == DU_CELL || k1 == DU_ATTVAR                 # canBind(*t1) (AV2: an attributed variable)",
         new="    if k1 == DU_CELL"),
    dict(id="AV2-O2 … and on the right", file=P, targets=T,
         old="    if k2 == DU_CELL || k2 == DU_ATTVAR                 # canBind(*t2) (AV2)",
         new="    if k2 == DU_CELL"),
    dict(id="AV2-U2 Var = Attvar copies the attvar word (no makeRefG)", file=P, targets=T,
         old="            _bind_const!(ld, p1, makeRefG(p2))      # Trail(t1, w2)",
         new="            _bind_const!(ld, p1, w2)"),
    dict(id="AV2-U3 Attvar = Var copies the attvar word (no makeRefG)", file=P, targets=T,
         old="            _bind_const!(ld, p2, makeRefG(p1))      # Trail(t2, w1)",
         new="            _bind_const!(ld, p2, w1)"),
    dict(id="AV2-U4 the same attvar against itself is refused (no t1 == t2)", file=P, targets=T,
         old="    (k1 == DU_ATTVAR && k2 == DU_ATTVAR && p1 == p2) && return BOOLEX_TRUE   # t1 == t2: the same attvar\n",
         new=""),
    dict(id="AV2-U5 Attvar = value fails silently instead of refusing (left)", file=P, targets=T,
         old="    k1 == DU_ATTVAR && throw(_bind_attvar_const_error(p1, w1))   # assignAttVar(t1, t2): AV3",
         new="    k1 == DU_ATTVAR && return BOOLEX_FALSE"),
    dict(id="AV2-U6 … (right)", file=P, targets=T,
         old="    k2 == DU_ATTVAR && throw(_bind_attvar_const_error(p2, w2))   # assignAttVar(t2, t1): AV3",
         new="    k2 == DU_ATTVAR && return BOOLEX_FALSE"),
    dict(id="AV2-U7 \\\\= takes an attributed variable for an atomic value (no full check)", file=P, targets=T,
         old="    elseif k1 == DU_ATTVAR || k2 == DU_ATTVAR           # isAttVar(w1) || isAttVar(w2): goto full_check\n",
         new=""),
    dict(id="AV2-E1 ERR_UNINSTANTIATION's argument text", file=E, targets=T,
         old='''        msg = "$argn-" * (
                  if argn == 1
                      "st"
                  elseif argn == 2
                      "nd"
                  else
                      "th"
                  end
              ) * " argument"''',
         new='        msg = "$argn argument"'),
]
