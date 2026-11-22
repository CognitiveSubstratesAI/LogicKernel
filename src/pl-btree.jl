# UPSTREAM: swipl-devel src/pl-btree.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2004-2018, University of Amsterdam
#
# BTREE SUPPORT (pl-btree.c): `'$btree_find_node'/5`, the search library(assoc) runs on its AVL trees
# (library/assoc.pl, `put_assoc` and `get_assoc` when `current_predicate('$btree_find_node'/5)`). A tree is a term
# `t(Key, Value, Balance, Left, Right)` whose three positions the call names in one integer, `Pos = 256*256*KeyPos +
# 256*LeftPos + RightPos` (1-based argument numbers).

# PORT: pl-btree.c btree_find_node
# DIVERGES: the locations are the kernel's (a global position, `-(slot+1)` for a term reference); the node a search
# ends at is handed to `unify_ptrs_cells` as the cell that holds it, as upstream passes the `Word`. A position past the
# compound (the key, left or right position equal to the arity or more) is refused with a type error (bounds checking), so
# all three positions are guarded with `<=`; `compareStandard` returns only -1, 0, 1 in the kernel (no `CMP_ERROR`).
"`'\$btree_find_node'(+Key, +Tree, +Pos, -Node, -Arg)`: the (sub)node of `Tree` Key is at, `Arg` is `=`, `<` or `>` (pl-btree.c)."
function btree_find_node(
    ld::PL_local_data{T}, A1::term_t, A2::term_t, A3::term_t, A4::term_t, A5::term_t
)::Bool where {T}
    p = PL_cvt_i_uint(ld, A3)
    p === nothing && return false
    rp = (UInt32(p & 0xff) - UInt32(1))                     # (p       & 0xff)-1, an unsigned int
    lp = (UInt32((p >> 8) & 0xff) - UInt32(1))
    kp = (UInt32((p >> 16) & 0xff) - UInt32(1))

    kloc = -(A1 + 1)                                        # k = valTermRef(A1)
    k, w, _ = _deref_loc(ld, -(A2 + 1))                     # t = valTermRef(A2); deRef(t)
    if !(k == DU_WORD && _is_gcompound(w))                  # if ( !isTerm(*t) )
        return PL_error(ld, ERR_TYPE, mk_sym(T, :btree), A2)
    end
    fpos = valPtr(w)                                        # f = valueTerm(*t)
    fd = ld.gstack[fpos]                                    # fd = word2functor(f->definition)
    arity = arityFunctor(ld.functors, fd)
    if arity <= Int(kp) || arity <= Int(lp) || arity <= Int(rp)   # if ( arity < kp || arity < lp || arity < rp ); `<=`: bounds checking
        return PL_error(ld, ERR_TYPE, mk_sym(T, :btree), A2)
    end
    tloc = -(A2 + 1)                                        # t, the cell that holds the node

    while true
        d = compareStandard_cells(ld, kloc, fpos + 1 + Int(kp), false)   # compareStandard(k, &f->arguments[kp])
        if d == CMP_EQUAL
            return unify_ptrs_cells(ld, tloc, -(A4 + 1)) &&
                   PL_unify_atom(ld, A5, mk_sym(T, :(=)))   # ATOM_equals
        end

        smaller = d == CMP_LESS
        argpos = fpos + 1 + Int(smaller ? lp : rp)          # n = &f->arguments[arg]
        nk, nw, _ = _deref_loc(ld, argpos)                  # deRef(n)
        if !(nk == DU_WORD && _is_gcompound(nw)) || ld.gstack[valPtr(nw)] != fd   # !isTerm(*n) || f->definition != fd
            return unify_ptrs_cells(ld, tloc, -(A4 + 1)) &&   # nomatch:
                   PL_unify_atom(ld, A5, mk_sym(T, smaller ? :< : :>))   # ATOM_smaller : ATOM_larger
        end
        fpos = valPtr(nw)                                   # f = valueTerm(*n)
        tloc = argpos                                       # t = n
    end
end

# PORT: pl-btree.c btree_find_node as pl_btree_find_node5_va
# (PRED_IMPL("$btree_find_node", 5, btree_find_node, 0))
"`'\$btree_find_node'(+Key, +Tree, +Pos, -Node, -Arg)` (pl-btree.c)."
function pl_btree_find_node5_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return btree_find_node(
        ld, PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3, PL__t0 + 4
    ) ? FTRUE : FFALSE
end

# PORT: pl-btree.c BeginPredDefs as PL_predicates_from_btree
"pl-btree.c's registration table (`BeginPredDefs(btree)`)."
const PL_predicates_from_btree = (
    PL_extension("\$btree_find_node", 5, pl_btree_find_node5_va, PL_FA_VARARGS),
)
