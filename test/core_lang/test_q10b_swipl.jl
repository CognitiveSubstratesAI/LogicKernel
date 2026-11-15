# ORIGINAL: a LIVE differential of the three predicates Q10 wrote on top of R2 stack 1 (`$suspend_findall_bag/0` pl-bag.c:332-361, through
# findnsols/4,5; `garbage_collect_atoms/0` pl-atom.c:1419; `prolog_alert_signal/2` pl-setup.c:1274-1310) and of `trie_property/2`
# (boot/syspred.pl:1264-1311, over `current_blob/2`) against swipl 10.1.20 (the pin 18168e62) — no swipl-devel counterpart.
# Q10's second rows file, test/core_lang/test_q10b_swipl.jl, rows fb01-fb15 ga01-ga07 pa01-pa20 tq01-tq10; the first is test_q10_swipl.jl:
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is test_q10_swipl.jl's (`enc`oded answers).
#   * The kernel boots from the vendored boot files (src/pl-qlf.jl `boot_global_data`): findnsols/4,5, setup_call_cleanup/3, nb_setarg/3 and
#     `trie_property/2` are the BOOT's own (boot/bags.pl, boot/syspred.pl), not copies: the rows call them by their system names.
#   * Every answer line is swipl's, PINNED (the pin's swipl, ~/.local/swipl-pin1-18168e62/bin/swipl, two identical runs, 2026-11-14); with
#     `swipl` on PATH the live answers are compared with the pins too. The kernel's line where it DIFFERS is in `_QB_KERNEL_DIFF`, never the pin.
#   * The tabled form of the TB3 rows tbc01/tbc02 (a variant table's node count read through `trie_property/2`) needs `start_tabling`, which is
#     not on this branch (TAB1 TB2+): tq01-tq10 read PLAIN tries (trie_new/1, trie_insert/3, trie_delete/3) the same way; the TB3 owner swaps
#     `'$trie_property'` for `trie_property` in those two rows.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.

using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the built-ins ride the term layer through PL_unify_integer, PL_get_integer and PL_unify_atom only

include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _QB = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_qbs(x) = lk_sym(_QB, Symbol(x))


_qb_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _qb_enc(t::_QB, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _qb_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _qb_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _qb_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_qb_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test/core_lang/test_ssu_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _QB_DRIVER = raw"""
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
function _qb_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _QB_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end




# the program the rows run against
const _QB_PROGRAM = raw"""
q_a(1).
q_a(2).
q_a(3).
q_a(4).
q_a(5).
% a hand-made bag around a findnsols/4: the chunks it delivers are added to the OUTER bag (the suspended inner bag is skipped)
q_nest(R) :-
    '$new_findall_bag',
    (   findnsols(2, X, q_a(X), L),
        '$add_findall_bag'(L)
    ;   true
    ),
    '$collect_findall_bag'(R, []),
    '$destroy_findall_bag'.
"""

const _QB_CASES = [
    ("fb01", raw"findnsols(2, X, q_a(X), L), R = L"),
    ("fb02", raw"findnsols(2, X, between(1, 7, X), L), R = L"),
    ("fb03", raw"findnsols(2, X, q_a(X), L, [end]), R = L"),
    ("fb04", raw"findnsols(0, X, q_a(X), L), R = L"),
    ("fb05", raw"findnsols(5, X, member(X, [1,2,3,4,5,6]), L), R = L"),
    ("fb06", raw"once(findnsols(2, X, q_a(X), L)), findall(Y, q_a(Y), L2), R = L-L2"),
    ("fb07", raw"findnsols(2, X, q_a(X), L), findall(Z, member(Z, [x,y]), L2), R = L-L2"),
    ("fb08", raw"findnsols(2, X-L2, (member(X, [a,b]), findnsols(2, Y, q_a(Y), L2)), R)"),
    (
        "fb09",
        raw"findnsols(2, X-L2, (member(X, [a,b,c]), once(findnsols(1, Y, q_a(Y), L2))), R)"
    ),
    ("fb10", raw"once((findnsols(2, X, q_a(X), L), L = [3|_])), R = L"),
    ("fb11", raw"q_nest(R)"),
    (
        "fb12",
        raw"findnsols(2, X, (q_a(X), ( X =:= 3 -> throw(error(q10b_err, _)) ; true )), R)"
    ),
    ("fb13", raw"findall(X, q_a(X), R)"),
    ("fb14", raw"forall(findnsols(2, X, q_a(X), _), true), findall(Y, q_a(Y), R)"),
    ("fb15", raw"findnsols(count(2), X, q_a(X), L), R = L"),
    ("ga01", raw"garbage_collect_atoms, R = ok"),
    ("ga02", raw"garbage_collect_atoms, garbage_collect_atoms, R = ok"),
    (
        "ga03",
        raw"atom_codes(A, [0'q, 0'1, 0'0, 0'b, 0'g, 0'a]), garbage_collect_atoms, atom_length(A, N), R = N"
    ),
    ("ga04", raw"call_cleanup(garbage_collect_atoms, Det = true), R = Det"),
    ("ga05", raw"findall(x, garbage_collect_atoms, R)"),
    ("ga06", raw"garbage_collect_atoms(x)"),
    (
        "ga07",
        raw"statistics(agc, N0), garbage_collect_atoms, statistics(agc, N1), ( N1 > N0 -> R = counted ; R = not_counted )"
    ),
    ("pa01", raw"prolog_alert_signal(X, X), R = X"),
    (
        "pa02",
        raw"prolog_alert_signal(Old, usr1), prolog_alert_signal(Now, Now), prolog_alert_signal(_, usr2), R = Old-Now"
    ),
    (
        "pa03",
        raw"prolog_alert_signal(Old, 0), prolog_alert_signal(Now, Now), prolog_alert_signal(_, usr2), R = Old-Now"
    ),
    ("pa04", raw"prolog_alert_signal(_, foo)"),
    ("pa05", raw"prolog_alert_signal(_, 1.5)"),
    ("pa06", raw"prolog_alert_signal(_, _)"),
    ("pa07", raw"prolog_alert_signal(_, 12), prolog_alert_signal(X, X), R = X"),
    ("pa08", raw"( prolog_alert_signal(usr1, usr2) -> R = yes ; R = no )"),
    ("pa09", raw"prolog_alert_signal(usr2, usr2), prolog_alert_signal(X, X), R = X"),
    (
        "pa10",
        raw"prolog_alert_signal(_, 'SIGUSR1'), prolog_alert_signal(X, X), prolog_alert_signal(_, usr2), R = X"
    ),
    (
        "pa11",
        raw"prolog_alert_signal(_, usr1), prolog_alert_signal(usr1, 0), prolog_alert_signal(X, X), prolog_alert_signal(_, usr2), R = X"
    ),
    ("pa12", raw"prolog_alert_signal(_, 9999)"),
    ("pa13", raw"prolog_alert_signal(_, -1)"),
    ("pa14", raw"atom_string(usr1, S), prolog_alert_signal(_, S)"),
    ("pa15", raw"prolog_alert_signal(_, f(x))"),
    (
        "pa16",
        raw"prolog_alert_signal(_, hup), prolog_alert_signal(X, X), prolog_alert_signal(_, usr2), R = X"
    ),
    ("pa17", raw"prolog_alert_signal(_, 32)"),
    (
        "pa18",
        raw"prolog_alert_signal(_, int), prolog_alert_signal(Old, hup), prolog_alert_signal(Now, Now), prolog_alert_signal(_, usr2), R = Old-Now"
    ),
    (
        "pa19",
        raw"prolog_alert_signal(_, 2), prolog_alert_signal(_, 0), prolog_alert_signal(X, 0), prolog_alert_signal(_, usr2), R = X"
    ),
    ("pa20", raw"prolog_alert_signal(X, X), prolog_alert_signal(Y, Y), R = X-Y"),
    (
        "tq01",
        raw"trie_new(T), trie_insert(T, f(a), 1), trie_insert(T, f(b), 2), trie_property(T, node_count(N)), '$trie_property'(T, node_count(M)), ( N == M -> R = same(N) ; R = differ(N, M) )"
    ),
    (
        "tq02",
        raw"trie_new(T), trie_insert(T, f(a), 1), trie_insert(T, f(b), 2), trie_property(T, node_count(N0)), trie_delete(T, f(a), _), trie_property(T, node_count(N1)), D is N0 - N1, R = r(N0, N1, D)"
    ),
    (
        "tq03",
        raw"trie_new(T), trie_insert(T, f(a), 1), trie_property(T, value_count(V)), trie_property(T, node_count(N)), R = V-N"
    ),
    ("tq04", raw"trie_new(T), findall(F, ( trie_property(T, P), functor(P, F, _) ), R)"),
    ("tq05", raw"trie_new(T), ( current_trie(T2), T2 == T -> R = yes ; R = no )"),
    (
        "tq06",
        raw"trie_new(T), trie_destroy(T), ( current_trie(T2), T2 == T -> R = yes ; R = no )"
    ),
    ("tq07", raw"trie_new(T), ( current_blob(B, trie), B == T -> R = yes ; R = no )"),
    ("tq08", raw"trie_new(T), ( trie_property(T, node_count(N)) -> R = N ; R = none )"),
    ("tq09", raw"( trie_property(foo, node_count(_)) -> R = yes ; R = no )"),
    (
        "tq10",
        raw"trie_new(T1), trie_new(T2), trie_insert(T2, g(x, y), 1), trie_property(T1, node_count(N1)), trie_property(T2, node_count(N2)), R = N1-N2"
    )
]

# the driver's whole output, one line per case after `ok`, from swipl 10.1.20 at the pin
const _QB_PINNED = [
    "ok",
    "t_fb01 c[116,95,102,98,48,49]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil))) c[116,95,102,98,48,49]/1(c[91,124,93]/2(i3,c[91,124,93]/2(i4,nil))) c[116,95,102,98,48,49]/1(c[91,124,93]/2(i5,nil))",
    "t_fb02 c[116,95,102,98,48,50]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil))) c[116,95,102,98,48,50]/1(c[91,124,93]/2(i3,c[91,124,93]/2(i4,nil))) c[116,95,102,98,48,50]/1(c[91,124,93]/2(i5,c[91,124,93]/2(i6,nil))) c[116,95,102,98,48,50]/1(c[91,124,93]/2(i7,nil))",
    "t_fb03 c[116,95,102,98,48,51]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(a[101,110,100],nil)))) c[116,95,102,98,48,51]/1(c[91,124,93]/2(i3,c[91,124,93]/2(i4,c[91,124,93]/2(a[101,110,100],nil)))) c[116,95,102,98,48,51]/1(c[91,124,93]/2(i5,c[91,124,93]/2(a[101,110,100],nil)))",
    "t_fb04 c[116,95,102,98,48,52]/1(nil)",
    "t_fb05 c[116,95,102,98,48,53]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,c[91,124,93]/2(i4,c[91,124,93]/2(i5,nil)))))) c[116,95,102,98,48,53]/1(c[91,124,93]/2(i6,nil))",
    "t_fb06 c[116,95,102,98,48,54]/1(c[45]/2(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)),c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,c[91,124,93]/2(i4,c[91,124,93]/2(i5,nil)))))))",
    "t_fb07 c[116,95,102,98,48,55]/1(c[45]/2(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)),c[91,124,93]/2(a[120],c[91,124,93]/2(a[121],nil)))) c[116,95,102,98,48,55]/1(c[45]/2(c[91,124,93]/2(i3,c[91,124,93]/2(i4,nil)),c[91,124,93]/2(a[120],c[91,124,93]/2(a[121],nil)))) c[116,95,102,98,48,55]/1(c[45]/2(c[91,124,93]/2(i5,nil),c[91,124,93]/2(a[120],c[91,124,93]/2(a[121],nil))))",
    "t_fb08 c[116,95,102,98,48,56]/1(c[91,124,93]/2(c[45]/2(a[97],c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil))),c[91,124,93]/2(c[45]/2(a[97],c[91,124,93]/2(i3,c[91,124,93]/2(i4,nil))),nil))) c[116,95,102,98,48,56]/1(c[91,124,93]/2(c[45]/2(a[97],c[91,124,93]/2(i5,nil)),c[91,124,93]/2(c[45]/2(a[98],c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil))),nil))) c[116,95,102,98,48,56]/1(c[91,124,93]/2(c[45]/2(a[98],c[91,124,93]/2(i3,c[91,124,93]/2(i4,nil))),c[91,124,93]/2(c[45]/2(a[98],c[91,124,93]/2(i5,nil)),nil)))",
    "t_fb09 c[116,95,102,98,48,57]/1(c[91,124,93]/2(c[45]/2(a[97],c[91,124,93]/2(i1,nil)),c[91,124,93]/2(c[45]/2(a[98],c[91,124,93]/2(i1,nil)),nil))) c[116,95,102,98,48,57]/1(c[91,124,93]/2(c[45]/2(a[99],c[91,124,93]/2(i1,nil)),nil))",
    "t_fb10 c[116,95,102,98,49,48]/1(c[91,124,93]/2(i3,c[91,124,93]/2(i4,nil)))",
    "t_fb11 c[116,95,102,98,49,49]/1(c[91,124,93]/2(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil)),c[91,124,93]/2(c[91,124,93]/2(i3,c[91,124,93]/2(i4,nil)),c[91,124,93]/2(c[91,124,93]/2(i5,nil),nil))))",
    "t_fb12 c[116,95,102,98,49,50]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil))) c[116,95,102,98,49,50]/1(c[114,97,105,115,101,100]/1(a[113,49,48,98,95,101,114,114]))",
    "t_fb13 c[116,95,102,98,49,51]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,c[91,124,93]/2(i4,c[91,124,93]/2(i5,nil))))))",
    "t_fb14 c[116,95,102,98,49,52]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,c[91,124,93]/2(i3,c[91,124,93]/2(i4,c[91,124,93]/2(i5,nil))))))",
    "t_fb15 c[116,95,102,98,49,53]/1(c[91,124,93]/2(i1,c[91,124,93]/2(i2,nil))) c[116,95,102,98,49,53]/1(c[91,124,93]/2(i3,c[91,124,93]/2(i4,nil))) c[116,95,102,98,49,53]/1(c[91,124,93]/2(i5,nil))",
    "t_ga01 c[116,95,103,97,48,49]/1(a[111,107])",
    "t_ga02 c[116,95,103,97,48,50]/1(a[111,107])",
    "t_ga03 c[116,95,103,97,48,51]/1(i6)",
    "t_ga04 c[116,95,103,97,48,52]/1(a[116,114,117,101])",
    "t_ga05 c[116,95,103,97,48,53]/1(c[91,124,93]/2(a[120],nil))",
    "t_ga06 c[116,95,103,97,48,54]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[112,114,111,99,101,100,117,114,101],c[47]/2(a[103,97,114,98,97,103,101,95,99,111,108,108,101,99,116,95,97,116,111,109,115],i1))))",
    "t_ga07 c[116,95,103,97,48,55]/1(a[99,111,117,110,116,101,100])",
    "t_pa01 c[116,95,112,97,48,49]/1(a[117,115,114,50])",
    "t_pa02 c[116,95,112,97,48,50]/1(c[45]/2(a[117,115,114,50],a[117,115,114,49]))",
    "t_pa03 c[116,95,112,97,48,51]/1(c[45]/2(a[117,115,114,50],i0))",
    "t_pa04 c[116,95,112,97,48,52]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,105,103,110,97,108],a[102,111,111])))",
    "t_pa05 c[116,95,112,97,48,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,105,103,110,97,108],f1.5)))",
    "t_pa06 c[116,95,112,97,48,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_pa07 c[116,95,112,97,48,55]/1(a[117,115,114,50])",
    "t_pa08 c[116,95,112,97,48,56]/1(a[110,111])",
    "t_pa09 c[116,95,112,97,48,57]/1(a[117,115,114,50])",
    "t_pa10 c[116,95,112,97,49,48]/1(a[117,115,114,49])",
    "t_pa11 c[116,95,112,97,49,49]/1(i0)",
    "t_pa12 c[116,95,112,97,49,50]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,105,103,110,97,108],i9999)))",
    "t_pa13 c[116,95,112,97,49,51]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,105,103,110,97,108],i-1)))",
    "t_pa14 c[116,95,112,97,49,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,105,103,110,97,108],s[117,115,114,49])))",
    "t_pa15 c[116,95,112,97,49,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,105,103,110,97,108],c[102]/1(a[120]))))",
    "t_pa16 c[116,95,112,97,49,54]/1(a[104,117,112])",
    "t_pa17 c[116,95,112,97,49,55]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[115,105,103,110,97,108],i32)))",
    "t_pa18 c[116,95,112,97,49,56]/1(c[45]/2(a[105,110,116],a[104,117,112]))",
    "t_pa19 c[116,95,112,97,49,57]/1(i0)",
    "t_pa20 c[116,95,112,97,50,48]/1(c[45]/2(a[117,115,114,50],a[117,115,114,50]))",
    "t_tq01 c[116,95,116,113,48,49]/1(c[115,97,109,101]/1(i4))",
    "t_tq02 c[116,95,116,113,48,50]/1(c[114]/3(i4,i3,i1))",
    "t_tq03 c[116,95,116,113,48,51]/1(c[45]/2(i1,i3))",
    "t_tq04 c[116,95,116,113,48,52]/1(c[91,124,93]/2(a[110,111,100,101,95,99,111,117,110,116],c[91,124,93]/2(a[118,97,108,117,101,95,99,111,117,110,116],c[91,124,93]/2(a[115,105,122,101],c[91,124,93]/2(a[104,97,115,104,101,100],c[91,124,93]/2(a[108,111,111,107,117,112,95,99,111,117,110,116],c[91,124,93]/2(a[103,101,110,95,99,97,108,108,95,99,111,117,110,116],c[91,124,93]/2(a[100,101,97,100,108,111,99,107],c[91,124,93]/2(a[119,97,105,116],nil)))))))))",
    "t_tq05 c[116,95,116,113,48,53]/1(a[121,101,115])",
    "t_tq06 c[116,95,116,113,48,54]/1(a[110,111])",
    "t_tq07 c[116,95,116,113,48,55]/1(a[121,101,115])",
    "t_tq08 c[116,95,116,113,48,56]/1(i1)",
    "t_tq09 c[116,95,116,113,48,57]/1(a[110,111])",
    "t_tq10 c[116,95,116,113,49,48]/1(c[45]/2(i1,i4))"
]

# the kernel's lines where they differ from swipl's (see the header)
# DIVERGES (ga07): `statistics(agc, N)` counts the atom GCs swipl ran; the kernel frees no atom (src/pl-atom.jl: atom GC left out), so
# `garbage_collect_atoms/0` succeeds and the count stays 0. swipl's answer (the pin): `counted`; the kernel's: `not_counted`.
const _QB_KERNEL_DIFF = Dict{String, String}(
    "t_ga07" => "t_ga07 c[116,95,103,97,48,55]/1(a[110,111,116,95,99,111,117,110,116,101,100])"
)
_qb_expected(p::String) = get(_QB_KERNEL_DIFF, first(split(p, ' ')), p)

function _qb_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _QB_CASES]
    text =
        _QB_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _QB_CASES
        ])
    f = joinpath(mktempdir(), "q10b.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _qb_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_QB}()
    ld = LK.PL_local_data{_QB}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _qb_enc(ball::_QB)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_qbs(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_QB, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _qb_enc(mk_expr(_QB, _QB[_qbs(name), lk_answers(ld, (a:a)...)...]))
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


@testset "the Q10 second rows as swipl's (fb01-tq10)" begin
    f, names = _qb_file()
    kl, _, _ = _qb_kernel(f, names)
    @test length(kl) == length(_QB_PINNED)
    for (k, p) in zip(kl, _QB_PINNED)
        want = _qb_expected(p)
        k == want || println(stderr, "  ours  ", k, "\n  want  ", want)
        @test k == want
    end
end

@testset "the Q10 second rows are not vacuous" begin
    # the program loaded; every row has its answer line; the chunked rows have the chunks swipl delivers
    @test _QB_PINNED[1] == "ok"
    @test length(_QB_PINNED) == length(_QB_CASES) + 1
    for (id, _) in _QB_CASES
        @test any(l -> startswith(l, "t_$id "), _QB_PINNED)
    end
    answers(id) = count(
        "c" * _qb_codes("t_$id") * "/1(",
        only(filter(l -> startswith(l, "t_$id "), _QB_PINNED))
    )
    @test answers("fb01") == 3     # [1,2] [3,4] [5]: two redos of `$suspend_findall_bag`
    @test answers("fb02") == 4     # [1,2] [3,4] [5,6] [7]: a third chunk (the counters carried over two suspensions)
    @test answers("fb03") == 3
    @test answers("fb04") == 1
    @test answers("fb05") == 2     # a full first chunk, then the rest
    @test answers("fb06") == 1     # the cut after the first chunk
    @test answers("fb07") == 3     # a findall/3 runs while the bag is suspended
    @test answers("fb08") == 3     # an inner findnsols pending inside the outer goal
    @test answers("fb09") == 2     # an inner findnsols cut (`once/1`) inside the outer goal
    @test answers("fb10") == 1     # a cut after the SECOND chunk
    @test answers("fb11") == 1     # the chunks added to an OUTER hand-made bag
    @test answers("fb12") == 2     # a chunk, then the exception of the redone goal
    @test answers("fb15") == 3     # count(2)
    @test any(
        l -> startswith(l, "t_fb12 ") && occursin("a" * _qb_codes("q10b_err"), l),
        _QB_PINNED
    )
    @test any(
        l -> startswith(l, "t_pa01 ") && occursin("a" * _qb_codes("usr2"), l), _QB_PINNED
    )
    @test any(
        l ->
            startswith(l, "t_pa02 ") && occursin("a" * _qb_codes("usr1"), l) &&
            occursin("a" * _qb_codes("usr2"), l),
        _QB_PINNED
    )
    @test any(l -> startswith(l, "t_pa03 ") && occursin("i0", l), _QB_PINNED)     # the integer 0, not an atom
    @test any(l -> startswith(l, "t_pa11 ") && occursin("i0", l), _QB_PINNED)
    @test any(
        l ->
            startswith(l, "t_pa06 ") && occursin("a" * _qb_codes("instantiation_error"), l),
        _QB_PINNED
    )
    @test count(
        l -> startswith(l, "t_pa") && occursin("c" * _qb_codes("domain_error"), l),
        _QB_PINNED
    ) ==
        4   # pa04, pa12, pa13, pa17
    @test any(l -> startswith(l, "t_tq04 ") && count("c[91,124,93]/2(", l) == 8, _QB_PINNED)   # eight properties
    @test any(
        l -> startswith(l, "t_tq05 ") && occursin("a" * _qb_codes("yes"), l), _QB_PINNED
    )
    @test any(
        l -> startswith(l, "t_tq06 ") && occursin("a" * _qb_codes("no"), l), _QB_PINNED
    )
    @test any(l -> startswith(l, "t_tq01 ") && occursin("i4", l), _QB_PINNED)
    # the one known difference: swipl's answer is the pin, the kernel's differs from it
    ga07 = only(filter(l -> startswith(l, "t_ga07 "), _QB_PINNED))
    @test occursin("a" * _qb_codes("counted"), ga07)
    @test _qb_expected(ga07) != ga07
    @test occursin("a" * _qb_codes("not_counted"), _qb_expected(ga07))
    @test count(l -> _qb_expected(l) != l, _QB_PINNED) == length(_QB_KERNEL_DIFF)
end

@testset "the Q10 second pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_QB_PINNED) == length(_QB_CASES) + 1
    if swipl === nothing
        @info "Q10B LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _qb_file()
        @test _qb_swipl_lines(f, names) == _QB_PINNED
    end
end
