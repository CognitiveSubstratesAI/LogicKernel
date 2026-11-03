pr_s1(1).
pr_s1(2).
pr_s2(1).
pr_s3(1).
pr_s4(1).
pr_s5(1).
pr_s6(1).
pr_s7(1).
pr_t(X, Y) :- pr_s1(X), pr_s1(Y).
pr_u.
pr_try(G, R) :- catch(( G -> R = yes ; R = no ), error(E, _), R = err(E)).
pr_cp(S, L) :- findall(S, current_predicate(S), L0), msort(L0, L).
pr_ld1(1).
pr_ld1(2).
:- abolish(pr_ld1/1).
:- asserta((pr_ld1(X) :- X = 3)).
pr_ld2(a).
:- abolish(pr_ld2/1).
pr_ld3(1).
:- abolish(pr_ld3/1).
pr_ld3(2).
pr_ld4(1).
pr_ld4(2).
:- abolish(pr_ld4, 1).
:- asserta(pr_ld4(7)), assertz(pr_ld4(8)).
:- assertz(prws:pr_wq(1)).
:- '$import'(prws:pr_wq/1, weak).
pr_wq(9).
mrq:qs(1).
mrq:qs(2).
t_pr01(R) :- catch((assertz(pr_a1(1)), assertz(pr_a1(2)), abolish(pr_a1/1), pr_try(pr_a1(_), R)), error(E, _), R = raised(E)).
t_pr02(R) :- catch((assertz(pr_a2(1)), abolish(pr_a2/1), pr_try(current_predicate(pr_a2/1), R)), error(E, _), R = raised(E)).
t_pr03(R) :- catch((abolish(pr_s7/1), pr_try(pr_s7(_), R)), error(E, _), R = raised(E)).
t_pr04(R) :- catch((abolish(pr_s2, 1), pr_try(current_predicate(pr_s2/1), R)), error(E, _), R = raised(E)).
t_pr05(R) :- catch((assertz(pr_a3(1)), abolish(pr_a3, 1), pr_try(pr_a3(_), R)), error(E, _), R = raised(E)).
t_pr06(R) :- catch((assertz(pr_a4(1)), abolish(pr_a4/1), assertz(pr_a4(2)), findall(X, pr_a4(X), R)), error(E, _), R = raised(E)).
t_pr07(R) :- catch((assertz(pr_a5(1)), abolish(pr_a5/1), '$get_predicate_attribute'(pr_a5(_), dynamic, V), R = V), error(E, _), R = raised(E)).
t_pr08(R) :- catch((assertz(pr_a6(1)), '$get_predicate_attribute'(pr_a6(_), dynamic, V0), abolish(pr_a6/1), pr_try('$get_predicate_attribute'(pr_a6(_), dynamic, _), R0), R = V0-R0), error(E, _), R = raised(E)).
t_pr09(R) :- catch((abolish(pr_nosuch/3), R = ok), error(E, _), R = raised(E)).
t_pr10(R) :- catch((abolish(pr_nosuch2, 3), R = ok), error(E, _), R = raised(E)).
t_pr11(R) :- catch((abolish(atom_length/2)), error(E, _), R = raised(E)).
t_pr12(R) :- catch((abolish(atom_length, 2)), error(E, _), R = raised(E)).
t_pr13(R) :- catch((assertz(pr_m1:pr_q(1)), abolish(pr_m1:pr_q/1), pr_try(current_predicate(pr_m1:pr_q/1), R)), error(E, _), R = raised(E)).
t_pr14(R) :- catch((assertz(pr_m1:pr_q2(1)), abolish(pr_m1:pr_q2, 1), pr_try(pr_m1:pr_q2(_), R)), error(E, _), R = raised(E)).
t_pr15(R) :- catch((assertz(pr_m1:pr_q3(1)), abolish(pr_m1:pr_q3/1), pr_try(current_predicate(pr_q3/1), R)), error(E, _), R = raised(E)).
t_pr16(R) :- catch((abolish(foo)), error(E, _), R = raised(E)).
t_pr17(R) :- catch((abolish(pr_x/(-1))), error(E, _), R = raised(E)).
t_pr18(R) :- catch((abolish(pr_x, -1)), error(E, _), R = raised(E)).
t_pr19(R) :- catch((abolish(_)), error(E, _), R = raised(E)).
t_pr20(R) :- catch((abolish(_/1)), error(E, _), R = raised(E)).
t_pr21(R) :- catch((abolish(pr_x/a)), error(E, _), R = raised(E)).
t_pr22(R) :- catch((abolish(1/1)), error(E, _), R = raised(E)).
t_pr23(R) :- catch((abolish(pr_x/_)), error(E, _), R = raised(E)).
t_pr24(R) :- catch((abolish(pr_x, 99999999999)), error(E, _), R = raised(E)).
t_pr25(R) :- catch((abolish(pr_x, 1.5)), error(E, _), R = raised(E)).
t_pr26(R) :- catch((catch(( set_prolog_flag(iso, true), abolish(pr_s3/1) ), error(E, _), true), set_prolog_flag(iso, false), R = E), error(E, _), R = raised(E)).
t_pr27(R) :- catch((assertz(pr_a7(1)), catch(( set_prolog_flag(iso, true), abolish(pr_a7/1), E = ok ), error(E, _), true), set_prolog_flag(iso, false), R = E), error(E, _), R = raised(E)).
t_pr28(R) :- catch((pr_try(pr_s3(_), R)), error(E, _), R = raised(E)).
t_pr29(R) :- catch((assertz(pr_m2:pr_i(1)), pr_m3:import(pr_m2:pr_i/1), abolish(pr_m3:pr_i/1), pr_try(pr_m3:pr_i(_), R)), error(E, _), R = raised(E)).
t_pr30(R) :- catch((assertz(pr_m2:pr_i2(1)), pr_m3:import(pr_m2:pr_i2/1), abolish(pr_m3:pr_i2/1), findall(X, pr_m2:pr_i2(X), R)), error(E, _), R = raised(E)).
t_pr31(R) :- catch((assertz(pr_m2:pr_i3(1)), pr_m3:import(pr_m2:pr_i3/1), abolish(pr_m3:pr_i3/1), pr_try('$get_predicate_attribute'(pr_m3:pr_i3(_), imported, _), R)), error(E, _), R = raised(E)).
t_pr32(R) :- catch((assertz(pr_g(1)), assertz(pr_g(2)), assertz(pr_g(3)), retract(pr_g(2)), garbage_collect_clauses, findall(X, pr_g(X), R)), error(E, _), R = raised(E)).
t_pr33(R) :- catch((garbage_collect_clauses, R = ok), error(E, _), R = raised(E)).
t_pr34(R) :- catch((current_predicate(pr_s4/1), R = yes), error(E, _), R = raised(E)).
t_pr35(R) :- catch((current_predicate(pr_s4/2), R = yes), error(E, _), R = raised(E)).
t_pr36(R) :- catch((findall(A, current_predicate(pr_t/A), R)), error(E, _), R = raised(E)).
t_pr37(R) :- catch((findall(N, ( current_predicate(N/2), N == pr_t ), R)), error(E, _), R = raised(E)).
t_pr38(R) :- catch((current_predicate(pr_nosuch/_), R = yes), error(E, _), R = raised(E)).
t_pr39(R) :- catch((current_predicate(pr_u/0), R = yes), error(E, _), R = raised(E)).
t_pr40(R) :- catch((pr_cp(pr_s5/_, R)), error(E, _), R = raised(E)).
t_pr41(R) :- catch((catch(pr_und, _, true), pr_try(current_predicate(pr_und/0), R)), error(E, _), R = raised(E)).
t_pr42(R) :- catch((current_predicate(atom_length/2), R = yes), error(E, _), R = raised(E)).
t_pr43(R) :- catch((assertz(pr_m5:pr_zz(1)), current_predicate(pr_m5:pr_zz/1), R = yes), error(E, _), R = raised(E)).
t_pr44(R) :- catch((assertz(pr_m5:pr_zz2(1)), current_predicate(pr_nomod:pr_zz2/1), R = yes), error(E, _), R = raised(E)).
t_pr45(R) :- catch((assertz(pr_m6:pr_e(1)), assertz(pr_e(1)), findall(M, ( current_predicate(M:pr_e/1), ( M == user ; M == pr_m1 ; M == pr_m2 ; M == pr_m3 ; M == pr_m5 ; M == pr_m6 ) ), Ms), msort(Ms, R)), error(E, _), R = raised(E)).
t_pr46(R) :- catch((assertz(pr_m6:pr_e2(1)), assertz(pr_m6:pr_e2(2)), assertz(pr_e2(1)), findall(M-A, current_predicate(M:pr_e2/A), Ms), msort(Ms, R)), error(E, _), R = raised(E)).
t_pr47(R) :- catch((assertz(pr_m6:pr_e3(1)), findall(M, current_predicate(M:pr_e3/_), Ms), msort(Ms, R)), error(E, _), R = raised(E)).
t_pr48(R) :- catch((pr_m7:current_predicate(pr_s6/1), R = yes), error(E, _), R = raised(E)).
t_pr49(R) :- catch((findall(A, pr_m7:current_predicate(pr_s6/A), R)), error(E, _), R = raised(E)).
t_pr50(R) :- catch((assertz(pr_m8:pr_s6(1)), findall(A, pr_m8:current_predicate(pr_s6/A), R)), error(E, _), R = raised(E)).
t_pr51(R) :- catch((assertz(pr_m8:pr_lc(1)), findall(N, ( pr_m8:current_predicate(N/1), N == pr_lc ), R)), error(E, _), R = raised(E)).
t_pr52(R) :- catch((pr_try(current_predicate(pr_m6:pr_s6/1), R)), error(E, _), R = raised(E)).
t_pr53(R) :- catch((assertz(pr_dc(a, _, _)), current_predicate(pr_dc//1), R = yes), error(E, _), R = raised(E)).
t_pr54(R) :- catch((assertz(pr_dc2(a, _, _)), findall(A, current_predicate(pr_dc2//A), R)), error(E, _), R = raised(E)).
t_pr55(R) :- catch((assertz(pr_dc3(a, _)), pr_try(current_predicate(pr_dc3//1), R)), error(E, _), R = raised(E)).
t_pr56(R) :- catch((current_predicate(foo)), error(E, _), R = raised(E)).
t_pr57(R) :- catch((current_predicate(1/2)), error(E, _), R = raised(E)).
t_pr58(R) :- catch((current_predicate(pr_s1/a)), error(E, _), R = raised(E)).
t_pr59(R) :- catch((current_predicate(pr_s1/(-1))), error(E, _), R = raised(E)).
t_pr60(R) :- catch((pr_try(current_predicate(_), R)), error(E, _), R = raised(E)).
t_pr61(R) :- catch((current_predicate(pr_s1/1/2)), error(E, _), R = raised(E)).
t_pr62(R) :- catch((findall(M, ( current_predicate(M:pr_s1/1), ( M == user ; M == pr_m1 ; M == pr_m2 ; M == pr_m3 ; M == pr_m5 ; M == pr_m6 ; M == pr_m7 ; M == pr_m8 ) ), Ms), msort(Ms, R)), error(E, _), R = raised(E)).
t_pr63(R) :- catch(('$c_current_predicate'(pr_s1, user:pr_s1(_)), R = yes), error(E, _), R = raised(E)).
t_pr64(R) :- catch(('$c_current_predicate'(N, user:pr_t(_, _)), R = N), error(E, _), R = raised(E)).
t_pr65(R) :- catch((findall(F, '$c_current_predicate'(pr_t, user:F), R)), error(E, _), R = raised(E)).
t_pr66(R) :- catch(('$c_current_predicate'(_, pr_nomod2:pr_s1(_)), R = yes), error(E, _), R = raised(E)).
t_pr67(R) :- catch(('$c_current_predicate'(a, user:pr_s1(_)), R = yes), error(E, _), R = raised(E)).
t_pr68(R) :- catch(('$c_current_predicate'(1, user:_), R = yes), error(E, _), R = raised(E)).
t_pr69(R) :- catch((findall(N, '$c_current_predicate'(N, user:pr_s1(_)), R)), error(E, _), R = raised(E)).
t_pr70(R) :- catch((findall(N-F, ( '$c_current_predicate'(N, user:F), N == pr_t ), R)), error(E, _), R = raised(E)).
t_pr71(R) :- catch(('$c_current_predicate'(_, user:1), R = yes), error(E, _), R = raised(E)).
t_pr72(R) :- catch((assertz(pr_m10:pr_cc(1)), findall(N, ( '$c_current_predicate'(N, pr_m10:_), N == pr_cc ), R)), error(E, _), R = raised(E)).
t_pr73(R) :- catch(('$get_predicate_attribute'(pr_s1(_), defined, V), R = V), error(E, _), R = raised(E)).
t_pr74(R) :- catch(('$get_predicate_attribute'(pr_t(_, _), number_of_rules, V), R = V), error(E, _), R = raised(E)).
t_pr75(R) :- catch(('$get_predicate_attribute'(pr_t(_, _), number_of_clauses, V), R = V), error(E, _), R = raised(E)).
t_pr76(R) :- catch(('$get_predicate_attribute'(pr_s1(_), number_of_clauses, V), R = V), error(E, _), R = raised(E)).
t_pr77(R) :- catch(('$get_predicate_attribute'(pr_s1(_), number_of_rules, V), R = V), error(E, _), R = raised(E)).
t_pr78(R) :- catch(('$get_predicate_attribute'(pr_s1(_), dynamic, V), R = V), error(E, _), R = raised(E)).
t_pr79(R) :- catch((assertz(pr_ga1(1)), assertz(pr_ga1(2)), retract(pr_ga1(1)), '$get_predicate_attribute'(pr_ga1(_), number_of_clauses, V), R = V), error(E, _), R = raised(E)).
t_pr80(R) :- catch((assertz(pr_m2:pr_gi(1)), pr_m3:import(pr_m2:pr_gi/1), '$get_predicate_attribute'(pr_m3:pr_gi(_), imported, V), R = V), error(E, _), R = raised(E)).
t_pr81(R) :- catch((pr_try('$get_predicate_attribute'(pr_s1(_), imported, _), R)), error(E, _), R = raised(E)).
t_pr82(R) :- catch(('$get_predicate_attribute'(pr_m9:pr_s1(_), imported, V), R = V), error(E, _), R = raised(E)).
t_pr83(R) :- catch((assertz(pr_m11:pr_ex(1)), pr_m11:export(pr_ex/1), '$get_predicate_attribute'(pr_m11:pr_ex(_), exported, V), R = V), error(E, _), R = raised(E)).
t_pr84(R) :- catch(('$get_predicate_attribute'(pr_s1(_), exported, V), R = V), error(E, _), R = raised(E)).
t_pr85(R) :- catch(('$get_predicate_attribute'(system:atom_length(_, _), foreign, V), R = V), error(E, _), R = raised(E)).
t_pr86(R) :- catch(('$get_predicate_attribute'(pr_s1(_), foreign, V), R = V), error(E, _), R = raised(E)).
t_pr87(R) :- catch((pr_try('$get_predicate_attribute'(system:atom_length(_, _), number_of_clauses, _), R)), error(E, _), R = raised(E)).
t_pr88(R) :- catch(('$get_predicate_attribute'(pr_s1(_), line_count, V), R = V), error(E, _), R = raised(E)).
t_pr89(R) :- catch(('$get_predicate_attribute'(system:atom_length(_, _), line_count, V), R = V), error(E, _), R = raised(E)).
t_pr90(R) :- catch((assertz(pr_mp(_, _, _, _, _, _, _, _)), meta_predicate(pr_mp(0, :, ^, //, +, -, ?, 2)), '$get_predicate_attribute'(pr_mp(_, _, _, _, _, _, _, _), meta_predicate, V), R = V), error(E, _), R = raised(E)).
t_pr91(R) :- catch((pr_try('$get_predicate_attribute'(pr_s1(_), meta_predicate, _), R)), error(E, _), R = raised(E)).
t_pr92(R) :- catch(('$get_predicate_attribute'(system:findall(_, _, _), meta_predicate, V), R = V), error(E, _), R = raised(E)).
t_pr93(R) :- catch((pr_try('$get_predicate_attribute'(pr_s1(_), tabled, _), R)), error(E, _), R = raised(E)).
t_pr94(R) :- catch((pr_try('$get_predicate_attribute'(pr_s1(_), nosuchkey, _), R)), error(E, _), R = raised(E)).
t_pr95(R) :- catch(('$get_predicate_attribute'(pr_s1(_), 1, _)), error(E, _), R = raised(E)).
t_pr96(R) :- catch(('$get_predicate_attribute'(pr_s1(_), _, _)), error(E, _), R = raised(E)).
t_pr97(R) :- catch((pr_try('$get_predicate_attribute'(pr_nosuch(_), defined, _), R)), error(E, _), R = raised(E)).
t_pr98(R) :- catch((pr_try('$get_predicate_attribute'(_, defined, _), R)), error(E, _), R = raised(E)).
t_pr99(R) :- catch(('$get_predicate_attribute'(pr_s1(_), size, V), integer(V), V > 0, R = ok), error(E, _), R = raised(E)).
t_pr100(R) :- catch(('$get_predicate_attribute'(pr_s1(_), last_modified_generation, V), integer(V), R = ok), error(E, _), R = raised(E)).
t_pr101(R) :- catch(('$get_predicate_attribute'(system:atom_length(_, _), locked, V), R = V), error(E, _), R = raised(E)).
t_pr102(R) :- catch(('$get_predicate_attribute'(pr_s1(_), transparent, V), R = V), error(E, _), R = raised(E)).
t_pr103(R) :- catch((assertz(pr_pi(1)), assertz(pr_pi(2)), assertz(pr_pi(3)), pr_pi(2), pr_try('$get_predicate_attribute'(pr_pi(_), primary_index, _), R)), error(E, _), R = raised(E)).
t_pr104(R) :- catch((assertz(pr_ga2(1)), '$get_predicate_attribute'(pr_ga2(_), defined, V), R = V), error(E, _), R = raised(E)).
t_pr105(R) :- catch((pr_u, '$get_predicate_attribute'(pr_u, number_of_clauses, V), R = V), error(E, _), R = raised(E)).
t_pr106(R) :- catch((assertz(pr_a8(1)), assertz(pr_a8(2)), retract(pr_a8(1)), abolish(pr_a8/1), assertz(pr_a8(3)), '$get_predicate_attribute'(pr_a8(_), number_of_clauses, V), findall(X, pr_a8(X), L), R = V-L), error(E, _), R = raised(E)).
t_pr107(R) :- catch((assertz((pr_a9(X) :- X > 0)), assertz(pr_a9(1)), abolish(pr_a9/1), assertz(pr_a9(5)), '$get_predicate_attribute'(pr_a9(_), number_of_rules, V), R = V), error(E, _), R = raised(E)).
t_pr108(R) :- catch((assertz(pr_a10(_, _)), meta_predicate(pr_a10(0, ?)), abolish(pr_a10/2), assertz(pr_a10(1, 2)), pr_try('$get_predicate_attribute'(pr_a10(_, _), meta_predicate, _), R)), error(E, _), R = raised(E)).
t_pr109(R) :- catch((pr_try(current_predicate(_:pr_s1/1), R)), error(E, _), R = raised(E)).
t_pr110(R) :- catch((pr_try('$c_current_predicate'(_, user:_), R)), error(E, _), R = raised(E)).
t_pr111(R) :- catch((abolish(pr_x, 1000000)), error(E, _), R = raised(E)).
t_pr112(R) :- catch((assertz(pr_a11(1)), abolish(pr_a11/1), findall(A, current_predicate(pr_a11/A), R)), error(E, _), R = raised(E)).
t_pr113(R) :- catch((pr_try('$get_predicate_attribute'(pr_s7(_), number_of_clauses, _), R)), error(E, _), R = raised(E)).
t_pr114(R) :- catch((pr_try('$get_predicate_attribute'(pr_s7(_), number_of_rules, _), R)), error(E, _), R = raised(E)).
t_pr115(R) :- catch((assertz(pr_sz(1)), '$get_predicate_attribute'(pr_sz(_), size, S1), assertz(pr_sz(2)), assertz(pr_sz(3)), '$get_predicate_attribute'(pr_sz(_), size, S3), S3 > S1, R = ok), error(E, _), R = raised(E)).
t_pr116(R) :- catch((pr_try('$get_predicate_attribute'(system:atom_length(_, _), last_modified_generation, _), R)), error(E, _), R = raised(E)).
t_pr117(R) :- catch((assertz(pr_pi2(1, a)), assertz(pr_pi2(2, b)), assertz(pr_pi2(3, c)), pr_pi2(2, _), '$get_predicate_attribute'(pr_pi2(_, _), primary_index, V), R = V), error(E, _), R = raised(E)).
t_pr118(R) :- catch((findall(X, pr_ld1(X), R)), error(E, _), R = raised(E)).
t_pr119(R) :- catch((pr_try('$get_predicate_attribute'(pr_ld1(_), dynamic, _), R)), error(E, _), R = raised(E)).
t_pr120(R) :- catch((pr_try(pr_ld2(_), R)), error(E, _), R = raised(E)).
t_pr121(R) :- catch((findall(X, pr_ld3(X), R)), error(E, _), R = raised(E)).
t_pr122(R) :- catch((findall(X, pr_ld4(X), R)), error(E, _), R = raised(E)).
t_pr123(R) :- catch((findall(X, pr_wq(X), R)), error(E, _), R = raised(E)).
t_pr124(R) :- catch((pr_try('$get_predicate_attribute'(pr_wq(_), imported, _), R)), error(E, _), R = raised(E)).
t_pr125(R) :- catch(('$declare_module'(mrq, user, user, '/pr/q.pl', 1, false), '$set_source_module'(user), pr_try(mrq:qs(_), R)), error(E, _), R = raised(E)).
t_pr126(R) :- catch((pr_try('$get_predicate_attribute'(mrq:qs(_), defined, _), R)), error(E, _), R = raised(E)).
t_pr127(R) :- catch((assertz((pr_a12(X) :- X > 0)), assertz(pr_a12(1)), assertz(pr_a12(2)), abolish(pr_a12/1), assertz(pr_a12(5)), '$get_predicate_attribute'(pr_a12(_), number_of_rules, V0), assertz((pr_a12(Y) :- Y > 1)), '$get_predicate_attribute'(pr_a12(_), number_of_rules, V1), R = [V0, V1]), error(E, _), R = raised(E)).
