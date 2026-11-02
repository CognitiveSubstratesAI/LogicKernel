:- dynamic bp3_hit/1.
bp3_hit1(_) :- assertz(bp3_hit(x)).
bp3_cb.
bp3_cb(_).
bp3_cb(_, _).
bp3_cb(_, _, _).
bp3_hex([]).
bp3_hex([C|Cs]) :- ( C >= 0'0, C =< 0'9 ; C >= 0'a, C =< 0'f ), !, bp3_hex(Cs).
bp3_mk(0, []) :- !.
bp3_mk(N, [N|T]) :- N1 is N-1, bp3_mk(N1, T).
t_bp3m01(R) :- catch(('$memberchk'(b, [a,b,c], T), R = T), error(SsuE, _), R = raised(SsuE)).
t_bp3m02(R) :- catch(('$memberchk'(z, [a,b], T), R = T), error(SsuE, _), R = raised(SsuE)).
t_bp3m03(R) :- catch(('$memberchk'(X, [a,b], T), R = X-T), error(SsuE, _), R = raised(SsuE)).
t_bp3m04(R) :- catch(('$memberchk'(c, [a,b|L], T), ( T == L -> R = same ; R = diff )), error(SsuE, _), R = raised(SsuE)).
t_bp3m05(R) :- catch(('$memberchk'(a, L, T), ( T == L -> R = same ; R = diff )), error(SsuE, _), R = raised(SsuE)).
t_bp3m06(R) :- catch(('$memberchk'(a, [a|b], T), R = T), error(SsuE, _), R = raised(SsuE)).
t_bp3m07(R) :- catch(('$memberchk'(z, [a|b], T), R = T), error(SsuE, _), R = raised(SsuE)).
t_bp3m08(R) :- catch(('$memberchk'(a, foo, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_bp3m09(R) :- catch(('$memberchk'(a, 1, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_bp3m10(R) :- catch(('$memberchk'(f(X), [g(1), f(2), f(3)], T), R = X-T), error(SsuE, _), R = raised(SsuE)).
t_bp3m11(R) :- catch(('$memberchk'(f(X,X), [f(1,2), f(3,3)], T), R = X-T), error(SsuE, _), R = raised(SsuE)).
t_bp3m12(R) :- catch(('$memberchk'(a, [], T), R = T), error(SsuE, _), R = raised(SsuE)).
t_bp3m13(R) :- catch(('$memberchk'(c, [b,c], x), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3m14(R) :- catch((findall(X-T, '$memberchk'(X, [a,b], T), R)), error(SsuE, _), R = raised(SsuE)).
t_bp3m15(R) :- catch(('$memberchk'(f(X,b), [f(1,a), f(2,b)], T), R = X-T), error(SsuE, _), R = raised(SsuE)).
t_bp3m16(R) :- catch((bp3_mk(12000, L), '$memberchk'(1, L, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_bp3m17(R) :- catch(('$memberchk'(a, [a,b], []), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3m18(R) :- catch(('$memberchk'(f(_), [f(x)|_], T), R = T), error(SsuE, _), R = raised(SsuE)).
t_bp3i01(R) :- catch(('$inc_message_count'(error), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3i02(R) :- catch(('$inc_message_count'(warning), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3i03(R) :- catch(('$inc_message_count'(informational), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3i04(R) :- catch(('$inc_message_count'(foo), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3i05(R) :- catch(('$inc_message_count'(1), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3i06(R) :- catch(('$inc_message_count'(_), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3i07(R) :- catch(('$inc_message_count'(f(x)), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3i08(R) :- catch(('$inc_message_count'(1.5), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3i09(R) :- catch(('$inc_message_count'([]), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3i10(R) :- catch((findall(x, '$inc_message_count'(error), R)), error(SsuE, _), R = raised(SsuE)).
t_bp3i11(R) :- catch((statistics(errors, E0), '$inc_message_count'(error), statistics(errors, E1), R is E1-E0), error(SsuE, _), R = raised(SsuE)).
t_bp3i12(R) :- catch((statistics(warnings, E0), '$inc_message_count'(warning), statistics(warnings, E1), R is E1-E0), error(SsuE, _), R = raised(SsuE)).
t_bp3n01(R) :- catch(('$notrace'(F, S), '$restore_trace'(F, S), R = F-S), error(SsuE, _), R = raised(SsuE)).
t_bp3n02(R) :- catch(('$notrace'(F0, S0), '$notrace'(F, S), '$restore_trace'(F0, S0), R = F-S), error(SsuE, _), R = raised(SsuE)).
t_bp3n03(R) :- catch(('$notrace'(F0, S0), '$restore_trace'(0, -1), '$notrace'(F, _), '$restore_trace'(F0, S0), R = F), error(SsuE, _), R = raised(SsuE)).
t_bp3n04(R) :- catch(('$notrace'(F0, S0), '$restore_trace'(4, -1), '$notrace'(F, _), '$restore_trace'(F0, S0), R = F), error(SsuE, _), R = raised(SsuE)).
t_bp3n05(R) :- catch(('$notrace'(F0, S0), '$restore_trace'(8, -1), '$notrace'(F, _), '$restore_trace'(F0, S0), R = F), error(SsuE, _), R = raised(SsuE)).
t_bp3n06(R) :- catch(('$notrace'(F0, S0), '$restore_trace'(12, -1), '$notrace'(F, _), '$restore_trace'(F0, S0), R = F), error(SsuE, _), R = raised(SsuE)).
t_bp3n07(R) :- catch(('$notrace'(F0, S0), '$restore_trace'(F0, -2), '$notrace'(_, S), '$restore_trace'(F0, S0), R = S), error(SsuE, _), R = raised(SsuE)).
t_bp3n08(R) :- catch(('$notrace'(a, _), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3n09(R) :- catch(('$notrace'(_, 5), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3n10(R) :- catch(('$restore_trace'(a, -1), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3n11(R) :- catch(('$restore_trace'(_, -1), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3n12(R) :- catch(('$restore_trace'(12, a), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3n13(R) :- catch(('$restore_trace'(12, _), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3n14(R) :- catch(('$restore_trace'(4294967296, -1), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3n15(R) :- catch(('$restore_trace'(12, -3), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3n16(R) :- catch(('$restore_trace'(12, -1.5), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3n17(R) :- catch(('$restore_trace'(12, 99999999999999999999), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3n18(R) :- catch(('$notrace'(F0, S0), '$restore_trace'(F0, S0), '$restore_trace'(F0, S0), '$notrace'(F, S), '$restore_trace'(F0, S0), R = F-S), error(SsuE, _), R = raised(SsuE)).
t_bp3n19(R) :- catch(('$notrace'(F0, S0), '$notrace'(F, _), '$restore_trace'(F0, S0), R = F), error(SsuE, _), R = raised(SsuE)).
t_bp3l01(R) :- catch((prolog_listen(untable, bp3_cb), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l02(R) :- catch((prolog_listen(untable, bp3_cb, [as(last)]), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l03(R) :- catch((prolog_listen(untable, bp3_cb, [as(first)]), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l04(R) :- catch((prolog_listen(untable, bp3_cb, [name(bp3_n1)]), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l05(R) :- catch((prolog_listen(untable, bp3_cb, [name(bp3_n1)]), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l06(R) :- catch((prolog_listen(untable, bp3_cb, [as(last), name(bp3_n2)]), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l07(R) :- catch((prolog_listen(untable, bp3_cb, []), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l08(R) :- catch((prolog_listen(untable, bp3_cb, [as(middle)]), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l09(R) :- catch((prolog_listen(untable, bp3_cb, [as(1)]), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l10(R) :- catch((prolog_listen(untable, bp3_cb, [foo(1)]), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l11(R) :- catch((prolog_listen(untable, bp3_cb, foo), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l12(R) :- catch((prolog_listen(untable, bp3_cb, [as(last)|_]), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l13(R) :- catch((prolog_listen(nosuchevent, bp3_cb), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l14(R) :- catch((prolog_listen(1, bp3_cb), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l15(R) :- catch((prolog_listen(_, bp3_cb), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l16(R) :- catch((prolog_listen(untable, 1), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l17(R) :- catch((prolog_listen(untable, _), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l18(R) :- catch((prolog_listen(untable, user:bp3_cb), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l19(R) :- catch((prolog_listen(untable, user:1), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l20(R) :- catch((prolog_listen(abort, bp3_cb), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l21(R) :- catch((prolog_listen(erase, bp3_cb), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l22(R) :- catch((prolog_listen(break, bp3_cb), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l23(R) :- catch((prolog_listen(frame_finished, bp3_cb), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l24(R) :- catch((prolog_listen(thread_start, bp3_cb), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l25(R) :- catch((prolog_listen(thread_exit, bp3_cb), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l26(R) :- catch((prolog_listen(this_thread_exit, bp3_cb), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l27(R) :- catch((prolog_listen(untable, bp3_cb(a)), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l28(R) :- catch((prolog_listen(untable, bp3_cb, [as(middle), name(bp3_n3)]), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l29(R) :- catch((findall(x, prolog_listen(untable, bp3_cb), R)), error(SsuE, _), R = raised(SsuE)).
t_bp3l30(R) :- catch((prolog_listen(untable, bp3_cb, [name(1)]), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l31(R) :- catch((prolog_listen(nosuchevent, 1, [as(first)]), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l32(R) :- catch((prolog_listen(1, bp3_cb, [as(middle)]), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3l33(R) :- catch((prolog_listen(erase, bp3_hit1), recorda(bp3_k, v, Ref), erase(Ref), findall(H, bp3_hit(H), Hs), length(Hs, R)), error(SsuE, _), R = raised(SsuE)).
t_bp3v01(R) :- catch((variant_sha1(foo, H), atom_length(H, R)), error(SsuE, _), R = raised(SsuE)).
t_bp3v02(R) :- catch((variant_sha1(f(X,Y,X), H1), variant_sha1(f(A,B,A), H2), ( H1 == H2 -> R = same ; R = diff )), error(SsuE, _), R = raised(SsuE)).
t_bp3v03(R) :- catch((variant_sha1(f(X,Y), H1), variant_sha1(f(X,X), H2), ( H1 == H2 -> R = same ; R = diff )), error(SsuE, _), R = raised(SsuE)).
t_bp3v04(R) :- catch((variant_sha1(f(a), H), ( atom(H) -> R = atom ; R = other )), error(SsuE, _), R = raised(SsuE)).
t_bp3v05(R) :- catch((variant_sha1(f(a,_), H), atom_codes(H, Cs), ( bp3_hex(Cs) -> R = hex ; R = nothex )), error(SsuE, _), R = raised(SsuE)).
t_bp3v06(R) :- catch((variant_sha1(a, H1), variant_sha1(b, H2), ( H1 == H2 -> R = same ; R = diff )), error(SsuE, _), R = raised(SsuE)).
t_bp3v07(R) :- catch((variant_sha1(a, H1), variant_sha1(a, H2), ( H1 == H2 -> R = same ; R = diff )), error(SsuE, _), R = raised(SsuE)).
t_bp3v08(R) :- catch((variant_sha1(a, foo), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3v09(R) :- catch((variant_sha1(a, 1), R = yes), error(SsuE, _), R = raised(SsuE)).
t_bp3v10(R) :- catch((findall(H, variant_sha1(g(_), H), Hs), length(Hs, R)), error(SsuE, _), R = raised(SsuE)).
t_bp3v11(R) :- catch((variant_sha1([a,b|T], H1), variant_sha1([a,b|U], H2), ( H1 == H2 -> R = same ; R = diff )), error(SsuE, _), R = raised(SsuE)).
t_bp3v12(R) :- catch((variant_sha1(1, H1), variant_sha1(2, H2), ( H1 == H2 -> R = same ; R = diff )), error(SsuE, _), R = raised(SsuE)).
t_bp3v13(R) :- catch((variant_sha1(f(X,Y), H1), variant_sha1(f(Y,X), H2), ( H1 == H2 -> R = same ; R = diff )), error(SsuE, _), R = raised(SsuE)).
t_bp3v14(R) :- catch((variant_sha1(f(a), H), atom_length(H, R)), error(SsuE, _), R = raised(SsuE)).
t_bp3v15(R) :- catch((variant_sha1(foo, R)), error(SsuE, _), R = raised(SsuE)).
