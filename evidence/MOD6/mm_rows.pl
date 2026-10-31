mme_done :- '$set_source_module'(user), '$set_typein_module'(user).
mme_det(G, D) :- call_cleanup(G, Det = true), ( Det == true -> D = det ; D = nondet ).
mme_pre(M) :- atom_concat(mmx_, _, M).
mme_names(L) :- findall(M, ('$current_module'(M, _), mme_pre(M)), L0), msort(L0, L).
mme_pairs(L) :- findall(M-F, ('$current_module'(M, F), mme_pre(M)), L0), msort(L0, L).
mme_supers(M, L) :- findall(S, import_module(M, S), L).
t_s01(R) :- catch(('$declare_module'(mmx_f, user, user, '/mmx/f.pl', 1, false), '$declare_module'(mmx_g1, user, user, '/mmx/g.pl', 1, false), '$declare_module'(mmx_g2, user, user, '/mmx/g.pl', 5, false), '$declare_module'(mmx_s, system, user, '/mmx/s.pl', 1, false), '$declare_module'(mmx_t, temporary, user, '/mmx/t.pl', 1, false), assertz(mmx_u:p(1)), R = ok), error(F, _), R = raised(F)), mme_done.
t_i01(R) :- catch((mme_supers(user, L), R = L), error(F, _), R = raised(F)), mme_done.
t_i02(R) :- catch((mme_supers(system, L), R = L), error(F, _), R = raised(F)), mme_done.
t_i03(R) :- catch((mme_supers(mmx_fresh1, L), R = L), error(F, _), R = raised(F)), mme_done.
t_i04(R) :- catch((mme_supers(mmx_u, L), R = L), error(F, _), R = raised(F)), mme_done.
t_i05(R) :- catch((mme_supers(mmx_f, L), mme_supers(mmx_s, L2), mme_supers(mmx_t, L3), R = [L, L2, L3]), error(F, _), R = raised(F)), mme_done.
t_i06(R) :- catch((add_import_module(mmx_c2, mmx_u, start), mme_supers(mmx_c2, L), R = L), error(F, _), R = raised(F)), mme_done.
t_i07(R) :- catch((add_import_module(mmx_c3, mmx_f, end), add_import_module(mmx_c3, mmx_u, end), mme_supers(mmx_c3, L), R = L), error(F, _), R = raised(F)), mme_done.
t_i08(R) :- catch((mme_supers(mmx_c3, L), delete_import_module(mmx_c3, user), mme_supers(mmx_c3, L2), R = L-L2), error(F, _), R = raised(F)), mme_done.
t_i09(R) :- catch((findall(S-D, mme_det(import_module(mmx_c2, S), D), L), R = L), error(F, _), R = raised(F)), mme_done.
t_i10(R) :- catch((mme_det(import_module(mmx_u, S), D), R = S-D), error(F, _), R = raised(F)), mme_done.
t_i11(R) :- catch((( import_module(mmx_c2, mmx_u) -> A = yes ; A = no ), ( import_module(mmx_c2, user) -> B = yes ; B = no ), R = A-B), error(F, _), R = raised(F)), mme_done.
t_i12(R) :- catch((( import_module(mmx_u, user) -> A = yes ; A = no ), ( import_module(mmx_u, system) -> B = yes ; B = no ), R = A-B), error(F, _), R = raised(F)), mme_done.
t_i13(R) :- catch((catch(import_module(_, _), error(E, _), true), R = E), error(F, _), R = raised(F)), mme_done.
t_i14(R) :- catch((catch(import_module(1, _), error(E, _), true), R = E), error(F, _), R = raised(F)), mme_done.
t_i15(R) :- catch((catch(import_module(f(x), _), error(E, _), true), R = E), error(F, _), R = raised(F)), mme_done.
t_i16(R) :- catch((( import_module(mmx_u, 1) -> A = yes ; A = no ), ( import_module(mmx_u, f(x)) -> B = yes ; B = no ), R = A-B), error(F, _), R = raised(F)), mme_done.
t_i17(R) :- catch((import_module(mmx_c2, S), !, R = S), error(F, _), R = raised(F)), mme_done.
t_i18(R) :- catch((( forall(import_module(mmx_c2, S), atom(S)) -> R = yes ; R = no )), error(F, _), R = raised(F)), mme_done.
t_i19(R) :- catch((add_import_module(mmx_c4, mmx_u, start), findall(S, (import_module(mmx_c4, S), ( S == mmx_u -> add_import_module(mmx_c4, mmx_f, end) ; true )), L), R = L), error(F, _), R = raised(F)), mme_done.
t_i20(R) :- catch((( import_module(user, S), import_module(S, S2) -> R = S-S2 ; R = none )), error(F, _), R = raised(F)), mme_done.
t_c01(R) :- catch(('$current_module'(user, Fa), '$current_module'(system, Fb), R = Fa-Fb), error(F, _), R = raised(F)), mme_done.
t_c02(R) :- catch(('$current_module'(mmx_f, Fa), R = Fa), error(F, _), R = raised(F)), mme_done.
t_c03(R) :- catch((( '$current_module'(mmx_none, Fa) -> R = yes(Fa) ; R = no )), error(F, _), R = raised(F)), mme_done.
t_c04(R) :- catch((( '$current_module'(mmx_f, '/mmx/f.pl') -> A = yes ; A = no ), ( '$current_module'(mmx_f, '/mmx/other.pl') -> B = yes ; B = no ), ( '$current_module'(user, []) -> C = yes ; C = no ), ( '$current_module'(mmx_f, 1) -> D = yes ; D = no ), R = [A, B, C, D]), error(F, _), R = raised(F)), mme_done.
t_c05(R) :- catch(('$current_module'(M, '/mmx/f.pl'), R = M), error(F, _), R = raised(F)), mme_done.
t_c06(R) :- catch(('$current_module'(M, '/mmx/g.pl'), msort(M, S), R = S), error(F, _), R = raised(F)), mme_done.
t_c07(R) :- catch((( '$current_module'([mmx_g1, mmx_g2], '/mmx/g.pl') -> A = yes ; A = no ), ( '$current_module'([mmx_g2, mmx_g1], '/mmx/g.pl') -> B = yes ; B = no ), R = A-B), error(F, _), R = raised(F)), mme_done.
t_c08(R) :- catch((( '$current_module'(M, '/mmx/unknown.pl') -> R = yes(M) ; R = no )), error(F, _), R = raised(F)), mme_done.
t_c09(R) :- catch((( '$current_module'(1, _) -> A = yes ; A = no ), ( '$current_module'(f(x), _) -> B = yes ; B = no ), R = A-B), error(F, _), R = raised(F)), mme_done.
t_c10(R) :- catch((( '$current_module'(_, 1) -> R = yes ; R = no )), error(F, _), R = raised(F)), mme_done.
t_c11(R) :- catch((mme_names(L), R = L), error(F, _), R = raised(F)), mme_done.
t_c12(R) :- catch((mme_pairs(L), R = L), error(F, _), R = raised(F)), mme_done.
t_c13(R) :- catch((findall(M, ('$current_module'(M, _), ( M == system ; M == user )), L0), msort(L0, L), R = L), error(F, _), R = raised(F)), mme_done.
t_c14(R) :- catch((findall(M, ('$current_module'(M, _), ( M == mmx_s ; M == mmx_t )), L), '$current_module'(mmx_s, Fa), '$current_module'(mmx_t, Fb), R = L-Fa-Fb), error(F, _), R = raised(F)), mme_done.
t_c15(R) :- catch((findall(D, mme_det('$current_module'(_, _), D), L0), sort(L0, L), R = L), error(F, _), R = raised(F)), mme_done.
t_c16(R) :- catch((mme_det('$current_module'(user, _), D1), mme_det('$current_module'(_, '/mmx/f.pl'), D2), mme_det('$current_module'(_, '/mmx/g.pl'), D3), R = [D1, D2, D3]), error(F, _), R = raised(F)), mme_done.
t_c17(R) :- catch(('$current_module'(M, _), !, ( atom(M) -> R = ok ; R = no )), error(F, _), R = raised(F)), mme_done.
t_c18(R) :- catch((\+ \+ '$current_module'(_, _), \+ \+ '$current_module'(_, _), once('$current_module'(_, _)), once('$current_module'(_, _)), R = ok), error(F, _), R = raised(F)), mme_done.
t_c19(R) :- catch((findall(M, ('$current_module'(M, _), ( M == mmx_u ; M == mmx_f ; M == mmx_c2 )), L0), msort(L0, L), R = L), error(F, _), R = raised(F)), mme_done.
t_d01(R) :- catch(('$destroy_module'(mmx_t), ( '$current_module'(mmx_t, Fa) -> R = yes(Fa) ; R = no )), error(F, _), R = raised(F)), mme_done.
t_d03(R) :- catch((findall(M, ('$current_module'(M, _), M == mmx_t), L), R = L), error(F, _), R = raised(F)), mme_done.
t_d04(R) :- catch((assertz(mmx_t:q(1)), findall(M, ('$current_module'(M, _), M == mmx_t), L), '$module_property'(mmx_t, class(C)), R = L-C), error(F, _), R = raised(F)), mme_done.
t_d05(R) :- catch(('$declare_module'(mmx_t3, temporary, user, '/mmx/t3.pl', 1, false), mme_supers(mmx_t3, L1), '$destroy_module'(mmx_t3), mme_supers(mmx_t3, L2), ( '$current_module'(mmx_t3, Fa) -> A = Fa ; A = none ), R = [L1, L2, A]), error(F, _), R = raised(F)), mme_done.
