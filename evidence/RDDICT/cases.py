# RDDICT oracle rows: (group, goal) in order; mk_rows.py numbers them rd01.. and writes the test file's _RDD_CASES.
# A row READS dict syntax through term_to_atom/2 (swipl 10.1.19: pl-read.c's dict branch) and observes the result through helpers that
# hold no dict syntax (the PROGRAM below): a dict is observed through dict_pairs/3 (the standard order of the keys), never printed.
# Text helpers: T(text) quotes a text as a Prolog atom (a single quote becomes \', a backslash stays as written).
GROUPS = []


def T(text):
    return "'" + text.replace("'", "\\'") + "'"


def g(name, goals):
    GROUPS.append((name, goals))


def rdd(*texts):
    return ["rdd(%s, R)" % T(t) for t in texts]


def rds(*texts):
    return ["rds(%s, R)" % T(t) for t in texts]


def rdx(*texts):
    return ["rdx(%s, R)" % T(t) for t in texts]


g("dicts: reads, tags, keys, values", rdd(
    "_{}", "_{ }", "_{a:1}", "t{b:1,a:2}", "Tag{k:v,k2:v2}", "t{}", "X{a:1}", "'x y'{a:2}",
    "_{1:a,2:b}", "_{[]:x}", "_{'':1}", "_{-1:a}", "_{a:1,1:b,[]:c,z:d}", "_{0'a:1}",
    "_{a:1,b:2,c:3,d:4,e:5,f:6,g:7,h:8}", "_{h:8,g:7,f:6,e:5,d:4,c:3,b:2,a:1}",
    "_{a:X,b:X}", "_{a:f(X,Y),b:\"str\",c:1.5,d:[1,2],e:'q q',f:Y}",
    "_{a: -1}", "_{a:(b,c)}", "_{a:b:c}", "_{a:(x:-y)}", "_{a:- 1}", "_{a:{x}}", "_{a:1+2*3}", "_{ a : 1 , b : 2 }",
    "_{a:1,\\nb:2}", "_{a:1, /* c */ b:2}", "_{'a b':1}", "_{{}:1}", "_{+ :1}", "_{1:a,a:1,[]:b,'':c}",
    "{a}", "f(x)", "f{}", "_{a:1} ", "_{a:'_{b:1}'}",
))
g("dicts: nested, in arguments, with operators", [
    "rdv(%s, a, R)" % T("_{a:_{b:1}}"),
    "rdv(%s, a, R)" % T("_{a:t{b:1,c:x}}"),
    "rdw(%s, a, c, R)" % T("_{a:t{b:1,c:_{}}}"),
    "rdw(%s, a, b, R)" % T("t{a:u{b:v{c:1}}}"),
    "rdw(%s, a, c, R)" % T("_{a:t{c:_{x:1,y:2}}}"),
    "rdv(%s, b, R)" % T("_{a:1,b:X{c:2}}"),
    "rda(%s, 1, R)" % T("f(_{a:1},_{b:2})"),
    "rda(%s, 2, R)" % T("f(_{a:1},_{b:2})"),
    "rda(%s, 2, R)" % T("g(x,t{a:1,b:2},y)"),
    "rda(%s, 1, R)" % T("[_{a:1}]"),
    "rda(%s, 2, R)" % T("a- _{x:1}"),
    "rda(%s, 1, R)" % T("f(t{a:1}, t{a:1})"),
    "rda(%s, 1, R)" % T("f(_{a:1,b:2,c:3},x)"),
] + rdx("_{a:1}:b", "t{a:1}=X", "p:-_{a:1}", "f(x):_{a:1}"))
g("syntax errors (syn(Id, CharNo))", rds(
    "_{a}", "_{a:1", "_{a:1,a:2}", "_{1.5:a}", "_{99999999999999999999:1}", "_{f(x):1}", "_{a:1,}", "t{a:1,,b:2}",
    "_{\"s\":1}", "_{a:-}", "_{a:1}{b:2}", "1{a:2}", "\"s\"{a:2}", "_{a:1 b:2}", "_{:1}", "_{a:}", "_{a:1,b}", "_{,}",
    "_{a:1)", "_{a:1]", "_{a:x:-y}", "_ {a:1}", "foo {a:1}", "_{1:a,1:b}", "_{a:1,b:2,a:3}", "_{(a):1}", "_{a;1}",
    "_{a=1}", "_{'a':1,a:2}", "_{0'a:1,97:2}", "_{-1:a,-1:b}", "_{a:1,b:2", "_{", "t{", "a{b}", "_{a:1,[a]:2}",
    "X{a:1}.", "_{[]:1,[]:2}",
))
g("dict-dot reads: the generic '.'/2 term (no dict-specific reader code)", rdx(
    "Ctx.get(stack)", "_{a:1}.put(b,2)", "X.y.z", "X.put(a,1).get(a)", "_{a:1}.a", "t{a:1}.get(a)", "a.b", "X.Y",
    "1.5", "f(a).g", "X.put(k,v)", "X.put(f(Y),Y)", "X.put(a,Y).get(a)",
))
g("clause bodies and heads read by the loader (the program's own dict syntax)", [
    "rdb1(R)", "rdb2(R)", "rdb3(R)", "rdb4(R)", "rdb5(R)",
    "rdh(_{a:1}, R)", "rdh(_{a:2}, R)", "rdh(t{a:1}, R)", "rdh(X, R), X = _{a:1}",
])

def rdp(*texts):
    return ["rdp(%s, R)" % T(t) for t in texts]


g("subterm_positions of dicts (dict_position/5, key_value_position/7), read_term_from_atom/3", rdp(
    "_{a:1}", "t{a:1,b:f(x)}", "_{}", "X{k:v}", "f(_{a:1})", "_{1:a}", "_{a:_{b:1}}", " _{ a : 1 , b : 2 } ", "t{a:1,b:2,c:3}",
    "[_{a:1},t{}]", "_{'x y':\"s\"}", "a- _{}",
))

g("key and tag edge cases (the mutants' anchors: key tokens, small-int keys, duplicate positions, a tag shared with a value)", rds(
    "_{a{}:1}", "_{a{b:1}:2}", "_{|:1}", "_{]:1}", "_{):1}", "_{{a}:1}", "_{a:1,b:2,b:3}", "_{z:1,y:2,z:3,x:4}",
    "_{72057594037927936:1}", "_{72057594037927935:1}", "_{-72057594037927936:1}", "_{-72057594037927937:1}", "_{1152921504606846975:1}",
) + rdd(
    "_{72057594037927935:1}", "_{-72057594037927936:1}", "_{a{}:1}", "_{a{b:1}:2}",
) + rdd("_{a:x:-y}", "_{a:b;c}", "_{a:b->c}", "_{a:x:-y,b:2}", "_{a:b;c,d:e}", "_{a:p:-q:-r}") + ["rdsame(%s, R)" % T("X{a:X}"), "rdsame(%s, R)" % T("X{a:Y}"), "rdsame(%s, R)" % T("t{a:X}")])

# per var_tag mode: the cases run once per mode (module flags set from Julia in the kernel, `:- set_prolog_flag(var_tag, Mode).` for swipl)
MODES = ["dict", "error", "warning", "attvar", "#"]
MODE_CASES = [
    "rdd(%s, R)" % T("_{a:1}"), "rdd(%s, R)" % T("Tag{a:1,b:2}"), "rdd(%s, R)" % T("t{a:1}"), "rdd(%s, R)" % T("_{}"),
    "rda(%s, 1, R)" % T("f(_{a:1},_)"), "rda(%s, 2, R)" % T("f(t{a:1},_{b:2})"),
    "rds(%s, R)" % T("_{a:1,a:2}"), "rds(%s, R)" % T("_{a}"), "rds(%s, R)" % T("t{a:1,a:2}"),
    # build_attvar / build_labeled_subterm (var_tag attvar): attributes, labels (`X{= : Value}`) and their errors
    "rdav(%s, R)" % T("X{a:1,b:2}"), "rdav(%s, R)" % T("X{a:1,a:1}"), "rdav(%s, R)" % T("_{a:g(1)}"), "rdd(%s, R)" % T("X{}"),
    "rda(%s, 1, R)" % T("f(X{= : g(1)}, X)"), "rda(%s, 2, R)" % T("f(X{= : g(1)}, X)"), "rda(%s, 1, R)" % T("f(_{= : g(1)}, X)"),
    "rds(%s, R)" % T("X{a:1,a:2}"), "rds(%s, R)" % T("X{= : 1, a:2}"), "rds(%s, R)" % T("f(X{= : 1}, X{= : 2})"),
    "rds(%s, R)" % T("f(X{a:1}, X{= : 2})"), "rds(%s, R)" % T("f(X{= : 1}, X{a:2})"), "rds(%s, R)" % T("f(X{a:1}, X{b:2})"),
    "rdav(%s, R)" % T("f(X{a:1}, X{b:2})"),
    "current_prolog_flag(var_tag, R)",
]

PROGRAM = """rdt(G, G1) :- ( var(G) -> G1 = var ; G1 = G ).
rdo(A, R) :- ( attvar(A) -> R = attvar ; is_dict(A) -> dict_pairs(A, G, Ps), rdt(G, G1), R = d(G1, Ps) ; var(A) -> R = var ; R = A ).
rdd(Txt, R) :- term_to_atom(T, Txt), ( attvar(T) -> R = attvar ; is_dict(T) -> dict_pairs(T, G, Ps), rdt(G, G1), R = d(G1, Ps) ; R = nodict(T) ).
rdv(Txt, K, R) :- term_to_atom(T, Txt), get_dict(K, T, V), rdo(V, R).
rdw(Txt, K1, K2, R) :- term_to_atom(T, Txt), get_dict(K1, T, V1), get_dict(K2, V1, V2), rdo(V2, R).
rda(Txt, N, R) :- term_to_atom(T, Txt), arg(N, T, A), rdo(A, R).
rdx(Txt, R) :- term_to_atom(T, Txt), ( compound(T), T =.. [F, A, B] -> rdo(A, A1), rdo(B, B1), R = F-A1-B1 ; R = other(T) ).
rdp(Txt, R) :- read_term_from_atom(Txt, _, [subterm_positions(R)]).
rdav(Txt, R) :- term_to_atom(T, Txt), ( attvar(T) -> get_attrs(T, A), R = attrs(A) ; arg(1, T, X), attvar(X) -> get_attrs(X, A), R = attrs(A) ; R = nodict ).
rdsame(Txt, R) :- term_to_atom(T, Txt), dict_pairs(T, G, [_-V]), ( G == V -> R = same ; R = differ ).
rds(Txt, R) :- catch(( term_to_atom(_, Txt), R = read ), error(syntax_error(I), string(_, P)), R = syn(I, P)).
"""
# clauses whose own text holds dict syntax (the loader reads them); the pl-boot lines: init.pl:1297 `_{file_type:regular}`, autoload.pl:889 `:<`
BODIES = """rdb1(R) :- D = _{a:1,b:2}, dict_pairs(D, _, R).
rdb2(R) :- X = _{file_type:regular}, dict_pairs(X, _, R).
rdb3(R) :- _{module:M, exports:E, file:F} :< _{module:m1, exports:[a/1], file:'x.pl', extra:1}, R = M-E-F.
rdb4(R) :- T = point{x:1, y:2}, dict_pairs(T, Tag, Ps), R = Tag-Ps.
rdb5(R) :- T = Tag{k:v}, dict_pairs(T, G, Ps), ( G == Tag -> R = same(Ps) ; R = other ).
rdh(_{a:1}, yes).
rdh(t{a:1}, tagged).
"""
