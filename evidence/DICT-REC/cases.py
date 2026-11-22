# DICT-REC oracle rows: (group, goal) in order; mk_rows.py numbers them dr01.. and writes the test file's _DR_CASES.
# Dicts are built by dict_create/3 (the reader refuses dict syntax) and never appear in an answer: a row observes one through
# `dpairs/2` (get_dict/3 + msort) or a single lookup. Errors that carry the dict are caught inside the row.
# `bt/..` rows: trees are t(K,V,B,L,R) (assoc.pl's, Pos 0x010405) or n(K,L,R) (Pos 0x010203); a leaf is the atom `t` / `e`.
# NO row puts the key position one past the last argument (arity == kp): that one is a DIVERGES in src/pl-btree.jl.

GROUPS = []


def g(name, goals):
    GROUPS.append((name, goals))


T3 = "t(m,mv,<,t(f,fv,<,t,t),t(s,sv,<,t,t))"   # an AVL-shaped tree: root m, left f, right s
N3 = "n(5,n(2,e,e),n(8,e,e))"

g("b_set_dict/3", [
    "dict_create(D, t, [a-1, b-2]), b_set_dict(a, D, 9), dpairs(D, R)",
    "dict_create(D, t, [a-1, b-2]), b_set_dict(b, D, 9), dpairs(D, R)",
    "dict_create(D, t, [a-1, b-2]), ( b_set_dict(a, D, 9), fail ; dpairs(D, R) )",
    "dict_create(D, t, [a-1, b-2]), b_set_dict(a, D, 9), b_set_dict(b, D, 8), dpairs(D, R)",
    "dict_create(D, t, [a-1, b-2]), ( b_set_dict(a, D, 9), b_set_dict(b, D, 8), fail ; dpairs(D, R) )",
    "dict_create(D, t, [a-1, b-2]), catch(b_set_dict(c, D, 9), error(existence_error(T, K, _), _), R = ex(T, K))",
    "b_set_dict(a, foo, 9), R = yes",
    "b_set_dict(a, [a-1], 9), R = yes",
    "b_set_dict(a, _, 9), R = yes",
    "dict_create(D, t, [a-1]), b_set_dict(1.5, D, 9), R = yes",
    "dict_create(D, t, [a-1]), b_set_dict(_, D, 9), R = yes",
    "dict_create(D, t, [1-one, 2-two]), b_set_dict(2, D, 9), dpairs(D, R)",
    "dict_create(D, t, [a-1]), b_set_dict(a, D, f(X)), get_dict(a, D, f(Y)), X == Y, R = same",
    "dict_create(D, t, [a-1]), b_set_dict(a, D, f(X)), X = 3, get_dict(a, D, V), R = V",
    "dict_create(D, t, [a-X, b-2]), b_set_dict(a, D, 9), dpairs(D, P), R = X-P",
    "dict_create(D, t, [a-X, b-2]), ( b_set_dict(a, D, 9), fail ; get_dict(a, D, V), V == X, R = unbound_again )",
    "dict_create(D, t, [a-1]), b_set_dict(a, D, 9), put_dict(a, D, 7, N), dpairs(N, P), dpairs(D, Q), R = P-Q",
    "dict_create(D, t, [a-1, b-2]), b_set_dict(a, D, 1), dpairs(D, R)",
    "dict_create(D, t, [a-1]), b_set_dict(a, D, 9), get_dict(a, D, V), R = V",
])

g("nb_set_dict/3", [
    "dict_create(D, t, [a-1, b-2]), nb_set_dict(a, D, 9), dpairs(D, R)",
    "dict_create(D, t, [a-1, b-2]), nb_set_dict(b, D, 9), dpairs(D, R)",
    "dict_create(D, t, [a-1, b-2]), ( nb_set_dict(a, D, 9), fail ; dpairs(D, R) )",
    "dict_create(D, t, [a-1, b-2]), nb_set_dict(a, D, 9), nb_set_dict(b, D, 8), dpairs(D, R)",
    "dict_create(D, t, [a-1, b-2]), catch(nb_set_dict(c, D, 9), error(existence_error(T, K, _), _), R = ex(T, K))",
    "nb_set_dict(a, foo, 9), R = yes",
    "nb_set_dict(a, [a-1], 9), R = yes",
    "nb_set_dict(a, _, 9), R = yes",
    "dict_create(D, t, [a-1]), nb_set_dict(1.5, D, 9), R = yes",
    "dict_create(D, t, [a-1]), nb_set_dict(_, D, 9), R = yes",
    "dict_create(D, t, [1-one, 2-two]), nb_set_dict(2, D, 9), dpairs(D, R)",
    "dict_create(D, t, [a-1]), nb_set_dict(a, D, f(X)), get_dict(a, D, f(Y)), Y = 1, R = X",
    "dict_create(D, t, [a-1]), nb_set_dict(a, D, f(X)), get_dict(a, D, f(Y)), ( X == Y -> R = same ; R = copied )",
    "dict_create(D, t, [a-1]), ( nb_set_dict(a, D, f(x)), fail ; get_dict(a, D, V), R = V )",
    "dict_create(D, t, [a-1]), nb_set_dict(a, D, g(h(i))), get_dict(a, D, V), R = V",
    "dict_create(D, t, [a-1]), nb_set_dict(a, D, 9), put_dict(a, D, 7, N), dpairs(N, P), dpairs(D, Q), R = P-Q",
    "dict_create(D, t, [a-X]), nb_set_dict(a, D, 9), dpairs(D, P), R = X-P",
])

g("nb_link_dict/3", [
    "dict_create(D, t, [a-1, b-2]), nb_link_dict(a, D, 9), dpairs(D, R)",
    "dict_create(D, t, [a-1, b-2]), nb_link_dict(b, D, 9), dpairs(D, R)",
    "dict_create(D, t, [a-1, b-2]), ( nb_link_dict(a, D, 9), fail ; dpairs(D, R) )",
    "dict_create(D, t, [a-1, b-2]), catch(nb_link_dict(c, D, 9), error(existence_error(T, K, _), _), R = ex(T, K))",
    "nb_link_dict(a, foo, 9), R = yes",
    "nb_link_dict(a, [a-1], 9), R = yes",
    "nb_link_dict(a, _, 9), R = yes",
    "dict_create(D, t, [a-1]), nb_link_dict(1.5, D, 9), R = yes",
    "dict_create(D, t, [a-1]), nb_link_dict(_, D, 9), R = yes",
    "dict_create(D, t, [1-one, 2-two]), nb_link_dict(2, D, 9), dpairs(D, R)",
    "dict_create(D, t, [a-1]), nb_link_dict(a, D, f(X)), get_dict(a, D, f(Y)), Y = 1, R = X",
    "dict_create(D, t, [a-1]), nb_link_dict(a, D, f(X)), get_dict(a, D, f(Y)), ( X == Y -> R = same ; R = copied )",
    "dict_create(D, t, [a-1]), nb_link_dict(a, D, g(h(i))), get_dict(a, D, V), R = V",
    "dict_create(D, t, [a-1]), nb_link_dict(a, D, 9), put_dict(a, D, 7, N), dpairs(N, P), dpairs(D, Q), R = P-Q",
])

g("$btree_find_node/5", [
    f"'$btree_find_node'(m, {T3}, 0x010405, N, A), R = A-N",
    f"'$btree_find_node'(f, {T3}, 0x010405, N, A), R = A-N",
    f"'$btree_find_node'(s, {T3}, 0x010405, N, A), R = A-N",
    f"'$btree_find_node'(a, {T3}, 0x010405, N, A), R = A-N",
    f"'$btree_find_node'(z, {T3}, 0x010405, N, A), R = A-N",
    f"'$btree_find_node'(g, {T3}, 0x010405, N, A), R = A-N",
    f"'$btree_find_node'(r, {T3}, 0x010405, N, A), R = A-N",
    "'$btree_find_node'(k, t(k,v,<,t,t), 0x010405, N, A), R = A-N",
    "'$btree_find_node'(a, t(k,v,<,t,t), 0x010405, N, A), R = A-N",
    "'$btree_find_node'(z, t(k,v,<,t,t), 0x010405, N, A), R = A-N",
    "'$btree_find_node'(a, t(k,v,<,u(a),t), 0x010405, N, A), R = A-N",
    "'$btree_find_node'(a, t(k,v,<,t(a,b,c,d,e,f),t), 0x010405, N, A), R = A-N",
    "'$btree_find_node'(a, t(k,v,<,t(c,v,<,t,t),t), 0x010405, N, A), R = A-N",
    f"'$btree_find_node'(5, {N3}, 0x010203, N, A), R = A-N",
    f"'$btree_find_node'(2, {N3}, 0x010203, N, A), R = A-N",
    f"'$btree_find_node'(8, {N3}, 0x010203, N, A), R = A-N",
    f"'$btree_find_node'(1, {N3}, 0x010203, N, A), R = A-N",
    f"'$btree_find_node'(9, {N3}, 0x010203, N, A), R = A-N",
    f"'$btree_find_node'(3, {N3}, 0x010203, N, A), R = A-N",
    f"'$btree_find_node'(5, {N3}, 0x010203, n(5,L,Rt), A), R = A-L-Rt",
    f"'$btree_find_node'(2, {N3}, 0x010203, N, '='), R = N",
    f"'$btree_find_node'(2, {N3}, 0x010203, N, '<'), R = N",
    f"'$btree_find_node'(2, {N3}, 0x010203, foo, A), R = A",
    f"'$btree_find_node'(1, {N3}, 0x010203, n(2,e,e), A), R = A",
    f"'$btree_find_node'(1, {N3}, 0x010203, n(5,_,_), A), R = A",
    f"'$btree_find_node'(1, {N3}, 0x010203, N, '>'), R = N",
    f"'$btree_find_node'(1, {N3}, 0x010203, N, '<'), R = N",
    # the two other orders of the positions: key, then right/left swapped
    f"'$btree_find_node'(1, {N3}, 0x010302, N, A), R = A-N",
    f"'$btree_find_node'(9, {N3}, 0x010302, N, A), R = A-N",
    # key at argument 2: n(L,K,R)
    "'$btree_find_node'(5, n(n(2,e,e),5,n(8,e,e)), 0x020103, N, A), R = A-N",
    "'$btree_find_node'(1, m(a,3,b), 0x020103, N, A), R = A-N",
    # a Key that is not ground, compared in standard order
    "'$btree_find_node'(_, n(5,e,e), 0x010203, N, A), R = A-N",
    "'$btree_find_node'(f(x), n(5,e,e), 0x010203, N, A), R = A-N",
    "'$btree_find_node'(a, n(5,e,e), 0x010203, N, A), R = A-N",
    "'$btree_find_node'(1.5, n(5,e,e), 0x010203, N, A), R = A-N",
    # errors
    f"'$btree_find_node'(m, {T3}, foo, N, A), R = A-N",
    f"'$btree_find_node'(m, {T3}, -1, N, A), R = A-N",
    f"'$btree_find_node'(m, {T3}, 0, N, A), R = A-N",
    f"'$btree_find_node'(m, {T3}, _, N, A), R = A-N",
    f"'$btree_find_node'(m, {T3}, 1.5, N, A), R = A-N",
    "'$btree_find_node'(m, foo, 0x010405, N, A), R = A-N",
    "'$btree_find_node'(m, _, 0x010405, N, A), R = A-N",
    "'$btree_find_node'(m, 42, 0x010405, N, A), R = A-N",
    "'$btree_find_node'(m, t(a,b), 0x010405, N, A), R = A-N",
    "'$btree_find_node'(m, n(1,e,e), 0x010206, N, A), R = A-N",
    "'$btree_find_node'(m, n(1,e,e), 0x060203, N, A), R = A-N",
    "'$btree_find_node'(m, n(1,e,e), 0x010602, N, A), R = A-N",
    # a list is a '[|]'/2 tree: key at 1, no left (0x01 position 1 again), right = the tail; the search walks the spine
    "'$btree_find_node'(m, [a,b,c], 0x010102, N, A), R = A-N",
    "string_codes(S, [115]), '$btree_find_node'(m, S, 0x010203, N, A), R = A-N",
])

g("$needs_quotes/1", [
    "'$needs_quotes'('hello world'), R = yes",
    "'$needs_quotes'('A'), R = yes",
    "'$needs_quotes'('_x'), R = yes",
    "'$needs_quotes'(''), R = yes",
    "'$needs_quotes'(abc), R = yes",
    "'$needs_quotes'(a1), R = yes",
    "'$needs_quotes'(a_b), R = yes",
    "'$needs_quotes'(+), R = yes",
    "'$needs_quotes'(;), R = yes",
    "'$needs_quotes'(!), R = yes",
    "'$needs_quotes'(','), R = yes",
    "'$needs_quotes'('|'), R = yes",
    "'$needs_quotes'('a.b'), R = yes",
    "'$needs_quotes'('[]'), R = yes",
    "'$needs_quotes'([]), R = yes",
    "'$needs_quotes'({}), R = yes",
    "'$needs_quotes'('{}'), R = yes",
    "'$needs_quotes'(=..), R = yes",
    "'$needs_quotes'(\\+), R = yes",
    "'$needs_quotes'('1a'), R = yes",
    "'$needs_quotes'('\\n'), R = yes",
    "atom_codes(A, [233]), '$needs_quotes'(A), R = yes",
    "atom_codes(A, [201]), '$needs_quotes'(A), R = yes",
    "'$needs_quotes'(1), R = yes",
    "string_codes(S, [115]), '$needs_quotes'(S), R = yes",
    "'$needs_quotes'(f(x)), R = yes",
    "'$needs_quotes'(_), R = yes",
    "'$needs_quotes'([a]), R = yes",
    "'$needs_quotes'(1.5), R = yes",
])

g("the dict is checked before the key", [
    "b_set_dict(1.5, foo, 9), R = yes",
    "nb_set_dict(_, foo, 9), R = yes",
    "nb_link_dict(1.5, foo, 9), R = yes",
])
