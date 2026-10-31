:- assertz(mdy:dp(1)).
:- assertz(user:sup_p(7)).
sup_s(8).
mb_done :- '$set_source_module'(user), '$set_typein_module'(user).
t_a01(R) :- catch(('$declare_module'(mna, user, user, '/mb/f1.pl', 3, false), '$current_source_module'(S), '$module_property'(mna, class(C)), '$module_property'(mna, file(F)), '$module_property'(mna, line_count(L)), R = [S, C, F, L]), error(F, _), R = raised(F)), mb_done.
t_a02(R) :- catch(('$declare_module'(mna, user, user, '/mb/f1.pl', 9, false), '$module_property'(mna, line_count(L)), '$module_property'(mna, file(F)), R = L-F), error(F, _), R = raised(F)), mb_done.
t_a03(R) :- catch(('$declare_module'(mna, user, user, '/mb/f2.pl', 1, false), R = ok), error(F, _), R = raised(F)), mb_done.
t_a04(R) :- catch(('$declare_module'(mna, library, user, '/mb/f2.pl', 2, true), '$module_property'(mna, class(C)), '$module_property'(mna, file(F)), '$module_property'(mna, line_count(L)), R = [C, F, L]), error(F, _), R = raised(F)), mb_done.
t_a05(R) :- catch(('$declare_module'(mna, user, user, '/mb/f3.pl', 2, 1), '$module_property'(mna, file(F)), R = F), error(F, _), R = raised(F)), mb_done.
t_a06(R) :- catch(('$declare_module'(mnb, user, user, '/mb/f1.pl', 1, false), catch('$declare_module'(mnb, system, user, '/mb/f2.pl', 1, false), error(E, _), true), '$module_property'(mnb, class(C)), R = E-C), error(F, _), R = raised(F)), mb_done.
t_a07(R) :- catch((findall(Cl-C, (member(Cl, [user, system, library, test, development, temporary, weird]), atom_concat(mbc_, Cl, M), '$declare_module'(M, Cl, user, '/mb/cls.pl', 1, false), '$module_property'(M, class(C))), R)), error(F, _), R = raised(F)), mb_done.
t_a08(R) :- catch(('$declare_module'(_, user, user, '/mb/f.pl', 1, false), R = ok), error(F, _), R = raised(F)), mb_done.
t_a09(R) :- catch(('$declare_module'(1, user, user, '/mb/f.pl', 1, false), R = ok), error(F, _), R = raised(F)), mb_done.
t_a10(R) :- catch(('$declare_module'(f(x), user, user, '/mb/f.pl', 1, false), R = ok), error(F, _), R = raised(F)), mb_done.
t_a11(R) :- catch(('$declare_module'(mbe1, _, user, '/mb/f.pl', 1, false), R = ok), error(F, _), R = raised(F)), mb_done.
t_a12(R) :- catch(('$declare_module'(mbe1, user, _, '/mb/f.pl', 1, false), R = ok), error(F, _), R = raised(F)), mb_done.
t_a13(R) :- catch(('$declare_module'(mbe1, user, user, _, 1, false), R = ok), error(F, _), R = raised(F)), mb_done.
t_a14(R) :- catch(('$declare_module'(mbe1, user, user, '/mb/f.pl', a, false), R = ok), error(F, _), R = raised(F)), mb_done.
t_a15(R) :- catch(('$declare_module'(mbe1, user, user, '/mb/f.pl', _, false), R = ok), error(F, _), R = raised(F)), mb_done.
t_a16(R) :- catch(('$declare_module'(mbe1, user, user, '/mb/f.pl', 1, maybe), R = ok), error(F, _), R = raised(F)), mb_done.
t_a17(R) :- catch(('$declare_module'(mbe1, user, user, '/mb/f.pl', 1, _), R = ok), error(F, _), R = raised(F)), mb_done.
t_a18(R) :- catch(('$declare_module'(mbe1, user, user, '/mb/f.pl', 1.5, false), R = ok), error(F, _), R = raised(F)), mb_done.
t_a19(R) :- catch(('$declare_module'(mnc, user, user, '/mb/g.pl', 1, false), export(mnc:pe/1), '$module_property'(mnc, exports(L1)), '$declare_module'(mnc, user, user, '/mb/g.pl', 2, false), '$module_property'(mnc, exports(L2)), R = L1-L2), error(F, _), R = raised(F)), mb_done.
t_a20(R) :- catch((export(mpr:ex/0), '$declare_module'(mpr, user, user, '/mb/j.pl', 1, false), '$module_property'(mpr, exports(L)), R = L), error(F, _), R = raised(F)), mb_done.
t_a21(R) :- catch(('$declare_module'(mdy, user, user, '/mb/i.pl', 1, false), mdy:dp(X), R = X), error(F, _), R = raised(F)), mb_done.
t_b01(R) :- catch(('$declare_module'(mns1, user, user, '/mb/h.pl', 1, false), mns1:sup_p(X), R = X), error(F, _), R = raised(F)), mb_done.
t_b02(R) :- catch(('$declare_module'(mns2, user, system, '/mb/h.pl', 1, false), catch(mns2:sup_p(_), error(E, _), true), R = E), error(F, _), R = raised(F)), mb_done.
t_b03(R) :- catch(('$declare_module'(mns3, user, mns3, '/mb/h.pl', 1, false), R = ok), error(F, _), R = raised(F)), mb_done.
t_b04(R) :- catch(('$declare_module'(mns4, user, mnsup4, '/mb/h.pl', 1, false), '$module_property'(mnsup4, class(C)), mnsup4:assertz(zz4(1)), mns4:zz4(X), R = C-X), error(F, _), R = raised(F)), mb_done.
t_b05(R) :- catch(('$declare_module'(mns4, user, system, '/mb/h.pl', 1, false), catch(mns4:zz4(_), error(E, _), true), R = E), error(F, _), R = raised(F)), mb_done.
t_b06(R) :- catch(('$declare_module'(mns5, user, user, '/mb/h.pl', 1, false), mns5:sup_s(X0), '$declare_module'(mns5, user, system, '/mb/h.pl', 1, false), catch(mns5:sup_s(_), error(E, _), true), R = X0-E), error(F, _), R = raised(F)), mb_done.
t_c01(R) :- catch(('$declare_module'(mbsys, system, user, '/mb/t.pl', 1, false), '$module_property'(mbsys, class(C)), R = C), error(F, _), R = raised(F)), mb_done.
t_c02(R) :- catch(('$declare_module'(mtd10, temporary, user, '/mb/t.pl', 1, false), '$declare_module'(mtd10, user, user, '/mb/t.pl', 1, false), '$module_property'(mtd10, class(C)), R = C), error(F, _), R = raised(F)), mb_done.
t_d01(R) :- catch(('$declare_module'(mtd1, temporary, user, '/mb/t.pl', 1, false), '$destroy_module'(mtd1), ( '$module_property'(mtd1, class(C)) -> R = still(C) ; R = gone )), error(F, _), R = raised(F)), mb_done.
t_d02(R) :- catch(('$declare_module'(mtd2, temporary, user, '/mb/t.pl', 1, false), '$current_source_module'(S1), '$destroy_module'(mtd2), '$current_source_module'(S2), R = S1-S2), error(F, _), R = raised(F)), mb_done.
t_d03(R) :- catch((set_module(mtd3:class(temporary)), '$set_typein_module'(mtd3), '$destroy_module'(mtd3), '$current_typein_module'(T), R = T), error(F, _), R = raised(F)), mb_done.
t_d04(R) :- catch(('$destroy_module'(mtd4nx), '$destroy_module'(mtd4nx), R = ok), error(F, _), R = raised(F)), mb_done.
t_d05(R) :- catch(('$destroy_module'(mna), R = ok), error(F, _), R = raised(F)), mb_done.
t_d06(R) :- catch(('$destroy_module'(user), R = ok), error(F, _), R = raised(F)), mb_done.
t_d07(R) :- catch(('$destroy_module'(system), R = ok), error(F, _), R = raised(F)), mb_done.
t_d08(R) :- catch(('$destroy_module'(_), R = ok), error(F, _), R = raised(F)), mb_done.
t_d09(R) :- catch(('$destroy_module'(1), R = ok), error(F, _), R = raised(F)), mb_done.
t_d10(R) :- catch(('$destroy_module'(mbsys), R = ok), error(F, _), R = raised(F)), mb_done.
t_d11(R) :- catch(('$destroy_module'(mtd10), R = ok), error(F, _), R = raised(F)), mb_done.
t_d12(R) :- catch(('$declare_module'(mtd5, temporary, user, '/mb/t.pl', 1, false), '$destroy_module'(mtd5), '$destroy_module'(mtd5), R = ok), error(F, _), R = raised(F)), mb_done.
t_e01(R) :- catch(('$declare_module'(mtd6, temporary, user, '/mb/t.pl', 1, false), assertz(mtd6:tp(1)), mtd6:tp(X0), '$destroy_module'(mtd6), catch(mtd6:tp(_), error(E, _), true), R = X0-E), error(F, _), R = raised(F)), mb_done.
t_e02(R) :- catch(('$declare_module'(mtd7, temporary, user, '/mb/t.pl', 1, false), assertz(mtd7:tq(1)), '$destroy_module'(mtd7), '$declare_module'(mtd7, user, user, '/mb/t2.pl', 1, false), '$module_property'(mtd7, class(C)), '$module_property'(mtd7, file(F)), catch(mtd7:tq(_), error(E, _), true), R = C-F-E), error(F, _), R = raised(F)), mb_done.
t_e03(R) :- catch(('$declare_module'(mtd11, temporary, user, '/mb/t.pl', 1, false), export(mtd11:te/1), '$destroy_module'(mtd11), '$declare_module'(mtd11, user, user, '/mb/t.pl', 1, false), '$module_property'(mtd11, exports(L)), R = L), error(F, _), R = raised(F)), mb_done.
t_e04(R) :- catch(('$declare_module'(mtd12, temporary, user, '/mb/t.pl', 1, false), '$declare_module'(mtd12b, temporary, mtd12, '/mb/t.pl', 1, false), '$destroy_module'(mtd12), '$module_property'(mtd12b, class(C)), R = C), error(F, _), R = raised(F)), mb_done.
t_f01(R) :- catch(('$declare_module'(mtd8, temporary, user, '/mb/t.pl', 1, false), catch(assertz((mbtb :- mtd8:foo)), error(E, _), true), R = E), error(F, _), R = raised(F)), mb_done.
t_f02(R) :- catch((call(mtd8:true), R = ok), error(F, _), R = raised(F)), mb_done.
t_f03(R) :- catch((assertz((mbtb3 :- mna:foo)), R = ok), error(F, _), R = raised(F)), mb_done.
t_f04(R) :- catch(('$destroy_module'(mtd8), assertz((mbtb2 :- mtd8:foo)), R = ok), error(F, _), R = raised(F)), mb_done.
t_f05(R) :- catch(('$declare_module'(mtd8, temporary, user, '/mb/t.pl', 1, false), '$module_property'(mtd8, class(C)), R = C), error(F, _), R = raised(F)), mb_done.
