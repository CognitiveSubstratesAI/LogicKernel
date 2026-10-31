% split_string/4
st001(R) :- split_string("a.b.c", ".", "", R).
st002(R) :- split_string("/home//jan///nice/path", "/", "", R).
st003(R) :- split_string(" a b ", " ", "", R).
st004(R) :- split_string("  a  ", "", " ", R).
st005(R) :- split_string("//a//b//", "/", "/", R).
st006(R) :- split_string("", "", "", R).
st007(R) :- split_string("", ",", "", R).
st008(R) :- split_string("abc", "", "", R).
st009(R) :- split_string("   ", " ", " ", R).
st010(R) :- split_string("a b  c", " ", " ", R).
st011(R) :- split_string("SWI-Prolog, 7.0", ",", " ", R).
st012(R) :- string_codes(S, [0'a, 0, 0'b]), split_string(S, "", "", R).
st013(R) :- string_codes(S, [0'a, 0, 0'b]), split_string(S, "b", "", R).
st014(R) :- split_string(abc, "b", "", R).
st015(R) :- split_string([0'a, 0',, 0'b], ",", "", R).
st016(R) :- split_string("a,b", [0',], "", R).
st017(R) :- split_string("a.b", ".", "", [A|B]), R = A-B.
st018(R) :- catch(split_string(f(x), ".", "", _), error(E, C), R = E-C).
st019(R) :- catch(split_string(_, ".", "", _), error(E, _), R = E).
st020(R) :- catch(split_string("a", _, "", _), error(E, _), R = E).
st021(R) :- catch(split_string("a", ".", _, _), error(E, _), R = E).
st022(R) :- catch(split_string(123, "2", "", R), error(E, _), R = E).
st023(R) :- split_string("日本語", "本", "", R).
st024(R) :- ( split_string("a.b", ".", "", ["a", "b"]) -> R = yes ; R = no ).
st025(R) :- ( split_string("a.b", ".", "", ["a"]) -> R = yes ; R = no ).
st026(R) :- split_string("  a.b  ", ".", " ", R).
st027(R) :- split_string("abc", "abc", "", R).
st028(R) :- split_string("a  b", " ", "", R).
st029(R) :- split_string(" . ", ".", " ", R).
st030(R) :- split_string("..", ".", "", R).
st031(R) :- split_string("/home//jan///nice/path", "/", "", L), length(L, R).
st032(R) :- split_string("a.b.c", ".", "", [_, M|_]), string(M), R = M.
st033(R) :- catch(split_string("a", "b", [f(x)], _), error(E, _), R = E).
st034(R) :- split_string("abc", "", "abc", R).
st035(R) :- split_string("éaé", "a", "é", R).
% atom_string/2
st036(R) :- atom_string(abc, R).
st037(R) :- atom_string(R, "abc").
st038(R) :- atom_string(123, R).
st039(R) :- atom_string(R, "123"), atom(R).
st040(R) :- atom_string(1.5, R).
st041(R) :- atom_string("str", R).
st042(R) :- catch(atom_string(_, _), error(E, C), R = E-C).
st043(R) :- catch(atom_string(f(x), _), error(E, C), R = E-C).
st044(R) :- catch(atom_string(_, f(x)), error(E, C), R = E-C).
st045(R) :- ( atom_string(abc, "abc") -> R = yes ; R = no ).
st046(R) :- ( atom_string(abc, "abd") -> R = yes ; R = no ).
st047(R) :- ( atom_string(abc, abc) -> R = yes ; R = no ).
st048(R) :- atom_string([], R).
st049(R) :- atom_string(R, []).
st050(R) :- atom_string(R, [0'a, 0'b]).
st051(R) :- atom_string("日本", R).
st052(R) :- atom_string(R, "日本").
st053(R) :- ( atom_string(abc, 12) -> R = yes ; R = no ).
st054(R) :- atom_string(R, 12), atom(R).
st055(R) :- atom_string(A, "x y"), atom_length(A, R).
st056(R) :- atom_string(abc, S), string(S), R = S.
% string_codes/2, string_chars/2, text_to_string/2
st057(R) :- string_codes("abc", R).
st058(R) :- string_codes(R, [0'a, 0'b]), string(R).
st059(R) :- string_codes(abc, R).
st060(R) :- string_codes(12, R).
st061(R) :- catch(string_codes(_, _), error(E, C), R = E-C).
st062(R) :- string_codes(R, "ab").
st063(R) :- catch(string_codes(f(x), _), error(E, C), R = E-C).
st064(R) :- catch(string_codes(_, [a]), error(E, _), R = E).
st065(R) :- catch(string_codes(_, [-1]), error(E, _), R = E).
st066(R) :- catch(string_codes(_, [0'a|_]), error(E, _), R = E).
st067(R) :- string_codes("abc", [0'a|R]).
st068(R) :- ( string_codes("abc", [0'x|_]) -> R = yes ; R = no ).
st069(R) :- string_codes("", R).
st070(R) :- string_codes(R, []), string(R).
st071(R) :- string_codes("日本", R).
st072(R) :- string_codes(R, [26085, 26412]), string_length(R, N).
st073(R) :- string_chars("abc", R).
st074(R) :- string_chars(R, [a, b]), string(R).
st075(R) :- string_chars(abc, R).
st076(R) :- string_chars(12, R).
st077(R) :- catch(string_chars(_, _), error(E, C), R = E-C).
st078(R) :- catch(string_chars(_, [a, bc]), error(E, _), R = E).
st079(R) :- string_chars("日本", R).
st080(R) :- string_chars(R, ['日']), string_length(R, N).
st081(R) :- string_chars("abc", [a|R]).
st082(R) :- text_to_string(abc, R).
st083(R) :- text_to_string("str", R).
st084(R) :- text_to_string([0'a, 0'b], R).
st085(R) :- text_to_string([a, b], R).
st086(R) :- catch(text_to_string(12, _), error(E, C), R = E-C).
st087(R) :- catch(text_to_string(_, _), error(E, C), R = E-C).
st088(R) :- catch(text_to_string(f(x), _), error(E, C), R = E-C).
st089(R) :- text_to_string([], R).
st090(R) :- ( text_to_string(abc, "abc") -> R = yes ; R = no ).
st091(R) :- text_to_string('日本', R).
st092(R) :- text_to_string("s", S), string(S), R = S.
% string_length/2
st093(R) :- string_length("abc", R).
st094(R) :- string_length(abc, R).
st095(R) :- string_length(123, R).
st096(R) :- string_length(1.5, R).
st097(R) :- string_length([a, b, c], R).
st098(R) :- string_length([], R).
st099(R) :- string_length("", R).
st100(R) :- string_length("日本語", R).
st101(R) :- catch(string_length(f(x), _), error(E, C), R = E-C).
st102(R) :- catch(string_length(_, _), error(E, C), R = E-C).
st103(R) :- ( string_length("abc", 3) -> R = yes ; R = no ).
st104(R) :- ( string_length("abc", 4) -> R = yes ; R = no ).
st105(R) :- catch(string_length("abc", foo), error(E, _), R = E).
st106(R) :- ( string_length("abc", -1) -> R = yes ; R = no ).
st107(R) :- catch(string_length("abc", 1.5), error(E, _), R = E).
st108(R) :- string_length([0'a, 0'b], R).
st109(R) :- catch(string_length([a|_], _), error(E, _), R = E).
% string_concat/3
st110(R) :- string_concat(abc, def, R).
st111(R) :- string_concat("a", "b", R), string(R).
st112(R) :- string_concat(1, 2, R), string(R).
st113(R) :- string_concat(a, R, abc).
st114(R) :- string_concat(R, c, abc).
st115(R) :- string_concat(a, R, "abc"), string(R).
st116(R) :- findall(X-Y, string_concat(X, Y, "abc"), R).
st117(R) :- findall(X-Y, string_concat(X, Y, abc), R).
st118(R) :- ( string_concat("ab", "c", "abc") -> R = yes ; R = no ).
st119(R) :- ( string_concat(a, b, ac) -> R = yes ; R = no ).
st120(R) :- catch(string_concat(_, _, _), error(E, C), R = E-C).
st121(R) :- catch(string_concat(f(x), b, _), error(E, C), R = E-C).
st122(R) :- catch(string_concat(a, _, _), error(E, _), R = E).
st123(R) :- findall(X, string_concat(X, X, "abab"), R).
st124(R) :- findall(X, string_concat(X, X, "abc"), R).
st125(R) :- string_concat("", "", R), string_length(R, 0).
st126(R) :- catch(string_concat([0'a], [0'b], R), error(E, _), R = E).
st127(R) :- string_concat("日", "本", R), string_length(R, N).
st128(R) :- findall(X-Y, string_concat(X, Y, "日本"), L), length(L, R).
st129(R) :- string_concat(abc, R, "abcdef").
st130(R) :- ( string_concat(abc, R, "xbcdef") -> true ; R = no ).
st131(R) :- string_concat(R, "", "abc").
% sub_string/5
st132(R) :- sub_string("hello", 1, 3, A, R).
st133(R) :- sub_string("hello", B, 2, 0, R).
st134(R) :- sub_string("hello", B, L, 0, "llo"), R = B-L.
st135(R) :- findall(B-A, sub_string("hello", B, _, A, "l"), R).
st136(R) :- sub_string("hello", 0, L, 0, R).
st137(R) :- findall(B-L-A-S, sub_string("abc", B, L, A, S), R).
st138(R) :- sub_string(abc, 1, 1, 1, R).
st139(R) :- findall(B-L-A, sub_string("abc", B, L, A, ""), R).
st140(R) :- ( sub_string("abc", 4, _, _, _) -> R = yes ; R = no ).
st141(R) :- catch(( sub_string("abc", -1, _, _, _) -> R = yes ; R = no ), error(E, _), R = E).
st142(R) :- catch(sub_string("abc", foo, _, _, _), error(E, _), R = E).
st143(R) :- catch(sub_string(_, _, _, _, _), error(E, C), R = E-C).
st144(R) :- catch(sub_string(f(x), _, _, _, _), error(E, C), R = E-C).
st145(R) :- sub_string("abc", B, 1, 0, R).
st146(R) :- findall(L-A-S, sub_string("abc", 1, L, A, S), R).
st147(R) :- findall(B-A, sub_string("abab", B, 2, A, "ab"), R).
st148(R) :- findall(B-A, sub_string("aaaa", B, 2, A, "aa"), R).
st149(R) :- sub_string("abc", 0, _, 0, R).
st150(R) :- ( sub_string("abc", _, _, _, "abcd") -> R = yes ; R = no ).
st151(R) :- sub_string("abc", 3, 0, A, R), A = 0.
st152(R) :- ( sub_string("abc", 1, 5, _, _) -> R = yes ; R = no ).
st153(R) :- sub_string("日本語", 1, 1, A, S), string_length(S, N), R = A-N.
st154(R) :- findall(B, sub_string("abab", B, _, _, abab), R).
st155(R) :- findall(X, sub_string("abab", X, 2, X, "ab"), R).
st156(R) :- findall(X-S, sub_string("abab", X, 2, X, S), R).
st157(R) :- findall(X, sub_string("abcba", X, _, X, "b"), R).
st158(R) :- findall(X-L-S, sub_string("abcba", X, L, X, S), R).
st159(R) :- findall(X-S, sub_string("abc", X, 1, X, S), R).
st160(R) :- findall(X-S, sub_string("abcd", X, 1, X, S), R).
st161(R) :- findall(X, sub_string("abab", X, 2, X, "ba"), R).
st162(R) :- findall(X-Y, sub_string("abab", X, Y, X, "ab"), R).
st163(R) :- findall(X-A, sub_string("aaa", X, 1, A, "a"), R).
st164(R) :- findall(X, sub_string("abab", X, 2, X, abab), R).
st165(R) :- catch(sub_string("abc", 1, -1, _, _), error(E, _), R = E).
st166(R) :- findall(S, sub_string("ab", _, _, _, S), L), msort(L, R).
st167(R) :- sub_string(abc, B, _, 0, "c"), R = B.
st168(R) :- catch(sub_string("abc", _, _, _, f(x)), error(E, _), R = E).
st169(R) :- sub_string("abc", 1, 1, _, b), R = ok.
st170(R) :- ( sub_string("abc", _, _, _, 1) -> R = yes ; R = no ).
% string_code/3
st171(R) :- string_code(1, "abc", R).
st172(R) :- string_code(3, "abc", R).
st173(R) :- ( string_code(0, "abc", _) -> R = yes ; R = no ).
st174(R) :- ( string_code(4, "abc", _) -> R = yes ; R = no ).
st175(R) :- catch(( string_code(-1, "abc", _) -> R = yes ; R = no ), error(E, _), R = E).
st176(R) :- findall(I-C, string_code(I, "abc", C), R).
st177(R) :- string_code(I, "abc", 0'b), R = I.
st178(R) :- findall(I, string_code(I, "abca", 0'a), R).
st179(R) :- string_code(1, abc, R).
st180(R) :- string_code(2, "abc", b), R = ok.
st181(R) :- catch(string_code(_, "abc", foo), error(E, _), R = E).
st182(R) :- catch(string_code(a, "abc", _), error(E, _), R = E).
st183(R) :- catch(string_code(1, f(x), _), error(E, _), R = E).
st184(R) :- catch(string_code(_, _, _), error(E, C), R = E-C).
st185(R) :- ( string_code(1, "abc", 0'a) -> R = yes ; R = no ).
st186(R) :- ( string_code(1, "abc", 0'b) -> R = yes ; R = no ).
st187(R) :- catch(string_code(1.5, "abc", _), error(E, _), R = E).
st188(R) :- X is 1 << 70, catch(string_code(X, "abc", _), error(E, _), R = E).
st189(R) :- ( string_code(1, "abc", -1) -> R = yes ; R = no ).
st190(R) :- findall(I, string_code(I, "", _), R).
st191(R) :- findall(I-C, string_code(I, "日本", C), R).
st192(R) :- string_code(I, "abc", 0'c), R = I.
st193(R) :- ( string_code(I, "abc", 0'z) -> R = I ; R = no ).
st194(R) :- catch(string_code(0'a, "abc", _), error(E, _), R = E).
st195(R) :- string_code(1, [0'a, 0'b], R).
% get_string_code/3
st196(R) :- get_string_code(1, "abc", R).
st197(R) :- get_string_code(3, "abc", R).
st198(R) :- catch(get_string_code(5, "abc", _), error(E, C), R = E-C).
st199(R) :- catch(get_string_code(0, "abc", _), error(E, _), R = E).
st200(R) :- catch(get_string_code(-1, "abc", _), error(E, _), R = E).
st201(R) :- catch(get_string_code(a, "abc", _), error(E, _), R = E).
st202(R) :- X is 1 << 70, catch(get_string_code(X, "abc", _), error(E, _), R = E).
st203(R) :- catch(get_string_code(_, "abc", _), error(E, _), R = E).
st204(R) :- catch(get_string_code(1, f(x), _), error(E, _), R = E).
st205(R) :- get_string_code(2, abc, R).
st206(R) :- ( get_string_code(1, "abc", 0'b) -> R = yes ; R = no ).
st207(R) :- get_string_code(1, "日本", R).
st208(R) :- catch(get_string_code(1, "", _), error(E, _), R = E).
% appended after the first battery: the rows its mutants (tools/mutants/T2.py) need
st209(R) :- ( atom_string(12, "12") -> R = yes ; R = no ).
st210(R) :- ( atom_string("abc", abc) -> R = yes ; R = no ).
st211(R) :- findall(B-A-S, sub_string("abc", B, 3, A, S), R).
st212(R) :- findall(B-L-S, sub_string("abc", B, L, 1, S), R).
st213(R) :- split_string("a.,b", ".,", ",", R).
st214(R) :- split_string("a  ,b", ",", " ", R).
