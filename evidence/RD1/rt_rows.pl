rt_path(P) :- atom_concat('/home/shivaji1012/code/lk-rd1/evidence/RD1/rt_tmp', '/rt.txt', P).
rt_str(Text, S) :- open_string(Text, S).
rt_file(Text, S) :- rt_path(P), open(P, write, O), write(O, Text), close(O), open(P, read, S).
rt_bin(Text, S) :- rt_path(P), open(P, write, O), write(O, Text), close(O), open(P, read, S, [type(binary)]).
rt_out(S) :- rt_path(P), open(P, write, S).
rt_ctx(file(_, L, LP, C), file(L, LP, C)) :- !.
rt_ctx(stream(_, L, LP, C), stream(L, LP, C)) :- !.
rt_ctx(_, other).
rt_serr(G, R) :- catch((G, R = ok), error(F, C), (rt_ctx(C, C1), R = raised(F, C1))).
rt_serr_formal(G, R) :- catch((G, R = ok), error(F, _), R = raised(F)).
t_rt01(R) :- catch((rt_str('foo(X,Y,X). bar.', S), read(S,A), read(S,B), read(S,C), read(S,D), R = [A,B,C,D]), error(SsuE, _), R = raised(SsuE)).
t_rt02(R) :- catch((rt_str('42.', S), read(S,T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt03(R) :- catch((rt_str('f("ab", \'c d\', 0\'a, 1.5, [1,2|T], - 1, -(1), 1r3).', S), read(S,T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt04(R) :- catch((rt_str('', S), read(S,A), read(S,B), R = [A,B]), error(SsuE, _), R = raised(SsuE)).
t_rt05(R) :- catch((rt_str('   % only a comment\n /* and another */ ', S), read(S,T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt06(R) :- catch((rt_str('foo(1).', S), read(S, foo(2)), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt07(R) :- catch((rt_str('a. b.', S), read(S,_), read(S,b), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt08(R) :- catch((T = foo(_), rt_str('foo(7).', S), read(S,T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt09(R) :- catch((rt_str('X.', S), read(S,T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt10(R) :- catch((rt_str('f(X,Y,X).', S), read(S,T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt11(R) :- catch((rt_str('a.', S), close(S), read(S,_), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt12(R) :- catch((read(_, _), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt13(R) :- catch((read(foo, _), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt14(R) :- catch((rt_out(S), read(S,_), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt15(R) :- catch((rt_bin('A', S), read(S,_), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt16(R) :- catch((rt_bin('', S), read(S,T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt17(R) :- catch((rt_bin('foo(X). ', S), read(S,T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt18(R) :- catch((rt_file('foo(X, Y).\nbar.\n', S), read(S,A), read(S,B), read(S,C), R = [A,B,C]), error(SsuE, _), R = raised(SsuE)).
t_rt19(R) :- catch((rt_str('a. b.', S), read(S, a), read(S, c), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt20(R) :- catch((rt_str('a. b.', S), read(S, f(_)), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt21(R) :- catch((read(T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt22(R) :- catch((read(user_input, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt23(R) :- catch((read_term(T, [variable_names(Vs)]), R = T-Vs), error(SsuE, _), R = raised(SsuE)).
t_rt24(R) :- catch((read_term(user_input, T, [syntax_errors(error)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt25(R) :- catch((read_term(T, foo), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt26(R) :- catch((read_term(T, [variable_names(Vs)|_]), R = T-Vs), error(SsuE, _), R = raised(SsuE)).
t_rt30(R) :- catch((rt_str('foo(X,Y,X,_Z,_).', S), read_term(S,T,[variable_names(V)]), R = T-V), error(SsuE, _), R = raised(SsuE)).
t_rt31(R) :- catch((rt_str('foo(X,Y,X,_Z,_).', S), read_term(S,T,[variables(V)]), R = T-V), error(SsuE, _), R = raised(SsuE)).
t_rt32(R) :- catch((rt_str('foo(X,Y,X,_Z,_).', S), read_term(S,T,[singletons(V)]), R = T-V), error(SsuE, _), R = raised(SsuE)).
t_rt33(R) :- catch((rt_str('foo(X,Y,X,_Z,_).', S), read_term(S,T,[variable_names(N),variables(V),singletons(G)]), R = T-N-V-G), error(SsuE, _), R = raised(SsuE)).
t_rt34(R) :- catch((rt_str('foo(X,Y,X,_).', S), read_term(S,T,[singletons(warning)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt35(R) :- catch((rt_str('foo(X,_Y,_Y,__Z).', S), read_term(S,T,[singletons(G)]), R = T-G), error(SsuE, _), R = raised(SsuE)).
t_rt36(R) :- catch((rt_str('foo(a,b).', S), read_term(S,T,[variable_names(N),variables(V),singletons(G)]), R = T-N-V-G), error(SsuE, _), R = raised(SsuE)).
t_rt37(R) :- catch((rt_str('', S), read_term(S,T,[variable_names(N),variables(V),singletons(G),subterm_positions(P),term_position(TP)]), R = T-N-V-G-P-TP), error(SsuE, _), R = raised(SsuE)).
t_rt38(R) :- catch((rt_str('f(X).', S), read_term(S,T,[variable_names(['X'=1])]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt39(R) :- catch((rt_str('f(X).', S), read_term(S,T,[variable_names(foo)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt40(R) :- catch((rt_str('f(X).', S), read_term(S,T,[variables(foo)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt41(R) :- catch((rt_str('f(X,Y).', S), read_term(S,T,[variable_names(['X'=A|B])]), R = T-A-B), error(SsuE, _), R = raised(SsuE)).
t_rt42(R) :- catch((rt_str('f(X).', S), read_term(S,T,[variable_names(N),variable_names(M)]), R = T-N-M), error(SsuE, _), R = raised(SsuE)).
t_rt50(R) :- catch((rt_str('f(X).', S), read_term(S,T,foo), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt51(R) :- catch((rt_str('f(X).', S), read_term(S,T,[variable_names(V)|_]), R = T-V), error(SsuE, _), R = raised(SsuE)).
t_rt52(R) :- catch((rt_str('f(X).', S), read_term(S,T,[variable_names(V)|foo]), R = T-V), error(SsuE, _), R = raised(SsuE)).
t_rt53(R) :- catch((rt_str('f(X).', S), read_term(S,T,[_|foo]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt54(R) :- catch((rt_str('f(X).', S), read_term(S,T,[foo(bar)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt55(R) :- catch((rt_str('f(X).', S), read_term(S,T,[foo]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt56(R) :- catch((rt_str('f(X).', S), read_term(S,T,[syntax_errors(_)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt57(R) :- catch((rt_str('f(X).', S), read_term(S,T,[syntax_errors(bar)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt58(R) :- catch((rt_str('f(X).', S), read_term(S,T,[double_quotes(1)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt59(R) :- catch((rt_str('f(X).', S), read_term(S,T,[double_quotes(foo)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt60(R) :- catch((rt_str('f(X).', S), read_term(S,T,[cycles(maybe)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt61(R) :- catch((rt_str('f(X).', S), read_term(S,T,[module(1)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt62(R) :- catch((rt_str('f(X).', S), read_term(S,T,[module(_)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt63(R) :- catch((rt_str('f(X).', S), read_term(S,T,[back_quotes(foo)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt64(R) :- catch((rt_str('f(X).', S), read_term(S,T,[character_escapes(maybe)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt65(R) :- catch((rt_str('f(X).', S), read_term(S,T,[term_position(foo)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt66(R) :- catch((rt_str('f(X).', S), read_term(S,T,[subterm_positions(foo)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt67(R) :- catch((rt_str('f(X).', S), read_term(S,T,[variable_names(V),variable_names(W)]), R = T-V-W), error(SsuE, _), R = raised(SsuE)).
t_rt68(R) :- catch((rt_str('f(X).', S), read_term(S,T,[variable_names(V), module(M)]), R = T-V-M), error(SsuE, _), R = raised(SsuE)).
t_rt70(R) :- catch((read_term(_, T, []), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt71(R) :- catch((read_term(foo, T, []), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt72(R) :- catch((rt_out(S), read_term(S, T, []), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt73(R) :- catch((rt_bin('A', S), read_term(S, T, []), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt74(R) :- catch((rt_bin('f(X). ', S), read_term(S, T, [variable_names(V)]), R = T-V), error(SsuE, _), R = raised(SsuE)).
t_rt75(R) :- catch((rt_str('a.', S), close(S), read_term(S, T, []), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt76(R) :- catch((read_term(1, T, []), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt77(R) :- catch((read_term(f(x), T, []), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt80(R) :- catch((rt_file('a b. c.', S), read_term(S,T,[syntax_errors(fail)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt81(R) :- catch((rt_file('a b. c.', S), read_term(S,T,[syntax_errors(quiet)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt82(R) :- catch((rt_file('a b. c.', S), read_term(S,T,[syntax_errors(dec10)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt83(R) :- catch((rt_file('a b. c.', S), read_term(S,T,[syntax_errors(error)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt84(R) :- catch((rt_file('a b. c.', S), catch(read(S,_), _, true), read(S,T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt85(R) :- catch((rt_file('a b. c.', S), ( read_term(S,_,[syntax_errors(fail)]) -> true ; true ), read_term(S,U,[]), R = U), error(SsuE, _), R = raised(SsuE)).
t_rt86(R) :- catch((rt_file('a b. c.', S), ( read_term(S,_,[syntax_errors(quiet)]) -> true ; true ), read_term(S,U,[]), R = U), error(SsuE, _), R = raised(SsuE)).
t_rt100(R) :- catch((rt_serr((rt_file('a b.', S), read(S,_)), R)), error(SsuE, _), R = raised(SsuE)).
t_rt101(R) :- catch((rt_serr((rt_file('foo(.', S), read(S,_)), R)), error(SsuE, _), R = raised(SsuE)).
t_rt102(R) :- catch((rt_serr((rt_file('foo(', S), read(S,_)), R)), error(SsuE, _), R = raised(SsuE)).
t_rt103(R) :- catch((rt_serr((rt_file('\'abc', S), read(S,_)), R)), error(SsuE, _), R = raised(SsuE)).
t_rt104(R) :- catch((rt_serr((rt_file('foo(X,Y)', S), read(S,_)), R)), error(SsuE, _), R = raised(SsuE)).
t_rt105(R) :- catch((rt_serr((rt_file('f(a,).', S), read(S,_)), R)), error(SsuE, _), R = raised(SsuE)).
t_rt106(R) :- catch((rt_serr((rt_file('1 2.', S), read(S,_)), R)), error(SsuE, _), R = raised(SsuE)).
t_rt107(R) :- catch((rt_serr((rt_file(').', S), read(S,_)), R)), error(SsuE, _), R = raised(SsuE)).
t_rt108(R) :- catch((rt_serr((rt_file('a :- :- b.', S), read(S,_)), R)), error(SsuE, _), R = raised(SsuE)).
t_rt109(R) :- catch((rt_serr((rt_file('\n\n  foo bar baz.', S), read(S,_)), R)), error(SsuE, _), R = raised(SsuE)).
t_rt110(R) :- catch((rt_serr((rt_file('"abc', S), read(S,_)), R)), error(SsuE, _), R = raised(SsuE)).
t_rt111(R) :- catch((rt_serr((rt_file('a. b c. d.', S), read(S,_), read(S,_)), R)), error(SsuE, _), R = raised(SsuE)).
t_rt112(R) :- catch((rt_serr((rt_file('f(\'\\q\').', S), read(S,_)), R)), error(SsuE, _), R = raised(SsuE)).
t_rt113(R) :- catch((rt_serr((rt_file('/* abc', S), read(S,_)), R)), error(SsuE, _), R = raised(SsuE)).
t_rt114(R) :- catch((rt_serr((rt_file('foo.bar', S), read(S,_), read(S,_)), R)), error(SsuE, _), R = raised(SsuE)).
t_rt115(R) :- catch((rt_serr((rt_file('X = [a,b', S), read(S,_)), R)), error(SsuE, _), R = raised(SsuE)).
t_rt116(R) :- catch((rt_serr((rt_file('a b.', S), read_term(S,_,[syntax_errors(error)])), R)), error(SsuE, _), R = raised(SsuE)).
t_rt117(R) :- catch((rt_serr((rt_file('a b.', S), read_term(S,_,[syntax_errors(bar)])), R)), error(SsuE, _), R = raised(SsuE)).
t_rt118(R) :- catch((rt_serr((rt_file('a b.', S), read_term(S,_,[term_position(P), subterm_positions(Q)])), R)), error(SsuE, _), R = raised(SsuE)).
t_rt130(R) :- catch((rt_str('  foo(X, bar).', S), read_term(S,T,[term_position(P)]), R = T-P), error(SsuE, _), R = raised(SsuE)).
t_rt131(R) :- catch((rt_str('  foo(X, bar).', S), read_term(S,T,[subterm_positions(P)]), R = T-P), error(SsuE, _), R = raised(SsuE)).
t_rt132(R) :- catch((rt_file('  foo(X, bar).', S), read_term(S,T,[term_position(P)]), R = T-P), error(SsuE, _), R = raised(SsuE)).
t_rt133(R) :- catch((rt_str('\n\n  x.', S), read_term(S,T,[term_position(P)]), R = T-P), error(SsuE, _), R = raised(SsuE)).
t_rt134(R) :- catch((rt_str('foo(a,b). x', S), read_term(S,T,[subterm_positions(P)]), R = T-P), error(SsuE, _), R = raised(SsuE)).
t_rt135(R) :- catch((rt_str('[a,b|C]. ', S), read_term(S,T,[subterm_positions(P)]), R = T-P), error(SsuE, _), R = raised(SsuE)).
t_rt136(R) :- catch((rt_str('- 1 + {x} - "s" - \'q\'(Z) - [].', S), read_term(S,T,[subterm_positions(P)]), R = T-P), error(SsuE, _), R = raised(SsuE)).
t_rt137(R) :- catch((rt_str('a. b.\nc.', S), read_term(S,_,[term_position(P1)]), read_term(S,_,[term_position(P2)]), read_term(S,_,[term_position(P3)]), R = [P1,P2,P3]), error(SsuE, _), R = raised(SsuE)).
t_rt138(R) :- catch((rt_file('a. b.\nc.', S), read_term(S,_,[term_position(P1)]), read_term(S,_,[term_position(P2)]), read_term(S,_,[term_position(P3)]), R = [P1,P2,P3]), error(SsuE, _), R = raised(SsuE)).
t_rt139(R) :- catch((rt_str('x.', S), read_term(S,_,[]), read_term(S,T,[term_position(P),subterm_positions(Q)]), R = T-P-Q), error(SsuE, _), R = raised(SsuE)).
t_rt140(R) :- catch((rt_str('"s" + \'a b\' + 0\'c + 1.5 + a(B).', S), read_term(S,T,[subterm_positions(P)]), R = T-P), error(SsuE, _), R = raised(SsuE)).
t_rt141(R) :- catch((rt_str('(a , b) :- {c}.', S), read_term(S,T,[subterm_positions(P)]), R = T-P), error(SsuE, _), R = raised(SsuE)).
t_rt142(R) :- catch((rt_str('\\+ a.', S), read_term(S,T,[subterm_positions(P)]), R = T-P), error(SsuE, _), R = raised(SsuE)).
t_rt143(R) :- catch((rt_str('f(- , a).', S), read_term(S,T,[subterm_positions(P)]), R = T-P), error(SsuE, _), R = raised(SsuE)).
t_rt144(R) :- catch((rt_str('[].', S), read_term(S,T,[subterm_positions(P)]), R = T-P), error(SsuE, _), R = raised(SsuE)).
t_rt150(R) :- catch((rt_str('f("ab", `cd`).', S), read_term(S,T,[double_quotes(codes)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt151(R) :- catch((rt_str('f("ab", `cd`).', S), read_term(S,T,[double_quotes(atom)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt152(R) :- catch((rt_str('f("ab", `cd`).', S), read_term(S,T,[double_quotes(string), back_quotes(string)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt153(R) :- catch((rt_str('f("ab", `cd`).', S), read_term(S,T,[double_quotes(chars)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt154(R) :- catch((rt_str('f("ab", `cd`).', S), read_term(S,T,[back_quotes(symbol_char)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt155(R) :- catch((rt_str('f("ab", `cd`).', S), read_term(S,T,[back_quotes(codes)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt156(R) :- catch((rt_str('f(\'a\\nb\').', S), read_term(S,T,[character_escapes(false)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt157(R) :- catch((rt_str('f(\'a\\nb\').', S), read_term(S,T,[character_escapes(true)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt158(R) :- catch((rt_str('f(X) :- X = @(Y, [Y=f(Y)]).', S), read_term(S,T,[cycles(true)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt159(R) :- catch((rt_str('f(X,X).', S), read_term(S,T,[cycles(true), variable_names(V)]), R = T-V), error(SsuE, _), R = raised(SsuE)).
t_rt160(R) :- catch((rt_str('[a|b].', S), read_term(S,T,[dotlists(true)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt161(R) :- catch((rt_str('\'[|]\'(a,b).', S), read_term(S,T,[dotlists(true)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt162(R) :- catch((rt_str('foo:bar.', S), read_term(S,T,[module(user)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt163(R) :- catch((rt_str('a +++ b.', S), read_term(S,T,[module(nomod)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt164(R) :- catch((rt_serr((rt_file('a +++ b.', S), read_term(S,_,[module(nomod)])), R)), error(SsuE, _), R = raised(SsuE)).
t_rt165(R) :- catch((rt_str('f(X, Y).', S), read_term(S,T,[variable_names(V), module(user), double_quotes(codes), syntax_errors(error)]), R = T-V), error(SsuE, _), R = raised(SsuE)).
t_rt166(R) :- catch((rt_str('f(\'$VAR\'(1), "x").', S), read_term(S,T,[]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt167(R) :- catch((rt_str('x.', S), read_term(S,T,[end_of_file(foo)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt168(R) :- catch((rt_str('x. y.', S), read_term(S,T,[]), read_term(S,U,[]), read_term(S,V,[]), read_term(S,W,[]), R = [T,U,V,W]), error(SsuE, _), R = raised(SsuE)).
t_rt169(R) :- catch((rt_str('x.y', S), read_term(S,T,[]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt170(R) :- catch(('$raw_read'(user_input, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt171(R) :- catch(('$raw_read'(T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt172(R) :- catch((rt_str('foo( X ,b ) . bar', S), '$raw_read'(S, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt173(R) :- catch((rt_str('0\' . foo', S), '$raw_read'(S, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt174(R) :- catch((rt_str('/* c */ a % x\n . ', S), '$raw_read'(S, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt175(R) :- catch((rt_str('', S), '$raw_read'(S, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt177(R) :- catch((rt_str('foo( X ,b ) . bar( Y ) . ', S), '$raw_read'(S, A), '$raw_read'(S, B), '$raw_read'(S, C), R = [A,B,C]), error(SsuE, _), R = raised(SsuE)).
t_rt178(R) :- catch((rt_str('\'a. b\'. "x. y". c.', S), '$raw_read'(S, A), '$raw_read'(S, B), '$raw_read'(S, C), R = [A,B,C]), error(SsuE, _), R = raised(SsuE)).
t_rt179(R) :- catch((rt_str('foo(  X,\n   b)  .', S), '$raw_read'(S, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt180(R) :- catch((rt_str('end_of_file.', S), '$raw_read'(S, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt181(R) :- catch((rt_str('a. b.', S), '$raw_read'(S, _), read(S, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt182(R) :- catch((rt_str('a. b.', S), read(S, _), '$raw_read'(S, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt183(R) :- catch((rt_str('f(X, Y, X) :- g(Y).', S), '$raw_read'(S, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt185(R) :- catch((rt_serr((rt_file('\'abc', S), '$raw_read'(S, _)), R)), error(SsuE, _), R = raised(SsuE)).
t_rt186(R) :- catch((rt_serr((rt_file('a', S), '$raw_read'(S, _)), R)), error(SsuE, _), R = raised(SsuE)).
t_rt187(R) :- catch((rt_serr((rt_file('/* abc', S), '$raw_read'(S, _)), R)), error(SsuE, _), R = raised(SsuE)).
t_rt188(R) :- catch(('$raw_read'(_, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt189(R) :- catch(('$raw_read'(foo, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt190(R) :- catch((rt_out(S), '$raw_read'(S, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt191(R) :- catch((rt_bin('foo. ', S), '$raw_read'(S, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt192(R) :- catch((rt_str('a. b.', S), '$raw_read'(S, f(_)), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt193(R) :- catch((rt_str('a . ', S), '$raw_read'(S, 'a'), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt194(R) :- catch((rt_str('"abc".', S), '$raw_read'(S, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt195(R) :- catch((rt_str('[ a , b | C ] . ', S), '$raw_read'(S, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt196(R) :- catch((rt_str('a.b. c.', S), '$raw_read'(S, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt197(R) :- catch((rt_str('f(0\'a, 0\'\\n, 0\'\'\'). ', S), '$raw_read'(S, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt198(R) :- catch((rt_str('1.5 + 2.0e3 . ', S), '$raw_read'(S, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt199(R) :- catch((rt_str('a %c\n.\n', S), '$raw_read'(S, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt200(R) :- catch(('$is_named_var'('X'), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt201(R) :- catch(('$is_named_var'('_X'), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt202(R) :- catch(('$is_named_var'('_1'), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt203(R) :- catch(('$is_named_var'('__a'), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt204(R) :- catch(('$is_named_var'('_'), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt205(R) :- catch(('$is_named_var'('_a'), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt206(R) :- catch(('$is_named_var'('Foo'), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt207(R) :- catch(('$is_named_var'([]), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt208(R) :- catch(('$is_named_var'(1), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt209(R) :- catch(('$is_named_var'(f(x)), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt210(R) :- catch(('$is_named_var'(_), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt211(R) :- catch(('$is_named_var'("Foo"), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt212(R) :- catch(('$is_named_var'(foo), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt213(R) :- catch(('$is_named_var'('_G123'), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt214(R) :- catch(('$is_named_var'('Xa1'), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt215(R) :- catch(('$is_named_var'(''), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt216(R) :- catch(('$is_named_var'('_Z'), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt217(R) :- catch((char_code(A, 233), '$is_named_var'(A), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt218(R) :- catch((char_code(C, 201), atom_concat(C, a, A), '$is_named_var'(A), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt219(R) :- catch(('$is_named_var'('1X'), R = yes), error(SsuE, _), R = raised(SsuE)).
t_rt303(R) :- catch((rt_str('f(X).', S), read_term(S,T,[blob(error)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt305(R) :- catch((rt_str('f(X).', S), read_term(S,T,[blob(dead)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt306(R) :- catch((rt_str('f(X).', S), read_term(S,T,[blob(resolve)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt307(R) :- catch((rt_str('f.', S), read_term(S,T,[blob(foo)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt308(R) :- catch((rt_str('f.', S), read_term(S,T,[blob(1)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt309(R) :- catch((rt_str('f.', S), read_term(S,T,[blob(_)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt310(R) :- catch((rt_str('<>(1).', S), read_term(S,T,[blob(dead)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt311(R) :- catch((op(200, fy, rtm:(<)), rt_str('<a>(f).', S), read_term(S,T,[blob(dead),module(rtm)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt312(R) :- catch((rt_str('a < b.', S), read_term(S,T,[blob(dead)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt313(R) :- catch((rt_str('<(1).', S), read_term(S,T,[blob(resolve)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt314(R) :- catch((rt_file('<a>(1).', S), rt_serr_formal(read_term(S,T,[blob(error)]), R)), error(SsuE, _), R = raised(SsuE)).
t_rt315(R) :- catch((op(200, xfy, rtm:(>)), rt_str('a <b>(c).', S), read_term(S,T,[blob(dead),module(rtm)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt316(R) :- catch((rt_file('X = <a>.', S), rt_serr_formal(read_term(S,T,[blob(dead)]), R)), error(SsuE, _), R = raised(SsuE)).
t_rt317(R) :- catch((rt_file('<a>(1).', S), rt_serr_formal(read_term(S,T,[]), R)), error(SsuE, _), R = raised(SsuE)).
t_rt318(R) :- catch((rt_str('f.', S), read_clause(S,T,[blob(foo)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt319(R) :- catch((rt_str('f(X).', S), read_clause(S,T,[blob(dead)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt87(R) :- catch((rt_str('a b. c.', S), read_term(S,T,[syntax_errors(fail)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt88(R) :- catch((rt_str('a b. c.', S), read_term(S,T,[syntax_errors(quiet)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt89(R) :- catch((rt_str('a b. c.', S), read_term(S,T,[syntax_errors(dec10)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt120(R) :- catch((rt_serr_formal((rt_str('a b.', S), read(S,_)), R)), error(SsuE, _), R = raised(SsuE)).
t_rt121(R) :- catch((rt_serr_formal((rt_str('foo(.', S), read(S,_)), R)), error(SsuE, _), R = raised(SsuE)).
t_rt122(R) :- catch((rt_serr_formal((rt_str('foo(', S), read(S,_)), R)), error(SsuE, _), R = raised(SsuE)).
t_rt123(R) :- catch((rt_serr_formal((rt_str('\'abc', S), read(S,_)), R)), error(SsuE, _), R = raised(SsuE)).
t_rt124(R) :- catch((rt_serr_formal((rt_str('foo(X,Y)', S), read_term(S,_,[])), R)), error(SsuE, _), R = raised(SsuE)).
t_rt176(R) :- catch((rt_str('a', S), '$raw_read'(S, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt184(R) :- catch((rt_str('\'abc', S), '$raw_read'(S, T), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt300(R) :- catch((rt_str('f(X).', S), read_term(S,T,[comments(C)]), R = T-C), error(SsuE, _), R = raised(SsuE)).
t_rt301(R) :- catch((rt_str('f(X).', S), read_term(S,T,[var_prefix(true)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt302(R) :- catch((rt_str('f(X).', S), read_term(S,T,[quasi_quotations(Q)]), R = T-Q), error(SsuE, _), R = raised(SsuE)).
t_rt304(R) :- catch((rt_str('f(X).', S), read_term(S,T,[unicode_atoms(accept)]), R = T), error(SsuE, _), R = raised(SsuE)).
t_rt320(R) :- catch((rt_str('<a-b>(x, "y").', S), read_term(S,T,[blob(dead)]), blob(T, Ty), R = Ty), error(SsuE, _), R = raised(SsuE)).
t_rt321(R) :- catch((rt_str('<a-b>(x).', S), read_term(S,T,[blob(resolve)]), blob(T, Ty), R = Ty), error(SsuE, _), R = raised(SsuE)).
