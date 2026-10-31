:- assertz(ma:pa(1)).
:- assertz(ma:pa(2)).
:- assertz(ma:pb(a, b)).
:- assertz(ma:pc).
:- assertz(mb:pd(x)).
:- assertz(mc:pa(local)).
:- assertz(md:pf(1)).
:- assertz(md:pg(2)).
:- assertz(mwq:qq(42)).
:- assertz(mwq:rr(5)).
:- assertz(mauto:dummy).
:- ma:export(pdir/0).
t_e01(R) :- catch((export(ma:pa/1), '$module_property'(ma, exports(L)), msort(L, R)), error(F, _), R = raised(F)).
t_e02(R) :- catch((ma:export(pb/2), '$module_property'(ma, exports(L)), msort(L, R)), error(F, _), R = raised(F)).
t_e03(R) :- catch((export(ma:(pa/1, pc/0)), '$module_property'(ma, exports(L)), msort(L, R)), error(F, _), R = raised(F)).
t_e04(R) :- catch((export(ma:[pa/1]), R = ok), error(F, _), R = raised(F)).
t_e05(R) :- catch((export(ma:brandnew/0), '$module_property'(ma, exports(L)), msort(L, R)), error(F, _), R = raised(F)).
t_e06(R) :- catch(('$undefined_export'(ma, R0), msort(R0, R)), error(F, _), R = raised(F)).
t_e07(R) :- catch((assertz(ma:brandnew), '$undefined_export'(ma, R)), error(F, _), R = raised(F)).
t_e08(R) :- catch((export(ma:undefp/3), export(ma:undefp/3), '$undefined_export'(ma, R)), error(F, _), R = raised(F)).
t_e09(R) :- catch((export(ma:dcgp//2), '$module_property'(ma, exports(L)), msort(L, R)), error(F, _), R = raised(F)).
t_e10(R) :- catch((assertz(user:pu(1)), export(ma:pu/1), '$undefined_export'(ma, R0), msort(R0, R)), error(F, _), R = raised(F)).
t_e11(R) :- catch((export(_), R = ok), error(F, _), R = raised(F)).
t_e12(R) :- catch((export(foo), R = ok), error(F, _), R = raised(F)).
t_e13(R) :- catch((export(foo/a), R = ok), error(F, _), R = raised(F)).
t_e14(R) :- catch((export(foo/_), R = ok), error(F, _), R = raised(F)).
t_e15(R) :- catch((export(_/1), R = ok), error(F, _), R = raised(F)).
t_e16(R) :- catch((export(1/2), R = ok), error(F, _), R = raised(F)).
t_e17(R) :- catch((export(foo/(-1)), R = ok), error(F, _), R = raised(F)).
t_e18(R) :- catch((export(ma:_), R = ok), error(F, _), R = raised(F)).
t_e19(R) :- catch((export((ma:pa/1, _)), R = ok), error(F, _), R = raised(F)).
t_e20(R) :- catch((export(ma:(pa/1, bad)), R = ok), error(F, _), R = raised(F)).
t_e21(R) :- catch((export(nomx:p/1), '$module_property'(nomx, exports(R))), error(F, _), R = raised(F)).
t_e22(R) :- catch((export(ma:atom_length/2), '$module_property'(ma, exports(L)), msort(L, R)), error(F, _), R = raised(F)).
t_e23(R) :- catch((export(user:exuser/0), '$module_property'(user, exports(L)), msort(L, R)), error(F, _), R = raised(F)).
t_e24(R) :- catch((X = (ma:pa/1, X), catch(export(X), error(type_error(T, _), _), true), R = T), error(F, _), R = raised(F)).
t_e25(R) :- catch((export(ma:(n1/0, n2/0, n3/0)), '$module_property'(ma, exports(L)), msort(L, R)), error(F, _), R = raised(F)).
t_u01(R) :- catch(('$undefined_export'(_, R)), error(F, _), R = raised(F)).
t_u02(R) :- catch(('$undefined_export'(1, R)), error(F, _), R = raised(F)).
t_u03(R) :- catch(('$undefined_export'(nomodule_zz, R)), error(F, _), R = raised(F)).
t_u04(R) :- catch((( '$undefined_export'(ma, [a]) -> R = yes ; R = no )), error(F, _), R = raised(F)).
t_u05(R) :- catch(('$undefined_export'(md, R)), error(F, _), R = raised(F)).
t_d01(R) :- catch(('$def_modules'([pu/1, pa/1], R)), error(F, _), R = raised(F)).
t_d02(R) :- catch(('$def_modules'(ma:[pa/1, pb/2, pc/0, nosuch/0], R)), error(F, _), R = raised(F)).
t_d03(R) :- catch(('$def_modules'(mc:[pa/1, pu/1], R0), msort(R0, R)), error(F, _), R = raised(F)).
t_d04(R) :- catch(('$def_modules'(nosuchmod:[pu/1], R)), error(F, _), R = raised(F)).
t_d05(R) :- catch(('$def_modules'('$nosuch':[assertz/1], R)), error(F, _), R = raised(F)).
t_d06(R) :- catch(('$def_modules'([], R)), error(F, _), R = raised(F)).
t_d07(R) :- catch(('$def_modules'([nothing_at_all/9], R)), error(F, _), R = raised(F)).
t_d08(R) :- catch(('$def_modules'([a/1, b/1, c/1, d/1, e/1, f/1, g/1, h/1, i/1, j/1, k/1], R)), error(F, _), R = raised(F)).
t_d09(R) :- catch(('$def_modules'([pu/1|_], R)), error(F, _), R = raised(F)).
t_d10(R) :- catch(('$def_modules'(foo, R)), error(F, _), R = raised(F)).
t_d11(R) :- catch(('$def_modules'([foo], R)), error(F, _), R = raised(F)).
t_d12(R) :- catch(('$def_modules'([ma:pa/1], R)), error(F, _), R = raised(F)).
t_d18(R) :- catch(('$def_modules'(ma:[undefp/3, pu/1], R)), error(F, _), R = raised(F)).
t_d19(R) :- catch(('$def_modules'('$nosuch':[pu/1], R)), error(F, _), R = raised(F)).
t_d13(R) :- catch(('$current_source_module'(Old), '$set_source_module'(ma), '$def_modules'([pa/1, pu/1], R0), '$set_source_module'(Old), msort(R0, R)), error(F, _), R = raised(F)).
t_i01(R) :- catch((mi:import(ma:pa/1), findall(X, mi:pa(X), R)), error(F, _), R = raised(F)).
t_i02(R) :- catch((mi:import(ma:pa/1), findall(X, mi:pa(X), R)), error(F, _), R = raised(F)).
t_i03(R) :- catch((mi:import(mb:pd/1), findall(X, mi:pd(X), R)), error(F, _), R = raised(F)).
t_i04(R) :- catch((mc:import(ma:pa/1), R = ok), error(F, _), R = raised(F)).
t_i05(R) :- catch((mi:import(mc:pa/1), R = ok), error(F, _), R = raised(F)).
t_i06(R) :- catch((import(ma:pa/1), findall(X, user:pa(X), R)), error(F, _), R = raised(F)).
t_i07(R) :- catch((import(user:ma:pb/2), findall(X-Y, pb(X, Y), R)), error(F, _), R = raised(F)).
t_i08(R) :- catch((import(_), R = ok), error(F, _), R = raised(F)).
t_i09(R) :- catch((import(foo), R = ok), error(F, _), R = raised(F)).
t_i10(R) :- catch((import(foo/a), R = ok), error(F, _), R = raised(F)).
t_i11(R) :- catch((import(ma:_), R = ok), error(F, _), R = raised(F)).
t_i12(R) :- catch((import(selfimp/1), R = ok), error(F, _), R = raised(F)).
t_i13(R) :- catch((mi:import(ma:undefq/2), mi:undefq(1, 2), R = ok), error(F, _), R = raised(F)).
t_u06(R) :- catch((export(mi:undefq/2), '$undefined_export'(mi, R)), error(F, _), R = raised(F)).
t_i14(R) :- catch((export(mx:late/1), mj:import(mx:late/1), assertz(mx:late(7)), findall(X, mj:late(X), R)), error(F, _), R = raised(F)).
t_i15(R) :- catch((catch(mfx:qq(_), error(_, _), true), mfz:import(mfx:qq/1), mfx:import(mwq:qq/1), mfz:qq(A), mfx:qq(B), R = A-B), error(F, _), R = raised(F)).
t_i16(R) :- catch((catch(mgx:rr(_), error(_, _), true), mgx:import(mwq:rr/1), mgx:import(mwq:rr/1), mgx:rr(R)), error(F, _), R = raised(F)).
t_i17(R) :- catch((assertz(user:zz(11)), mhx:import(mauto:zz/1), findall(X, mhx:zz(X), R)), error(F, _), R = raised(F)).
t_w01(R) :- catch((mw:'$import'(ma:pb/2, weak), findall(X-Y, mw:pb(X, Y), R)), error(F, _), R = raised(F)).
t_w02(R) :- catch((assertz(md:pa(local_md)), md:'$import'(ma:pa/1, weak), findall(X, md:pa(X), R)), error(F, _), R = raised(F)).
t_w03(R) :- catch((md:'$import'(ma:pa/1, strong), R = ok), error(F, _), R = raised(F)).
t_w04(R) :- catch(('$import'(ma:pa/1, bogus), R = ok), error(F, _), R = raised(F)).
t_w05(R) :- catch(('$import'(ma:pa/1, _), R = ok), error(F, _), R = raised(F)).
t_w06(R) :- catch(('$import'(ma:pa/1, 1), R = ok), error(F, _), R = raised(F)).
t_w07(R) :- catch((mw:'$import'(ma:pb/2, weak), mw:'$import'(ma:pb/2, strong), findall(X-Y, mw:pb(X, Y), R)), error(F, _), R = raised(F)).
t_w08(R) :- catch((mw2:'$import'(ma:pb/2, strong), findall(X-Y, mw2:pb(X, Y), R)), error(F, _), R = raised(F)).
t_w09(R) :- catch((mw3:'$import'(ma:pa/1, weak), mw3:import(mc:pa/1), R = ok), error(F, _), R = raised(F)).
t_d14(R) :- catch(('$def_modules'(mi:[pa/1], R)), error(F, _), R = raised(F)).
t_d15(R) :- catch(('$def_modules'([pa/1, pb/2], R0), msort(R0, R)), error(F, _), R = raised(F)).
t_d16(R) :- catch(('$def_modules'(ma:[pa/1], R)), error(F, _), R = raised(F)).
t_d20(R) :- catch(('$def_modules'([ma:pa/1], R)), error(F, _), R = raised(F)).
t_d17(R) :- catch(('$def_modules'([pu/1, a/1, b/1, c/1, d/1, e/1, f/1, g/1, h/1, i/1], R)), error(F, _), R = raised(F)).
