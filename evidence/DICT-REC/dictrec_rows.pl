dpairs(D, Ps) :- findall(K-V, get_dict(K, D, V), Ps0), msort(Ps0, Ps).
t_dr01(R) :- catch((dict_create(D, t, [a-1, b-2]), b_set_dict(a, D, 9), dpairs(D, R)), error(SsuE, _), R = raised(SsuE)).
t_dr02(R) :- catch((dict_create(D, t, [a-1, b-2]), b_set_dict(b, D, 9), dpairs(D, R)), error(SsuE, _), R = raised(SsuE)).
t_dr03(R) :- catch((dict_create(D, t, [a-1, b-2]), ( b_set_dict(a, D, 9), fail ; dpairs(D, R) )), error(SsuE, _), R = raised(SsuE)).
t_dr04(R) :- catch((dict_create(D, t, [a-1, b-2]), b_set_dict(a, D, 9), b_set_dict(b, D, 8), dpairs(D, R)), error(SsuE, _), R = raised(SsuE)).
t_dr05(R) :- catch((dict_create(D, t, [a-1, b-2]), ( b_set_dict(a, D, 9), b_set_dict(b, D, 8), fail ; dpairs(D, R) )), error(SsuE, _), R = raised(SsuE)).
t_dr06(R) :- catch((dict_create(D, t, [a-1, b-2]), catch(b_set_dict(c, D, 9), error(existence_error(T, K, _), _), R = ex(T, K))), error(SsuE, _), R = raised(SsuE)).
t_dr07(R) :- catch((b_set_dict(a, foo, 9), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr08(R) :- catch((b_set_dict(a, [a-1], 9), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr09(R) :- catch((b_set_dict(a, _, 9), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr10(R) :- catch((dict_create(D, t, [a-1]), b_set_dict(1.5, D, 9), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr11(R) :- catch((dict_create(D, t, [a-1]), b_set_dict(_, D, 9), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr12(R) :- catch((dict_create(D, t, [1-one, 2-two]), b_set_dict(2, D, 9), dpairs(D, R)), error(SsuE, _), R = raised(SsuE)).
t_dr13(R) :- catch((dict_create(D, t, [a-1]), b_set_dict(a, D, f(X)), get_dict(a, D, f(Y)), X == Y, R = same), error(SsuE, _), R = raised(SsuE)).
t_dr14(R) :- catch((dict_create(D, t, [a-1]), b_set_dict(a, D, f(X)), X = 3, get_dict(a, D, V), R = V), error(SsuE, _), R = raised(SsuE)).
t_dr15(R) :- catch((dict_create(D, t, [a-X, b-2]), b_set_dict(a, D, 9), dpairs(D, P), R = X-P), error(SsuE, _), R = raised(SsuE)).
t_dr16(R) :- catch((dict_create(D, t, [a-X, b-2]), ( b_set_dict(a, D, 9), fail ; get_dict(a, D, V), V == X, R = unbound_again )), error(SsuE, _), R = raised(SsuE)).
t_dr17(R) :- catch((dict_create(D, t, [a-1]), b_set_dict(a, D, 9), put_dict(a, D, 7, N), dpairs(N, P), dpairs(D, Q), R = P-Q), error(SsuE, _), R = raised(SsuE)).
t_dr18(R) :- catch((dict_create(D, t, [a-1, b-2]), b_set_dict(a, D, 1), dpairs(D, R)), error(SsuE, _), R = raised(SsuE)).
t_dr19(R) :- catch((dict_create(D, t, [a-1]), b_set_dict(a, D, 9), get_dict(a, D, V), R = V), error(SsuE, _), R = raised(SsuE)).
t_dr20(R) :- catch((dict_create(D, t, [a-1, b-2]), nb_set_dict(a, D, 9), dpairs(D, R)), error(SsuE, _), R = raised(SsuE)).
t_dr21(R) :- catch((dict_create(D, t, [a-1, b-2]), nb_set_dict(b, D, 9), dpairs(D, R)), error(SsuE, _), R = raised(SsuE)).
t_dr22(R) :- catch((dict_create(D, t, [a-1, b-2]), ( nb_set_dict(a, D, 9), fail ; dpairs(D, R) )), error(SsuE, _), R = raised(SsuE)).
t_dr23(R) :- catch((dict_create(D, t, [a-1, b-2]), nb_set_dict(a, D, 9), nb_set_dict(b, D, 8), dpairs(D, R)), error(SsuE, _), R = raised(SsuE)).
t_dr24(R) :- catch((dict_create(D, t, [a-1, b-2]), catch(nb_set_dict(c, D, 9), error(existence_error(T, K, _), _), R = ex(T, K))), error(SsuE, _), R = raised(SsuE)).
t_dr25(R) :- catch((nb_set_dict(a, foo, 9), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr26(R) :- catch((nb_set_dict(a, [a-1], 9), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr27(R) :- catch((nb_set_dict(a, _, 9), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr28(R) :- catch((dict_create(D, t, [a-1]), nb_set_dict(1.5, D, 9), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr29(R) :- catch((dict_create(D, t, [a-1]), nb_set_dict(_, D, 9), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr30(R) :- catch((dict_create(D, t, [1-one, 2-two]), nb_set_dict(2, D, 9), dpairs(D, R)), error(SsuE, _), R = raised(SsuE)).
t_dr31(R) :- catch((dict_create(D, t, [a-1]), nb_set_dict(a, D, f(X)), get_dict(a, D, f(Y)), Y = 1, R = X), error(SsuE, _), R = raised(SsuE)).
t_dr32(R) :- catch((dict_create(D, t, [a-1]), nb_set_dict(a, D, f(X)), get_dict(a, D, f(Y)), ( X == Y -> R = same ; R = copied )), error(SsuE, _), R = raised(SsuE)).
t_dr33(R) :- catch((dict_create(D, t, [a-1]), ( nb_set_dict(a, D, f(x)), fail ; get_dict(a, D, V), R = V )), error(SsuE, _), R = raised(SsuE)).
t_dr34(R) :- catch((dict_create(D, t, [a-1]), nb_set_dict(a, D, g(h(i))), get_dict(a, D, V), R = V), error(SsuE, _), R = raised(SsuE)).
t_dr35(R) :- catch((dict_create(D, t, [a-1]), nb_set_dict(a, D, 9), put_dict(a, D, 7, N), dpairs(N, P), dpairs(D, Q), R = P-Q), error(SsuE, _), R = raised(SsuE)).
t_dr36(R) :- catch((dict_create(D, t, [a-X]), nb_set_dict(a, D, 9), dpairs(D, P), R = X-P), error(SsuE, _), R = raised(SsuE)).
t_dr37(R) :- catch((dict_create(D, t, [a-1, b-2]), nb_link_dict(a, D, 9), dpairs(D, R)), error(SsuE, _), R = raised(SsuE)).
t_dr38(R) :- catch((dict_create(D, t, [a-1, b-2]), nb_link_dict(b, D, 9), dpairs(D, R)), error(SsuE, _), R = raised(SsuE)).
t_dr39(R) :- catch((dict_create(D, t, [a-1, b-2]), ( nb_link_dict(a, D, 9), fail ; dpairs(D, R) )), error(SsuE, _), R = raised(SsuE)).
t_dr40(R) :- catch((dict_create(D, t, [a-1, b-2]), catch(nb_link_dict(c, D, 9), error(existence_error(T, K, _), _), R = ex(T, K))), error(SsuE, _), R = raised(SsuE)).
t_dr41(R) :- catch((nb_link_dict(a, foo, 9), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr42(R) :- catch((nb_link_dict(a, [a-1], 9), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr43(R) :- catch((nb_link_dict(a, _, 9), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr44(R) :- catch((dict_create(D, t, [a-1]), nb_link_dict(1.5, D, 9), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr45(R) :- catch((dict_create(D, t, [a-1]), nb_link_dict(_, D, 9), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr46(R) :- catch((dict_create(D, t, [1-one, 2-two]), nb_link_dict(2, D, 9), dpairs(D, R)), error(SsuE, _), R = raised(SsuE)).
t_dr47(R) :- catch((dict_create(D, t, [a-1]), nb_link_dict(a, D, f(X)), get_dict(a, D, f(Y)), Y = 1, R = X), error(SsuE, _), R = raised(SsuE)).
t_dr48(R) :- catch((dict_create(D, t, [a-1]), nb_link_dict(a, D, f(X)), get_dict(a, D, f(Y)), ( X == Y -> R = same ; R = copied )), error(SsuE, _), R = raised(SsuE)).
t_dr49(R) :- catch((dict_create(D, t, [a-1]), nb_link_dict(a, D, g(h(i))), get_dict(a, D, V), R = V), error(SsuE, _), R = raised(SsuE)).
t_dr50(R) :- catch((dict_create(D, t, [a-1]), nb_link_dict(a, D, 9), put_dict(a, D, 7, N), dpairs(N, P), dpairs(D, Q), R = P-Q), error(SsuE, _), R = raised(SsuE)).
t_dr51(R) :- catch(('$btree_find_node'(m, t(m,mv,<,t(f,fv,<,t,t),t(s,sv,<,t,t)), 0x010405, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr52(R) :- catch(('$btree_find_node'(f, t(m,mv,<,t(f,fv,<,t,t),t(s,sv,<,t,t)), 0x010405, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr53(R) :- catch(('$btree_find_node'(s, t(m,mv,<,t(f,fv,<,t,t),t(s,sv,<,t,t)), 0x010405, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr54(R) :- catch(('$btree_find_node'(a, t(m,mv,<,t(f,fv,<,t,t),t(s,sv,<,t,t)), 0x010405, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr55(R) :- catch(('$btree_find_node'(z, t(m,mv,<,t(f,fv,<,t,t),t(s,sv,<,t,t)), 0x010405, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr56(R) :- catch(('$btree_find_node'(g, t(m,mv,<,t(f,fv,<,t,t),t(s,sv,<,t,t)), 0x010405, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr57(R) :- catch(('$btree_find_node'(r, t(m,mv,<,t(f,fv,<,t,t),t(s,sv,<,t,t)), 0x010405, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr58(R) :- catch(('$btree_find_node'(k, t(k,v,<,t,t), 0x010405, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr59(R) :- catch(('$btree_find_node'(a, t(k,v,<,t,t), 0x010405, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr60(R) :- catch(('$btree_find_node'(z, t(k,v,<,t,t), 0x010405, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr61(R) :- catch(('$btree_find_node'(a, t(k,v,<,u(a),t), 0x010405, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr62(R) :- catch(('$btree_find_node'(a, t(k,v,<,t(a,b,c,d,e,f),t), 0x010405, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr63(R) :- catch(('$btree_find_node'(a, t(k,v,<,t(c,v,<,t,t),t), 0x010405, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr64(R) :- catch(('$btree_find_node'(5, n(5,n(2,e,e),n(8,e,e)), 0x010203, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr65(R) :- catch(('$btree_find_node'(2, n(5,n(2,e,e),n(8,e,e)), 0x010203, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr66(R) :- catch(('$btree_find_node'(8, n(5,n(2,e,e),n(8,e,e)), 0x010203, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr67(R) :- catch(('$btree_find_node'(1, n(5,n(2,e,e),n(8,e,e)), 0x010203, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr68(R) :- catch(('$btree_find_node'(9, n(5,n(2,e,e),n(8,e,e)), 0x010203, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr69(R) :- catch(('$btree_find_node'(3, n(5,n(2,e,e),n(8,e,e)), 0x010203, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr70(R) :- catch(('$btree_find_node'(5, n(5,n(2,e,e),n(8,e,e)), 0x010203, n(5,L,Rt), A), R = A-L-Rt), error(SsuE, _), R = raised(SsuE)).
t_dr71(R) :- catch(('$btree_find_node'(2, n(5,n(2,e,e),n(8,e,e)), 0x010203, N, '='), R = N), error(SsuE, _), R = raised(SsuE)).
t_dr72(R) :- catch(('$btree_find_node'(2, n(5,n(2,e,e),n(8,e,e)), 0x010203, N, '<'), R = N), error(SsuE, _), R = raised(SsuE)).
t_dr73(R) :- catch(('$btree_find_node'(2, n(5,n(2,e,e),n(8,e,e)), 0x010203, foo, A), R = A), error(SsuE, _), R = raised(SsuE)).
t_dr74(R) :- catch(('$btree_find_node'(1, n(5,n(2,e,e),n(8,e,e)), 0x010203, n(2,e,e), A), R = A), error(SsuE, _), R = raised(SsuE)).
t_dr75(R) :- catch(('$btree_find_node'(1, n(5,n(2,e,e),n(8,e,e)), 0x010203, n(5,_,_), A), R = A), error(SsuE, _), R = raised(SsuE)).
t_dr76(R) :- catch(('$btree_find_node'(1, n(5,n(2,e,e),n(8,e,e)), 0x010203, N, '>'), R = N), error(SsuE, _), R = raised(SsuE)).
t_dr77(R) :- catch(('$btree_find_node'(1, n(5,n(2,e,e),n(8,e,e)), 0x010203, N, '<'), R = N), error(SsuE, _), R = raised(SsuE)).
t_dr78(R) :- catch(('$btree_find_node'(1, n(5,n(2,e,e),n(8,e,e)), 0x010302, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr79(R) :- catch(('$btree_find_node'(9, n(5,n(2,e,e),n(8,e,e)), 0x010302, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr80(R) :- catch(('$btree_find_node'(5, n(n(2,e,e),5,n(8,e,e)), 0x020103, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr81(R) :- catch(('$btree_find_node'(1, m(a,3,b), 0x020103, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr82(R) :- catch(('$btree_find_node'(_, n(5,e,e), 0x010203, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr83(R) :- catch(('$btree_find_node'(f(x), n(5,e,e), 0x010203, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr84(R) :- catch(('$btree_find_node'(a, n(5,e,e), 0x010203, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr85(R) :- catch(('$btree_find_node'(1.5, n(5,e,e), 0x010203, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr86(R) :- catch(('$btree_find_node'(m, t(m,mv,<,t(f,fv,<,t,t),t(s,sv,<,t,t)), foo, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr87(R) :- catch(('$btree_find_node'(m, t(m,mv,<,t(f,fv,<,t,t),t(s,sv,<,t,t)), -1, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr88(R) :- catch(('$btree_find_node'(m, t(m,mv,<,t(f,fv,<,t,t),t(s,sv,<,t,t)), 0, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr89(R) :- catch(('$btree_find_node'(m, t(m,mv,<,t(f,fv,<,t,t),t(s,sv,<,t,t)), _, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr90(R) :- catch(('$btree_find_node'(m, t(m,mv,<,t(f,fv,<,t,t),t(s,sv,<,t,t)), 1.5, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr91(R) :- catch(('$btree_find_node'(m, foo, 0x010405, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr92(R) :- catch(('$btree_find_node'(m, _, 0x010405, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr93(R) :- catch(('$btree_find_node'(m, 42, 0x010405, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr94(R) :- catch(('$btree_find_node'(m, t(a,b), 0x010405, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr95(R) :- catch(('$btree_find_node'(m, n(1,e,e), 0x010206, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr96(R) :- catch(('$btree_find_node'(m, n(1,e,e), 0x060203, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr97(R) :- catch(('$btree_find_node'(m, n(1,e,e), 0x010602, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr98(R) :- catch(('$btree_find_node'(m, [a,b,c], 0x010102, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr99(R) :- catch((string_codes(S, [115]), '$btree_find_node'(m, S, 0x010203, N, A), R = A-N), error(SsuE, _), R = raised(SsuE)).
t_dr100(R) :- catch(('$needs_quotes'('hello world'), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr101(R) :- catch(('$needs_quotes'('A'), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr102(R) :- catch(('$needs_quotes'('_x'), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr103(R) :- catch(('$needs_quotes'(''), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr104(R) :- catch(('$needs_quotes'(abc), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr105(R) :- catch(('$needs_quotes'(a1), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr106(R) :- catch(('$needs_quotes'(a_b), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr107(R) :- catch(('$needs_quotes'(+), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr108(R) :- catch(('$needs_quotes'(;), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr109(R) :- catch(('$needs_quotes'(!), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr110(R) :- catch(('$needs_quotes'(','), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr111(R) :- catch(('$needs_quotes'('|'), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr112(R) :- catch(('$needs_quotes'('a.b'), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr113(R) :- catch(('$needs_quotes'('[]'), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr114(R) :- catch(('$needs_quotes'([]), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr115(R) :- catch(('$needs_quotes'({}), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr116(R) :- catch(('$needs_quotes'('{}'), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr117(R) :- catch(('$needs_quotes'(=..), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr118(R) :- catch(('$needs_quotes'(\+), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr119(R) :- catch(('$needs_quotes'('1a'), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr120(R) :- catch(('$needs_quotes'('\n'), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr121(R) :- catch((atom_codes(A, [233]), '$needs_quotes'(A), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr122(R) :- catch((atom_codes(A, [201]), '$needs_quotes'(A), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr123(R) :- catch(('$needs_quotes'(1), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr124(R) :- catch((string_codes(S, [115]), '$needs_quotes'(S), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr125(R) :- catch(('$needs_quotes'(f(x)), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr126(R) :- catch(('$needs_quotes'(_), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr127(R) :- catch(('$needs_quotes'([a]), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr128(R) :- catch(('$needs_quotes'(1.5), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr129(R) :- catch((b_set_dict(1.5, foo, 9), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr130(R) :- catch((nb_set_dict(_, foo, 9), R = yes), error(SsuE, _), R = raised(SsuE)).
t_dr131(R) :- catch((nb_link_dict(1.5, foo, 9), R = yes), error(SsuE, _), R = raised(SsuE)).
