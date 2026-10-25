
qq(u).
set_class(M, C, R) :-
    catch(( set_module(M:class(C)), '$module_property'(M, class(K)), R = K ),
          error(E, Ctx), R = E-Ctx).
t_s01(R) :- ('$current_source_module'(R)).
t_s02(R) :- ('$current_typein_module'(R)).
t_s03(R) :- ('$set_source_module'(sm_a), '$current_source_module'(A), '$set_source_module'(user), '$current_source_module'(B), R = A-B).
t_s04(R) :- ('$set_typein_module'(tm_a), '$current_typein_module'(A), '$set_typein_module'(user), '$current_typein_module'(B), R = A-B).
t_s05(R) :- ('$set_source_module'(sm_b), '$set_typein_module'(tm_b), '$current_source_module'(S), '$current_typein_module'(T), '$set_source_module'(user), '$set_typein_module'(user), R = S-T).
t_s06(R) :- (catch('$set_source_module'(_), error(E, C), true), R = E-C).
t_s07(R) :- (catch('$set_source_module'(1), error(E, C), true), R = E-C).
t_s08(R) :- (catch('$set_typein_module'(f(x)), error(E, C), true), R = E-C).
t_s09(R) :- ('$set_source_module'('[]'), '$current_source_module'(M), '$set_source_module'(user), ( M == [] -> R = nil ; R = text )).
t_s10(R) :- ('$set_source_module'([]), '$current_source_module'(M), '$set_source_module'(user), ( M == [] -> R = nil ; R = text )).
t_s11(R) :- ('$set_source_module'(sm_new), '$set_source_module'(user), '$module_property'(sm_new, class(R))).
t_s12(R) :- ('$set_source_module'('$sm_sys'), '$set_source_module'(user), '$module_property'('$sm_sys', class(R))).
t_m01(R) :- ('$module_property'(user, class(R))).
t_m02(R) :- ('$module_property'(system, class(R))).
t_m03(R) :- (( '$module_property'(mp_none_zz, class(C)) -> R = C ; R = no )).
t_m04(R) :- ('$module_property'(user, exports(R))).
t_m05(R) :- ('$module_property'(system, exports(R))).
t_m06(R) :- (( '$module_property'(user, file(_)) -> R = yes ; R = no )).
t_m07(R) :- (( '$module_property'(user, line_count(_)) -> R = yes ; R = no )).
t_m08(R) :- (catch('$module_property'(user, foo), error(E, C), true), R = E-C).
t_m09(R) :- (catch('$module_property'(user, foo(1)), error(E, C), true), R = E-C).
t_m10(R) :- (catch('$module_property'(user, _), error(E, C), true), R = E-C).
t_m11(R) :- (catch('$module_property'(1, class(_)), error(E, C), true), R = E-C).
t_m12(R) :- (catch('$module_property'(_, class(_)), error(E, C), true), R = E-C).
t_m13(R) :- (( '$module_property'(user, program_space(_)) -> R = yes ; R = no )).
t_m14(R) :- ('$module_property'(system, size(S)), '$module_property'(system, program_size(P)), '$module_property'(system, last_modified_generation(G)), ( integer(S), S > 0, integer(P), P >= 0, integer(G), G >= 0 -> R = ints ; R = other )).
t_m15(R) :- ('$set_source_module'(pz_m), '$set_source_module'(user), '$module_property'(pz_m, program_size(P0)), '$module_property'(pz_m, last_modified_generation(G0)), assertz(pz_m:f(1)), '$module_property'(pz_m, program_size(P1)), '$module_property'(pz_m, last_modified_generation(G1)), assertz(pz_m:f(2)), '$module_property'(pz_m, program_size(P2)), '$module_property'(pz_m, last_modified_generation(G2)), retract(pz_m:f(1)), '$module_property'(pz_m, program_size(P3)), '$module_property'(pz_m, last_modified_generation(G3)), ( P0 == 0, G0 == 0, P1 > P0, P2 > P1, P3 < P2, P3 == P1, G1 > G0, G2 > G1, G3 > G2 -> R = ok ; R = [P0,P1,P2,P3,G0,G1,G2,G3] )).
t_c01(R) :- (assertz(cb1:q(1)), assertz(cb2:q(2)), assertz(cb1:qq(c)), add_import_module(cm1, cb1, start), G = cm1:q(X), call(G), R = X).
t_c02(R) :- (add_import_module(cm1, cb2, start), G = cm1:q(X), call(G), R = X).
t_c03(R) :- (add_import_module(cm1, cb1, end), G = cm1:q(X), call(G), R = X).
t_c04(R) :- (delete_import_module(cm1, cb2), G = cm1:q(X), call(G), R = X).
t_c05(R) :- (( delete_import_module(cm1, cb2) -> R = yes ; R = no )).
t_c06(R) :- (add_import_module(cm3, cb1, end), G = cm3:qq(X), call(G), R = X).
t_c07(R) :- (add_import_module(cm4, cb1, start), G = cm4:qq(X), call(G), R = X).
t_c08(R) :- (add_import_module(cm5, cb1, middle), G = cm5:qq(X), call(G), R = X).
t_c09(R) :- (catch(add_import_module(user, cm4, start), error(E, C), true), R = E-C).
t_c10(R) :- (catch(add_import_module(cm4, cm4, start), error(E, C), true), R = E-C).
t_c11(R) :- (add_import_module(cm4, user, end), G = cm4:qq(X), call(G), R = X).
t_c12(R) :- (catch(add_import_module(_, user, start), error(E, C), true), R = E-C).
t_c13(R) :- (catch(add_import_module(cm4, _, start), error(E, C), true), R = E-C).
t_c14(R) :- (catch(add_import_module(cm4, user, _), error(E, C), true), R = E-C).
t_c15(R) :- (catch(add_import_module(cm4, user, 1), error(E, C), true), R = E-C).
t_c16(R) :- (catch(add_import_module(1, user, start), error(E, C), true), R = E-C).
t_c17(R) :- (catch(add_import_module(system, user, start), error(E, C), true), R = E-C).
t_c18(R) :- (G = cm4:qq(X), call(G), R = X).
t_c19(R) :- (set_module(cs1:base(cb1)), G = cs1:qq(X), call(G), R = X).
t_c20(R) :- (set_module(cm4:base(cb2)), G = cm4:qq(X), call(G), R = X).
t_c21(R) :- (catch(set_module(cs1:base(cs1)), error(E, C), true), R = E-C).
t_c22(R) :- (catch(set_module(base(user)), error(E, C), true), R = E-C).
t_c23(R) :- ('$set_typein_module'(cs2), set_module(base(cb1)), '$set_typein_module'(user), G = cs2:qq(X), call(G), R = X).
t_c24(R) :- (( delete_import_module(cs1, cb1) -> R = yes ; R = no )).
t_c25(R) :- (G = cs1:qq(X), call(G), R = X).
t_k01(R) :- (set_class(cl1, library, R)).
t_k02(R) :- (set_class(cl1, temporary, R)).
t_k03(R) :- (set_class(cl1, user, R)).
t_k04(R) :- (set_class(cl1, temporary, R)).
t_k05(R) :- (assertz(cl2:f), set_class(cl2, temporary, R)).
t_k06(R) :- (set_class(cl2, foo, R)).
t_k07(R) :- (set_class(cl2, 1, R)).
t_k08(R) :- (set_class(cl2, _, R)).
t_k09(R) :- (set_class(cl2, test, R)).
t_k10(R) :- (set_class(cl2, development, R)).
t_k11(R) :- (set_class(cl2, system, R)).
t_k12(R) :- (set_class(cl2, user, R)).
t_k13(R) :- (catch(set_module(user:class(temporary)), error(E, C), true), R = E-C).
t_p01(R) :- (set_module(ps1:program_space(0)), ( '$module_property'(ps1, program_space(_)) -> R = yes ; R = no )).
t_p02(R) :- (catch(set_module(ps1:program_space(foo)), error(E, C), true), R = E-C).
t_p03(R) :- (catch(set_module(ps1:program_space(-1)), error(E, C), true), R = E-C).
t_p04(R) :- (catch(set_module(ps1:program_space(_)), error(E, C), true), R = E-C).
t_p05(R) :- (catch(set_module(foo), error(E, C), true), R = E-C).
t_p06(R) :- (catch(set_module(foo(1)), error(E, C), true), R = E-C).
t_p07(R) :- (catch(set_module(_), error(E, C), true), R = E-C).
t_p08(R) :- (catch(set_module(cs1:class(_)), error(E, C), true), R = E-C).
t_p09(R) :- (catch(set_module(cs1:base(1)), error(E, C), true), R = E-C).
t_p10(R) :- (catch(set_module(cs1:base(_)), error(E, C), true), R = E-C).
t_p11(R) :- (catch(set_module(1:class(user)), error(E, C), true), R = E-C).
t_p12(R) :- (catch(set_module(_:class(user)), error(E, C), true), R = E-C).
t_p13(R) :- (catch(set_module(a:b:foo(1)), error(E, C), true), R = E-C).
t_e01(R) :- (assertz(ec_new:f), '$module_property'(ec_new, class(R))).
t_e02(R) :- (( clause(f, _) -> R = leaked ; clause(ec_new:f, B), R = B )).
t_e03(R) :- (G = ec_new:f, ( call(G) -> R = yes ; R = no )).
