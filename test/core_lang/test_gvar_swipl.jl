# ORIGINAL: G1's gate (lk-channel evidence/r2/design/flags_rest.md §4 D7/D8, §5 H6-H9, §6 G1 row) — the global variables of pl-gvar.c
# (b_setval/2, b_getval/2, nb_setval/2, nb_linkval/2, nb_getval/2, nb_delete/1, nb_current/2) against swipl 10.1.19, as clauses of a consulted program.
# test/core_lang/test_gvar_swipl.jl — cases `t_<id>(R)` run IN ORDER in one database (the global variables persist between them, as in swipl's
# driver), each wrapped in `catch(Goal, error(SsuE, _), R = raised(SsuE))`:
#   * Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, evidence/G1/gen_rows.py + gvar_driver.pl, 2026-10-31);
#     with `swipl` on PATH the live answers are compared with the pins too.
#   * nb_current enumerations are compared SORTED (flag c: the kernel enumerates in insertion order, swipl in hash order).
#   * Rows marked `UNVERIFIED on the kernel: gate decides` are judged by the first gate run (a mismatch is traced, not re-pinned).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the global variables (src/pl-gvar.jl), built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _GV = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_gvs(x) = lk_sym(_GV, Symbol(x))

_gv_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _gv_enc(t::_GV, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _gv_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _gv_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _gv_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_gv_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test/core_lang/test_at_body_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _GV_DRIVER = raw"""
enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- T == [], !, write(nil).
enc(T, S, S) :- atom(T), !, atom_codes(T, Cs), format("a~w", [Cs]).
enc(T, S, S) :- string(T), !, string_codes(T, Cs), format("s~w", [Cs]).
enc(T, S, S) :- integer(T), !, format("i~w", [T]).
enc(T, S, S) :- rational(T, N, D), !, format("q~wr~w", [N, D]).
enc(T, S, S) :- float(T), !, format("f~w", [T]).
enc(T, S0, S) :- compound_name_arity(T, N, A),
    ( N == [] -> write('c[]') ; atom_codes(N, Cs), format("c~w", [Cs]) ),
    format("/~w(", [A]), encargs(1, A, T, S0, S), write(')').
encargs(I, A, _, S, S) :- I > A, !.
encargs(I, A, T, S0, S) :- arg(I, T, X), enc(X, S0, S1), ( I < A -> write(',') ; true ),
    I1 is I+1, encargs(I1, A, T, S1, S).
vidx([X|_], V, I, I) :- X == V, !.
vidx([_|Xs], V, I0, I) :- I1 is I0+1, vidx(Xs, V, I1, I).
fz_pred(N) :-
    format("~w", [N]), functor(G, N, 1),
    catch(findnsols(50, G, G, Gs), _, Gs = [exception]),
    forall(member(S, Gs), ( S == exception -> write(' exception') ; write(' '), enc(S) )), nl.
fz_run(File, Ns) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(member(N, Ns), fz_pred(N)).
"""
function _gv_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _GV_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: helpers (the library predicates are not loaded in the kernel) and the user:exception/3 hook clauses (D8)
const _GV_PROGRAM = raw"""
gv_member(X, [X|_]).
gv_member(X, [_|T]) :- gv_member(X, T).
gv_forall(C, A) :- \+ ( C, \+ A ).
gv_len(L, N) :- gv_len(L, 0, N).
gv_len([], N, N).
gv_len([_|T], N0, N) :- N1 is N0+1, gv_len(T, N1, N).
gv_dom:attr_unify_hook(_, _).
user:exception(undefined_global_variable, gv_auto, retry) :- nb_setval(gv_auto, 42).
user:exception(undefined_global_variable, gv_fl, fail).
user:exception(undefined_global_variable, gv_er, error).
user:exception(undefined_global_variable, gv_bad, foo).
user:exception(undefined_global_variable, gv_cnt, retry) :- nb_getval(gv_cnt_calls, N), N1 is N+1, nb_setval(gv_cnt_calls, N1).
"""

# (id, goal), run IN ORDER
const _GV_CASES = [
    # nb_setval/nb_getval round trip
    ("g01", raw"nb_setval(gv_a, 1), nb_getval(gv_a, R)"),
    # a compound with a shared variable
    ("g02", raw"nb_setval(gv_b, f(X, _, X)), nb_getval(gv_b, R)"),
    # H6, query 1: the value is stored by this query
    ("g03", raw"nb_setval(gv_h6, f(_, _)), R = stored"),
    # H6, query 2: the value outlives query 1 (D7: _release_frozen! keeps the region while gvar_grefs > 0)
    ("g04", raw"nb_getval(gv_h6, R)"),
    # H6: a compound held by nb_setval across 10^4 throw/catch
    ("g05", raw"nb_setval(gv_h6b, g(_, _)), gv_forall(between(1, 10000, _), catch(throw(ball(_, _)), _, true)), nb_getval(gv_h6b, R)"),
    # H6: the same value read by a later query
    ("g06", raw"nb_getval(gv_h6b, R)"),
    # an unbound variable is SHARED by nb_setval: binding X binds the stored value
    ("g07", raw"nb_setval(gv_c, X), X = 1, nb_getval(gv_c, R)"),
    # the binding is undone on backtracking: the stored value is unbound again
    ("g08", raw"( nb_setval(gv_d, X), X = 1, fail ; nb_getval(gv_d, R) )"),
    # flag f: b_setval over an nb_setval'ed unbound variable binds that variable (upstream quirk)
    ("g09", raw"nb_setval(gv_e, X), b_setval(gv_e, 1), R = X"),
    # b_setval replaces a value
    ("g10", raw"b_setval(gv_f, 1), b_setval(gv_f, f(_)), b_getval(gv_f, R)"),
    # H7: b_setval of a new key undone on backtracking (the key stays, its value back to []) - swipl decides
    ("g11", raw"( b_setval(gv_v, 1), fail ; true ), b_getval(gv_v, R)"),
    # H7: two b_setval, the last wins
    ("g12", raw"b_setval(gv_w, 1), b_setval(gv_w, 2), b_getval(gv_w, R)"),
    # H7: b_setval under backtracking, each answer its own value
    ("g13", raw"findall(V, ( gv_member(X, [1, 2, 3]), b_setval(gv_x, X), b_getval(gv_x, V) ), R)"),
    # H7: the trailed assignment is undone
    ("g14", raw"b_setval(gv_y, 1), ( b_setval(gv_y, 2), fail ; b_getval(gv_y, R) )"),
    # H8: a cyclic value; UNVERIFIED on the kernel: gate decides (nshare/share are not ported, flag a)
    ("g15", raw"X = f(X), nb_setval(gv_cy, X), nb_getval(gv_cy, Y), Y = f(Y), R = yes"),
    # nb_linkval stores the term itself
    ("g16", raw"nb_linkval(gv_l, f(X)), nb_getval(gv_l, f(Y)), ( Y == X -> R = same ; R = diff )"),
    # nb_setval stores a copy
    ("g17", raw"nb_setval(gv_l2, f(X)), nb_getval(gv_l2, f(Y)), ( Y == X -> R = same ; R = diff )"),
    # nb_linkval aliasing: a later binding shows in the stored term
    ("g18", raw"nb_linkval(gv_l3, f(X)), X = 1, nb_getval(gv_l3, R)"),
    # nb_current enumeration, SORTED (flag c: the table order differs)
    ("g19", raw"nb_setval(gv_n1, a), nb_setval(gv_n2, b), nb_setval(gv_n3, c), findall(K, ( nb_current(K, _), gv_member(K, [gv_n1, gv_n2, gv_n3]) ), L), msort(L, R)"),
    # nb_current with a bound key
    ("g20", raw"nb_current(gv_n2, R)"),
    # nb_current with a bound value
    ("g21", raw"findall(K, ( nb_current(K, b), gv_member(K, [gv_n1, gv_n2, gv_n3]) ), R)"),
    # nb_delete then nb_current fails
    ("g22", raw"nb_setval(gv_dd, 1), nb_delete(gv_dd), ( nb_current(gv_dd, _) -> R = still ; R = gone )"),
    # nb_delete of an unknown key
    ("g23", raw"( nb_delete(gv_never) -> R = yes ; R = no )"),
    # H9: no hook answer: existence_error(variable, gv_nokey)
    ("g24", raw"nb_getval(gv_nokey, _)"),
    # H9: swipl's exact ball; UNVERIFIED on the kernel: gate decides (the context term)
    ("g25", raw"catch(nb_getval(gv_nokey2, _), E, true), R = E"),
    # a number as key
    ("g26", raw"nb_setval(1, a)"),
    # a compound as key
    ("g27", raw"nb_setval(f(x), a)"),
    # an unbound key
    ("g28", raw"nb_setval(_, a)"),
    # nb_getval, a compound key
    ("g29", raw"nb_getval(f(x), _)"),
    # b_setval, a compound key
    ("g30", raw"b_setval(f(x), a)"),
    # b_getval, an unbound key
    ("g31", raw"b_getval(_, _)"),
    # nb_delete, a compound key
    ("g32", raw"nb_delete(f(x))"),
    # nb_delete, an unbound key
    ("g33", raw"nb_delete(_)"),
    # nb_current, a compound key
    ("g34", raw"( nb_current(f(x), _) -> R = yes ; R = no )"),
    # a string value (UNVERIFIED on the kernel: gate decides, string_codes/2 is T1's)
    ("g35", raw"string_codes(S, [115, 116, 114]), nb_setval(gv_s, S), nb_getval(gv_s, R)"),
    # a float value (flag b: counts as on the global stack)
    ("g36", raw"nb_setval(gv_fl2, 1.5), nb_getval(gv_fl2, R)"),
    # a big integer value
    ("g37", raw"nb_setval(gv_bi, 100000000000000000000), nb_getval(gv_bi, R)"),
    # nb_setval overwrites
    ("g38", raw"nb_setval(gv_ow, a), nb_setval(gv_ow, b), nb_getval(gv_ow, R)"),
    # nb_current of an unknown key fails
    ("g39", raw"( nb_current(gv_nope, _) -> R = yes ; R = no )"),
    # nb_getval reads a b_setval value
    ("g40", raw"b_setval(gv_bg, f(_)), nb_getval(gv_bg, R)"),
    # nb_setval survives backtracking
    ("g41", raw"( gv_member(X, [1, 2]), nb_setval(gv_t, X), fail ; nb_getval(gv_t, R) )"),
    # an attributed variable value; UNVERIFIED on the kernel: gate decides
    ("g42", raw"put_attr(X, gv_dom, 1), nb_setval(gv_av, X), nb_getval(gv_av, Y), get_attr(Y, gv_dom, R)"),
    # b_setval inside \+ \+ is undone
    ("g43", raw"b_setval(gv_nest, a), ( \+ \+ ( b_setval(gv_nest, b), b_getval(gv_nest, I), I == b ) -> b_getval(gv_nest, R) ; R = bad )"),
    # the hook user:exception/3 answers retry after defining the variable (D8)
    ("g44", raw"nb_getval(gv_auto, R)"),
    # the hook answers fail
    ("g45", raw"( nb_getval(gv_fl, _) -> R = yes ; R = no )"),
    # the hook answers error
    ("g46", raw"nb_getval(gv_er, _)"),
    # the hook answers an unknown action
    ("g47", raw"nb_getval(gv_bad, _)"),
    # flag d: a hook answering retry without defining runs twice, then existence_error
    ("g48", raw"nb_setval(gv_cnt_calls, 0), catch(nb_getval(gv_cnt, _), _, true), nb_getval(gv_cnt_calls, R)"),
    # b_setval of an unbound variable: a later binding shows
    ("g49", raw"b_setval(gv_u, X), X = 1, b_getval(gv_u, R)"),
    # an unbound value
    ("g50", raw"nb_setval(gv_u2, _), nb_getval(gv_u2, R)"),
    # [] as key
    ("g51", raw"nb_setval([], 1)"),
    # 300 keys, all enumerated
    ("g52", raw"gv_forall(between(1, 300, I), ( atom_concat(gv_k_, I, K), nb_setval(K, I) )), findall(K-V, nb_current(K, V), All), findall(I, ( between(1, 300, I), atom_concat(gv_k_, I, K), gv_member(K-I, All) ), Is), gv_len(Is, R)"),
    # H2-like: a key created during an enumeration; sorted
    ("g53", raw"nb_setval(gv_m1, x), nb_setval(gv_m2, x), findall(K, ( nb_current(K, x), gv_member(K, [gv_m1, gv_m2]), nb_setval(gv_new_during, 1) ), L), msort(L, S), nb_current(gv_new_during, N), R = S-N"),
    # nb_setval after b_setval
    ("g54", raw"b_setval(gv_mix, 1), nb_setval(gv_mix, 2), nb_getval(gv_mix, R)"),
    # b_setval over an nb_setval value, undone
    ("g55", raw"nb_setval(gv_mix2, a), ( b_setval(gv_mix2, b), fail ; nb_getval(gv_mix2, R) )"),
    # nb_getval returns the stored term itself
    ("g56", raw"nb_setval(gv_k1, f(_)), nb_getval(gv_k1, A), nb_getval(gv_k1, B), ( A == B -> R = same ; R = diff )")
]

# the pins: swipl's output for the driver over `_GV_PROGRAM` and `_GV_CASES` (evidence/G1/gvar_rows.out)
const _GV_PINNED = [
    "ok",
    "t_g01 c[116,95,103,48,49]/1(i1)",
    "t_g02 c[116,95,103,48,50]/1(c[102]/3(V0,V1,V0))",
    "t_g03 c[116,95,103,48,51]/1(a[115,116,111,114,101,100])",
    "t_g04 c[116,95,103,48,52]/1(c[102]/2(V0,V1))",
    "t_g05 c[116,95,103,48,53]/1(c[103]/2(V0,V1))",
    "t_g06 c[116,95,103,48,54]/1(c[103]/2(V0,V1))",
    "t_g07 c[116,95,103,48,55]/1(i1)",
    "t_g08 c[116,95,103,48,56]/1(V0)",
    "t_g09 c[116,95,103,48,57]/1(i1)",
    "t_g10 c[116,95,103,49,48]/1(c[102]/1(V0))",
    "t_g11 c[116,95,103,49,49]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[118,97,114,105,97,98,108,101],a[103,118,95,118])))",
    "t_g12 c[116,95,103,49,50]/1(i2)",
    "t_g13 c[116,95,103,49,51]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))))",
    "t_g14 c[116,95,103,49,52]/1(i1)",
    "t_g15 c[116,95,103,49,53]/1(a[121,101,115])",
    "t_g16 c[116,95,103,49,54]/1(a[115,97,109,101])",
    "t_g17 c[116,95,103,49,55]/1(a[100,105,102,102])",
    "t_g18 c[116,95,103,49,56]/1(c[102]/1(i1))",
    "t_g19 c[116,95,103,49,57]/1(c[91,124,93]/2(a[103,118,95,110,49],c[91,124,93]/2(a[103,118,95,110,50],c[91,124,93]/2(a[103,118,95,110,51],nil))))",
    "t_g20 c[116,95,103,50,48]/1(a[98])",
    "t_g21 c[116,95,103,50,49]/1(c[91,124,93]/2(a[103,118,95,110,50],nil))",
    "t_g22 c[116,95,103,50,50]/1(a[103,111,110,101])",
    "t_g23 c[116,95,103,50,51]/1(a[121,101,115])",
    "t_g24 c[116,95,103,50,52]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[118,97,114,105,97,98,108,101],a[103,118,95,110,111,107,101,121])))",
    "t_g25 c[116,95,103,50,53]/1(c[101,114,114,111,114]/2(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[118,97,114,105,97,98,108,101],a[103,118,95,110,111,107,101,121,50]),c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,121,115,116,101,109],c[47]/2(a[110,98,95,103,101,116,118,97,108],i2)),V0)))",
    "t_g26 c[116,95,103,50,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_g27 c[116,95,103,50,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],c[102]/1(a[120]))))",
    "t_g28 c[116,95,103,50,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_g29 c[116,95,103,50,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],c[102]/1(a[120]))))",
    "t_g30 c[116,95,103,51,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],c[102]/1(a[120]))))",
    "t_g31 c[116,95,103,51,49]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_g32 c[116,95,103,51,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],c[102]/1(a[120]))))",
    "t_g33 c[116,95,103,51,51]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_g34 c[116,95,103,51,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],c[102]/1(a[120]))))",
    "t_g35 c[116,95,103,51,53]/1(s[115,116,114])",
    "t_g36 c[116,95,103,51,54]/1(f1.5)",
    "t_g37 c[116,95,103,51,55]/1(i100000000000000000000)",
    "t_g38 c[116,95,103,51,56]/1(a[98])",
    "t_g39 c[116,95,103,51,57]/1(a[110,111])",
    "t_g40 c[116,95,103,52,48]/1(c[102]/1(V0))",
    "t_g41 c[116,95,103,52,49]/1(i2)",
    "t_g42 c[116,95,103,52,50]/1(i1)",
    "t_g43 c[116,95,103,52,51]/1(a[97])",
    "t_g44 c[116,95,103,52,52]/1(i42)",
    "t_g45 c[116,95,103,52,53]/1(a[110,111])",
    "t_g46 c[116,95,103,52,54]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[118,97,114,105,97,98,108,101],a[103,118,95,101,114])))",
    "t_g47 c[116,95,103,52,55]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[118,97,114,105,97,98,108,101],a[103,118,95,98,97,100])))",
    "t_g48 c[116,95,103,52,56]/1(i2)",
    "t_g49 c[116,95,103,52,57]/1(i1)",
    "t_g50 c[116,95,103,53,48]/1(V0)",
    "t_g51 c[116,95,103,53,49]/1(V0)",
    "t_g52 c[116,95,103,53,50]/1(i300)",
    "t_g53 c[116,95,103,53,51]/1(c[45]/2(c[91,124,93]/2(a[103,118,95,109,49],c[91,124,93]/2(a[103,118,95,109,50],nil)),i1))",
    "t_g54 c[116,95,103,53,52]/1(i2)",
    "t_g55 c[116,95,103,53,53]/1(a[97])",
    "t_g56 c[116,95,103,53,54]/1(a[115,97,109,101])"
]

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _gv_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_GV}()
    ld = LK.PL_local_data{_GV}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _gv_enc(ball::_GV)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_gvs(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_GV, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _gv_enc(mk_expr(_GV, _GV[_gvs(name), lk_answers(ld, (a:a)...)...]))
                )
                rc == LK.PL_S_LAST && break
            elseif rc == LK.PL_S_EXCEPTION
                push!(sols, "exception")
                break
            else
                break
            end
        end
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        push!(out, "$name" * join(" " .* sols))
    end
    return out, gd, ld
end


"The program and cases as one file; the case predicates' names."
function _gv_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _GV_CASES]
    text =
        _GV_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _GV_CASES
        ])
    f = joinpath(mktempdir(), "gvar.pl")
    write(f, text)
    return f, names
end

@testset "global variables as swipl's (g01-g56)" begin
    f, names = _gv_file()
    kl, gd, ld = _gv_kernel(f, names)
    @test length(kl) == length(_GV_PINNED)
    for (k, p) in zip(kl, _GV_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
    # not vacuous: the pins hold stored values, unbound values, raised errors, and the sorted enumerations, so the comparison can
    # pass and can fail (one extractor: `_gv_enc` for both sides)
    @test count(l -> occursin("c[114,97,105,115,101,100]", l), _GV_PINNED) >= 8        # raised(...)
    @test count(l -> occursin("c[102]/", l), _GV_PINNED) >= 5                          # an f(...) value
    @test any(l -> startswith(l, "t_g04 ") && occursin("c[102]/2(V0,V1)", l), _GV_PINNED)     # H6, query 2
    @test any(l -> startswith(l, "t_g05 ") && occursin("c[103]/2(V0,V1)", l), _GV_PINNED)     # H6, 10^4 throws
    @test any(l -> startswith(l, "t_g07 ") && endswith(l, "(i1)"), _GV_PINNED)         # the shared variable
    @test any(l -> startswith(l, "t_g08 ") && endswith(l, "(V0)"), _GV_PINNED)         # undone on backtracking
    @test any(l -> startswith(l, "t_g09 ") && endswith(l, "(i1)"), _GV_PINNED)         # flag f
    @test any(l -> startswith(l, "t_g52 ") && endswith(l, "(i300)"), _GV_PINNED)       # all 300 keys
    # D7: the values are held on the global stack (the counter is positive after the rows), and no enumeration state is left open
    @test ld.gvar_grefs > 0
    @test !isempty(ld.gvar_nb_vars)
    @test LK.live_states(ld) == 0
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    # the pinned table is the driver's whole output (the inert-testset guard: an assertion either way)
    @test length(_GV_PINNED) == length(_GV_CASES) + 1
    if swipl === nothing
        @info "G1 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _gv_file()
        @test _gv_swipl_lines(f, names) == _GV_PINNED
    end
end

# H9 / D8: the hook before any program defines user:exception/3 — a database with ONLY the case predicate. user:exception/3 is
# dynamic from the start (setBuiltinPredicateProperties!), so the call finds no clause and the answer is the existence error;
# the pin is swipl's (evidence/G1/h9_rows.pl, h9_driver.pl, h9_rows.out).
const _GV_H9_PINNED = [
    "ok",
    "t_h9 c[116,95,104,57]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[118,97,114,105,97,98,108,101],a[103,118,95,110,111,107,101,121,51])))"
]

@testset "the hook before a program: a plain existence_error (H9, D8)" begin
    f = joinpath(mktempdir(), "h9.pl")
    write(f, "t_h9(R) :- catch(nb_getval(gv_nokey3, _), error(SsuE, _), R = raised(SsuE)).\n")
    kl, _, _ = _gv_kernel(f, ["t_h9"])
    @test kl == _GV_H9_PINNED
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    swipl === nothing || @test _gv_swipl_lines(f, ["t_h9"]) == _GV_H9_PINNED
    # not vacuous: the pin holds the existence_error with the variable's name
    @test occursin("c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2", _GV_H9_PINNED[2])
end
