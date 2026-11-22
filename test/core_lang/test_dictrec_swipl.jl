# ORIGINAL: a LIVE differential of DICT-REC's predicates against swipl at the pin (pl-dict.c, pl-btree.c, pl-write.c) — rows
# dr01-dr131: b_set_dict/3, nb_set_dict/3, nb_link_dict/3, $btree_find_node/5 and $needs_quotes/1:
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver and the term encoder are test_dict_preds_swipl.jl's (one extractor, both sides).
#   * Every answer line is swipl's, PINNED (swipl 10.1.20, the pin binary ~/.local/swipl-pin1-18168e62/bin/swipl, evidence/DICT-REC/dictrec_rows.out, two
#     byte-identical runs); with `swipl` on PATH the live answers are compared with the pins too.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
#   * Dicts are built by dict_create/3 only and never appear in an answer: a row observes one through `dpairs/2` (get_dict/3 findall, msort).
#   * $btree_find_node/5 rows dr51-dr99 keep every position INSIDE the node (kp, lp, rp < arity): a position past the compound is a
#     DIVERGES (src/pl-btree.jl: refused with a type error, bounds checking), so no swipl pin holds; the LK-ONLY rows lkb1-lkb3 name it.
#   * LK-ONLY rows (not comparable with swipl): the REFUSED owner rows ($atom_references/2, $atom_completions/2, malloc_property/1,
#     wait_for_input/3) — what they are and which step refused them; the $btree_find_node/5 position rows lkb1-lkb3; see the last testsets.
# dr01-dr19: b_set_dict/3
# dr20-dr36: nb_set_dict/3
# dr37-dr50: nb_link_dict/3
# dr51-dr99: $btree_find_node/5
# dr100-dr128: $needs_quotes/1
# dr129-dr131: the dict is checked before the key
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the predicates ride the term layer through the dict cells and callProlog; every type in CI
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _DR = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_drs(x) = lk_sym(_DR, Symbol(x))

_dr_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _dr_enc(t::_DR, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _dr_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _dr_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _dr_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_dr_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test/core_lang/test_ssu_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _DR_DRIVER = raw"""
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
function _dr_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _DR_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end



# the program: dpairs/2 observes a dict
const _DR_PROGRAM = raw"""
dpairs(D, Ps) :- findall(K-V, get_dict(K, D, V), Ps0), msort(Ps0, Ps).
"""

const _DR_CASES = [
    ("dr01", raw"dict_create(D, t, [a-1, b-2]), b_set_dict(a, D, 9), dpairs(D, R)"),
    ("dr02", raw"dict_create(D, t, [a-1, b-2]), b_set_dict(b, D, 9), dpairs(D, R)"),
    ("dr03", raw"dict_create(D, t, [a-1, b-2]), ( b_set_dict(a, D, 9), fail ; dpairs(D, R) )"),
    ("dr04", raw"dict_create(D, t, [a-1, b-2]), b_set_dict(a, D, 9), b_set_dict(b, D, 8), dpairs(D, R)"),
    ("dr05", raw"dict_create(D, t, [a-1, b-2]), ( b_set_dict(a, D, 9), b_set_dict(b, D, 8), fail ; dpairs(D, R) )"),
    ("dr06", raw"dict_create(D, t, [a-1, b-2]), catch(b_set_dict(c, D, 9), error(existence_error(T, K, _), _), R = ex(T, K))"),
    ("dr07", raw"b_set_dict(a, foo, 9), R = yes"),
    ("dr08", raw"b_set_dict(a, [a-1], 9), R = yes"),
    ("dr09", raw"b_set_dict(a, _, 9), R = yes"),
    ("dr10", raw"dict_create(D, t, [a-1]), b_set_dict(1.5, D, 9), R = yes"),
    ("dr11", raw"dict_create(D, t, [a-1]), b_set_dict(_, D, 9), R = yes"),
    ("dr12", raw"dict_create(D, t, [1-one, 2-two]), b_set_dict(2, D, 9), dpairs(D, R)"),
    ("dr13", raw"dict_create(D, t, [a-1]), b_set_dict(a, D, f(X)), get_dict(a, D, f(Y)), X == Y, R = same"),
    ("dr14", raw"dict_create(D, t, [a-1]), b_set_dict(a, D, f(X)), X = 3, get_dict(a, D, V), R = V"),
    ("dr15", raw"dict_create(D, t, [a-X, b-2]), b_set_dict(a, D, 9), dpairs(D, P), R = X-P"),
    ("dr16", raw"dict_create(D, t, [a-X, b-2]), ( b_set_dict(a, D, 9), fail ; get_dict(a, D, V), V == X, R = unbound_again )"),
    ("dr17", raw"dict_create(D, t, [a-1]), b_set_dict(a, D, 9), put_dict(a, D, 7, N), dpairs(N, P), dpairs(D, Q), R = P-Q"),
    ("dr18", raw"dict_create(D, t, [a-1, b-2]), b_set_dict(a, D, 1), dpairs(D, R)"),
    ("dr19", raw"dict_create(D, t, [a-1]), b_set_dict(a, D, 9), get_dict(a, D, V), R = V"),
    ("dr20", raw"dict_create(D, t, [a-1, b-2]), nb_set_dict(a, D, 9), dpairs(D, R)"),
    ("dr21", raw"dict_create(D, t, [a-1, b-2]), nb_set_dict(b, D, 9), dpairs(D, R)"),
    ("dr22", raw"dict_create(D, t, [a-1, b-2]), ( nb_set_dict(a, D, 9), fail ; dpairs(D, R) )"),
    ("dr23", raw"dict_create(D, t, [a-1, b-2]), nb_set_dict(a, D, 9), nb_set_dict(b, D, 8), dpairs(D, R)"),
    ("dr24", raw"dict_create(D, t, [a-1, b-2]), catch(nb_set_dict(c, D, 9), error(existence_error(T, K, _), _), R = ex(T, K))"),
    ("dr25", raw"nb_set_dict(a, foo, 9), R = yes"),
    ("dr26", raw"nb_set_dict(a, [a-1], 9), R = yes"),
    ("dr27", raw"nb_set_dict(a, _, 9), R = yes"),
    ("dr28", raw"dict_create(D, t, [a-1]), nb_set_dict(1.5, D, 9), R = yes"),
    ("dr29", raw"dict_create(D, t, [a-1]), nb_set_dict(_, D, 9), R = yes"),
    ("dr30", raw"dict_create(D, t, [1-one, 2-two]), nb_set_dict(2, D, 9), dpairs(D, R)"),
    ("dr31", raw"dict_create(D, t, [a-1]), nb_set_dict(a, D, f(X)), get_dict(a, D, f(Y)), Y = 1, R = X"),
    ("dr32", raw"dict_create(D, t, [a-1]), nb_set_dict(a, D, f(X)), get_dict(a, D, f(Y)), ( X == Y -> R = same ; R = copied )"),
    ("dr33", raw"dict_create(D, t, [a-1]), ( nb_set_dict(a, D, f(x)), fail ; get_dict(a, D, V), R = V )"),
    ("dr34", raw"dict_create(D, t, [a-1]), nb_set_dict(a, D, g(h(i))), get_dict(a, D, V), R = V"),
    ("dr35", raw"dict_create(D, t, [a-1]), nb_set_dict(a, D, 9), put_dict(a, D, 7, N), dpairs(N, P), dpairs(D, Q), R = P-Q"),
    ("dr36", raw"dict_create(D, t, [a-X]), nb_set_dict(a, D, 9), dpairs(D, P), R = X-P"),
    ("dr37", raw"dict_create(D, t, [a-1, b-2]), nb_link_dict(a, D, 9), dpairs(D, R)"),
    ("dr38", raw"dict_create(D, t, [a-1, b-2]), nb_link_dict(b, D, 9), dpairs(D, R)"),
    ("dr39", raw"dict_create(D, t, [a-1, b-2]), ( nb_link_dict(a, D, 9), fail ; dpairs(D, R) )"),
    ("dr40", raw"dict_create(D, t, [a-1, b-2]), catch(nb_link_dict(c, D, 9), error(existence_error(T, K, _), _), R = ex(T, K))"),
    ("dr41", raw"nb_link_dict(a, foo, 9), R = yes"),
    ("dr42", raw"nb_link_dict(a, [a-1], 9), R = yes"),
    ("dr43", raw"nb_link_dict(a, _, 9), R = yes"),
    ("dr44", raw"dict_create(D, t, [a-1]), nb_link_dict(1.5, D, 9), R = yes"),
    ("dr45", raw"dict_create(D, t, [a-1]), nb_link_dict(_, D, 9), R = yes"),
    ("dr46", raw"dict_create(D, t, [1-one, 2-two]), nb_link_dict(2, D, 9), dpairs(D, R)"),
    ("dr47", raw"dict_create(D, t, [a-1]), nb_link_dict(a, D, f(X)), get_dict(a, D, f(Y)), Y = 1, R = X"),
    ("dr48", raw"dict_create(D, t, [a-1]), nb_link_dict(a, D, f(X)), get_dict(a, D, f(Y)), ( X == Y -> R = same ; R = copied )"),
    ("dr49", raw"dict_create(D, t, [a-1]), nb_link_dict(a, D, g(h(i))), get_dict(a, D, V), R = V"),
    ("dr50", raw"dict_create(D, t, [a-1]), nb_link_dict(a, D, 9), put_dict(a, D, 7, N), dpairs(N, P), dpairs(D, Q), R = P-Q"),
    ("dr51", raw"'$btree_find_node'(m, t(m,mv,<,t(f,fv,<,t,t),t(s,sv,<,t,t)), 0x010405, N, A), R = A-N"),
    ("dr52", raw"'$btree_find_node'(f, t(m,mv,<,t(f,fv,<,t,t),t(s,sv,<,t,t)), 0x010405, N, A), R = A-N"),
    ("dr53", raw"'$btree_find_node'(s, t(m,mv,<,t(f,fv,<,t,t),t(s,sv,<,t,t)), 0x010405, N, A), R = A-N"),
    ("dr54", raw"'$btree_find_node'(a, t(m,mv,<,t(f,fv,<,t,t),t(s,sv,<,t,t)), 0x010405, N, A), R = A-N"),
    ("dr55", raw"'$btree_find_node'(z, t(m,mv,<,t(f,fv,<,t,t),t(s,sv,<,t,t)), 0x010405, N, A), R = A-N"),
    ("dr56", raw"'$btree_find_node'(g, t(m,mv,<,t(f,fv,<,t,t),t(s,sv,<,t,t)), 0x010405, N, A), R = A-N"),
    ("dr57", raw"'$btree_find_node'(r, t(m,mv,<,t(f,fv,<,t,t),t(s,sv,<,t,t)), 0x010405, N, A), R = A-N"),
    ("dr58", raw"'$btree_find_node'(k, t(k,v,<,t,t), 0x010405, N, A), R = A-N"),
    ("dr59", raw"'$btree_find_node'(a, t(k,v,<,t,t), 0x010405, N, A), R = A-N"),
    ("dr60", raw"'$btree_find_node'(z, t(k,v,<,t,t), 0x010405, N, A), R = A-N"),
    ("dr61", raw"'$btree_find_node'(a, t(k,v,<,u(a),t), 0x010405, N, A), R = A-N"),
    ("dr62", raw"'$btree_find_node'(a, t(k,v,<,t(a,b,c,d,e,f),t), 0x010405, N, A), R = A-N"),
    ("dr63", raw"'$btree_find_node'(a, t(k,v,<,t(c,v,<,t,t),t), 0x010405, N, A), R = A-N"),
    ("dr64", raw"'$btree_find_node'(5, n(5,n(2,e,e),n(8,e,e)), 0x010203, N, A), R = A-N"),
    ("dr65", raw"'$btree_find_node'(2, n(5,n(2,e,e),n(8,e,e)), 0x010203, N, A), R = A-N"),
    ("dr66", raw"'$btree_find_node'(8, n(5,n(2,e,e),n(8,e,e)), 0x010203, N, A), R = A-N"),
    ("dr67", raw"'$btree_find_node'(1, n(5,n(2,e,e),n(8,e,e)), 0x010203, N, A), R = A-N"),
    ("dr68", raw"'$btree_find_node'(9, n(5,n(2,e,e),n(8,e,e)), 0x010203, N, A), R = A-N"),
    ("dr69", raw"'$btree_find_node'(3, n(5,n(2,e,e),n(8,e,e)), 0x010203, N, A), R = A-N"),
    ("dr70", raw"'$btree_find_node'(5, n(5,n(2,e,e),n(8,e,e)), 0x010203, n(5,L,Rt), A), R = A-L-Rt"),
    ("dr71", raw"'$btree_find_node'(2, n(5,n(2,e,e),n(8,e,e)), 0x010203, N, '='), R = N"),
    ("dr72", raw"'$btree_find_node'(2, n(5,n(2,e,e),n(8,e,e)), 0x010203, N, '<'), R = N"),
    ("dr73", raw"'$btree_find_node'(2, n(5,n(2,e,e),n(8,e,e)), 0x010203, foo, A), R = A"),
    ("dr74", raw"'$btree_find_node'(1, n(5,n(2,e,e),n(8,e,e)), 0x010203, n(2,e,e), A), R = A"),
    ("dr75", raw"'$btree_find_node'(1, n(5,n(2,e,e),n(8,e,e)), 0x010203, n(5,_,_), A), R = A"),
    ("dr76", raw"'$btree_find_node'(1, n(5,n(2,e,e),n(8,e,e)), 0x010203, N, '>'), R = N"),
    ("dr77", raw"'$btree_find_node'(1, n(5,n(2,e,e),n(8,e,e)), 0x010203, N, '<'), R = N"),
    ("dr78", raw"'$btree_find_node'(1, n(5,n(2,e,e),n(8,e,e)), 0x010302, N, A), R = A-N"),
    ("dr79", raw"'$btree_find_node'(9, n(5,n(2,e,e),n(8,e,e)), 0x010302, N, A), R = A-N"),
    ("dr80", raw"'$btree_find_node'(5, n(n(2,e,e),5,n(8,e,e)), 0x020103, N, A), R = A-N"),
    ("dr81", raw"'$btree_find_node'(1, m(a,3,b), 0x020103, N, A), R = A-N"),
    ("dr82", raw"'$btree_find_node'(_, n(5,e,e), 0x010203, N, A), R = A-N"),
    ("dr83", raw"'$btree_find_node'(f(x), n(5,e,e), 0x010203, N, A), R = A-N"),
    ("dr84", raw"'$btree_find_node'(a, n(5,e,e), 0x010203, N, A), R = A-N"),
    ("dr85", raw"'$btree_find_node'(1.5, n(5,e,e), 0x010203, N, A), R = A-N"),
    ("dr86", raw"'$btree_find_node'(m, t(m,mv,<,t(f,fv,<,t,t),t(s,sv,<,t,t)), foo, N, A), R = A-N"),
    ("dr87", raw"'$btree_find_node'(m, t(m,mv,<,t(f,fv,<,t,t),t(s,sv,<,t,t)), -1, N, A), R = A-N"),
    ("dr88", raw"'$btree_find_node'(m, t(m,mv,<,t(f,fv,<,t,t),t(s,sv,<,t,t)), 0, N, A), R = A-N"),
    ("dr89", raw"'$btree_find_node'(m, t(m,mv,<,t(f,fv,<,t,t),t(s,sv,<,t,t)), _, N, A), R = A-N"),
    ("dr90", raw"'$btree_find_node'(m, t(m,mv,<,t(f,fv,<,t,t),t(s,sv,<,t,t)), 1.5, N, A), R = A-N"),
    ("dr91", raw"'$btree_find_node'(m, foo, 0x010405, N, A), R = A-N"),
    ("dr92", raw"'$btree_find_node'(m, _, 0x010405, N, A), R = A-N"),
    ("dr93", raw"'$btree_find_node'(m, 42, 0x010405, N, A), R = A-N"),
    ("dr94", raw"'$btree_find_node'(m, t(a,b), 0x010405, N, A), R = A-N"),
    ("dr95", raw"'$btree_find_node'(m, n(1,e,e), 0x010206, N, A), R = A-N"),
    ("dr96", raw"'$btree_find_node'(m, n(1,e,e), 0x060203, N, A), R = A-N"),
    ("dr97", raw"'$btree_find_node'(m, n(1,e,e), 0x010602, N, A), R = A-N"),
    ("dr98", raw"'$btree_find_node'(m, [a,b,c], 0x010102, N, A), R = A-N"),
    ("dr99", raw"string_codes(S, [115]), '$btree_find_node'(m, S, 0x010203, N, A), R = A-N"),
    ("dr100", raw"'$needs_quotes'('hello world'), R = yes"),
    ("dr101", raw"'$needs_quotes'('A'), R = yes"),
    ("dr102", raw"'$needs_quotes'('_x'), R = yes"),
    ("dr103", raw"'$needs_quotes'(''), R = yes"),
    ("dr104", raw"'$needs_quotes'(abc), R = yes"),
    ("dr105", raw"'$needs_quotes'(a1), R = yes"),
    ("dr106", raw"'$needs_quotes'(a_b), R = yes"),
    ("dr107", raw"'$needs_quotes'(+), R = yes"),
    ("dr108", raw"'$needs_quotes'(;), R = yes"),
    ("dr109", raw"'$needs_quotes'(!), R = yes"),
    ("dr110", raw"'$needs_quotes'(','), R = yes"),
    ("dr111", raw"'$needs_quotes'('|'), R = yes"),
    ("dr112", raw"'$needs_quotes'('a.b'), R = yes"),
    ("dr113", raw"'$needs_quotes'('[]'), R = yes"),
    ("dr114", raw"'$needs_quotes'([]), R = yes"),
    ("dr115", raw"'$needs_quotes'({}), R = yes"),
    ("dr116", raw"'$needs_quotes'('{}'), R = yes"),
    ("dr117", raw"'$needs_quotes'(=..), R = yes"),
    ("dr118", raw"'$needs_quotes'(\+), R = yes"),
    ("dr119", raw"'$needs_quotes'('1a'), R = yes"),
    ("dr120", raw"'$needs_quotes'('\n'), R = yes"),
    ("dr121", raw"atom_codes(A, [233]), '$needs_quotes'(A), R = yes"),
    ("dr122", raw"atom_codes(A, [201]), '$needs_quotes'(A), R = yes"),
    ("dr123", raw"'$needs_quotes'(1), R = yes"),
    ("dr124", raw"string_codes(S, [115]), '$needs_quotes'(S), R = yes"),
    ("dr125", raw"'$needs_quotes'(f(x)), R = yes"),
    ("dr126", raw"'$needs_quotes'(_), R = yes"),
    ("dr127", raw"'$needs_quotes'([a]), R = yes"),
    ("dr128", raw"'$needs_quotes'(1.5), R = yes"),
    ("dr129", raw"b_set_dict(1.5, foo, 9), R = yes"),
    ("dr130", raw"nb_set_dict(_, foo, 9), R = yes"),
    ("dr131", raw"nb_link_dict(1.5, foo, 9), R = yes")
]

# swipl 10.1.20's answers to the program and cases above (the driver's lines; evidence/DICT-REC/dictrec_rows.out)
const _DR_PINNED = [
    "ok",
    "t_dr01 c[116,95,100,114,48,49]/1(c[91,124,93]/2(c[45]/2(a[97],i9),c[91,124,93]/2(c[45]/2(a[98],i2),nil)))",
    "t_dr02 c[116,95,100,114,48,50]/1(c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i9),nil)))",
    "t_dr03 c[116,95,100,114,48,51]/1(c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),nil)))",
    "t_dr04 c[116,95,100,114,48,52]/1(c[91,124,93]/2(c[45]/2(a[97],i9),c[91,124,93]/2(c[45]/2(a[98],i8),nil)))",
    "t_dr05 c[116,95,100,114,48,53]/1(c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),nil)))",
    "t_dr06 c[116,95,100,114,48,54]/1(c[101,120]/2(a[107,101,121],a[99]))",
    "t_dr07 c[116,95,100,114,48,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116],a[102,111,111])))",
    "t_dr08 c[116,95,100,114,48,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116],c[91,124,93]/2(c[45]/2(a[97],i1),nil))))",
    "t_dr09 c[116,95,100,114,48,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_dr10 c[116,95,100,114,49,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,107,101,121],f1.5)))",
    "t_dr11 c[116,95,100,114,49,49]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_dr12 c[116,95,100,114,49,50]/1(c[91,124,93]/2(c[45]/2(i1,a[111,110,101]),c[91,124,93]/2(c[45]/2(i2,i9),nil)))",
    "t_dr13 c[116,95,100,114,49,51]/1(a[115,97,109,101])",
    "t_dr14 c[116,95,100,114,49,52]/1(c[102]/1(i3))",
    "t_dr15 c[116,95,100,114,49,53]/1(c[45]/2(i9,c[91,124,93]/2(c[45]/2(a[97],i9),c[91,124,93]/2(c[45]/2(a[98],i2),nil))))",
    "t_dr16 c[116,95,100,114,49,54]/1(a[117,110,98,111,117,110,100,95,97,103,97,105,110])",
    "t_dr17 c[116,95,100,114,49,55]/1(c[45]/2(c[91,124,93]/2(c[45]/2(a[97],i7),nil),c[91,124,93]/2(c[45]/2(a[97],i9),nil)))",
    "t_dr18 c[116,95,100,114,49,56]/1(c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),nil)))",
    "t_dr19 c[116,95,100,114,49,57]/1(i9)",
    "t_dr20 c[116,95,100,114,50,48]/1(c[91,124,93]/2(c[45]/2(a[97],i9),c[91,124,93]/2(c[45]/2(a[98],i2),nil)))",
    "t_dr21 c[116,95,100,114,50,49]/1(c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i9),nil)))",
    "t_dr22 c[116,95,100,114,50,50]/1(c[91,124,93]/2(c[45]/2(a[97],i9),c[91,124,93]/2(c[45]/2(a[98],i2),nil)))",
    "t_dr23 c[116,95,100,114,50,51]/1(c[91,124,93]/2(c[45]/2(a[97],i9),c[91,124,93]/2(c[45]/2(a[98],i8),nil)))",
    "t_dr24 c[116,95,100,114,50,52]/1(c[101,120]/2(a[107,101,121],a[99]))",
    "t_dr25 c[116,95,100,114,50,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116],a[102,111,111])))",
    "t_dr26 c[116,95,100,114,50,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116],c[91,124,93]/2(c[45]/2(a[97],i1),nil))))",
    "t_dr27 c[116,95,100,114,50,55]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_dr28 c[116,95,100,114,50,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,107,101,121],f1.5)))",
    "t_dr29 c[116,95,100,114,50,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_dr30 c[116,95,100,114,51,48]/1(c[91,124,93]/2(c[45]/2(i1,a[111,110,101]),c[91,124,93]/2(c[45]/2(i2,i9),nil)))",
    "t_dr31 c[116,95,100,114,51,49]/1(V0)",
    "t_dr32 c[116,95,100,114,51,50]/1(a[99,111,112,105,101,100])",
    "t_dr33 c[116,95,100,114,51,51]/1(c[102]/1(a[120]))",
    "t_dr34 c[116,95,100,114,51,52]/1(c[103]/1(c[104]/1(a[105])))",
    "t_dr35 c[116,95,100,114,51,53]/1(c[45]/2(c[91,124,93]/2(c[45]/2(a[97],i7),nil),c[91,124,93]/2(c[45]/2(a[97],i9),nil)))",
    "t_dr36 c[116,95,100,114,51,54]/1(c[45]/2(V0,c[91,124,93]/2(c[45]/2(a[97],i9),nil)))",
    "t_dr37 c[116,95,100,114,51,55]/1(c[91,124,93]/2(c[45]/2(a[97],i9),c[91,124,93]/2(c[45]/2(a[98],i2),nil)))",
    "t_dr38 c[116,95,100,114,51,56]/1(c[91,124,93]/2(c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i9),nil)))",
    "t_dr39 c[116,95,100,114,51,57]/1(c[91,124,93]/2(c[45]/2(a[97],i9),c[91,124,93]/2(c[45]/2(a[98],i2),nil)))",
    "t_dr40 c[116,95,100,114,52,48]/1(c[101,120]/2(a[107,101,121],a[99]))",
    "t_dr41 c[116,95,100,114,52,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116],a[102,111,111])))",
    "t_dr42 c[116,95,100,114,52,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116],c[91,124,93]/2(c[45]/2(a[97],i1),nil))))",
    "t_dr43 c[116,95,100,114,52,51]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_dr44 c[116,95,100,114,52,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116,45,107,101,121],f1.5)))",
    "t_dr45 c[116,95,100,114,52,53]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_dr46 c[116,95,100,114,52,54]/1(c[91,124,93]/2(c[45]/2(i1,a[111,110,101]),c[91,124,93]/2(c[45]/2(i2,i9),nil)))",
    "t_dr47 c[116,95,100,114,52,55]/1(i1)",
    "t_dr48 c[116,95,100,114,52,56]/1(a[115,97,109,101])",
    "t_dr49 c[116,95,100,114,52,57]/1(c[103]/1(c[104]/1(a[105])))",
    "t_dr50 c[116,95,100,114,53,48]/1(c[45]/2(c[91,124,93]/2(c[45]/2(a[97],i7),nil),c[91,124,93]/2(c[45]/2(a[97],i9),nil)))",
    "t_dr51 c[116,95,100,114,53,49]/1(c[45]/2(a[61],c[116]/5(a[109],a[109,118],a[60],c[116]/5(a[102],a[102,118],a[60],a[116],a[116]),c[116]/5(a[115],a[115,118],a[60],a[116],a[116]))))",
    "t_dr52 c[116,95,100,114,53,50]/1(c[45]/2(a[61],c[116]/5(a[102],a[102,118],a[60],a[116],a[116])))",
    "t_dr53 c[116,95,100,114,53,51]/1(c[45]/2(a[61],c[116]/5(a[115],a[115,118],a[60],a[116],a[116])))",
    "t_dr54 c[116,95,100,114,53,52]/1(c[45]/2(a[60],c[116]/5(a[102],a[102,118],a[60],a[116],a[116])))",
    "t_dr55 c[116,95,100,114,53,53]/1(c[45]/2(a[62],c[116]/5(a[115],a[115,118],a[60],a[116],a[116])))",
    "t_dr56 c[116,95,100,114,53,54]/1(c[45]/2(a[62],c[116]/5(a[102],a[102,118],a[60],a[116],a[116])))",
    "t_dr57 c[116,95,100,114,53,55]/1(c[45]/2(a[60],c[116]/5(a[115],a[115,118],a[60],a[116],a[116])))",
    "t_dr58 c[116,95,100,114,53,56]/1(c[45]/2(a[61],c[116]/5(a[107],a[118],a[60],a[116],a[116])))",
    "t_dr59 c[116,95,100,114,53,57]/1(c[45]/2(a[60],c[116]/5(a[107],a[118],a[60],a[116],a[116])))",
    "t_dr60 c[116,95,100,114,54,48]/1(c[45]/2(a[62],c[116]/5(a[107],a[118],a[60],a[116],a[116])))",
    "t_dr61 c[116,95,100,114,54,49]/1(c[45]/2(a[60],c[116]/5(a[107],a[118],a[60],c[117]/1(a[97]),a[116])))",
    "t_dr62 c[116,95,100,114,54,50]/1(c[45]/2(a[60],c[116]/5(a[107],a[118],a[60],c[116]/6(a[97],a[98],a[99],a[100],a[101],a[102]),a[116])))",
    "t_dr63 c[116,95,100,114,54,51]/1(c[45]/2(a[60],c[116]/5(a[99],a[118],a[60],a[116],a[116])))",
    "t_dr64 c[116,95,100,114,54,52]/1(c[45]/2(a[61],c[110]/3(i5,c[110]/3(i2,a[101],a[101]),c[110]/3(i8,a[101],a[101]))))",
    "t_dr65 c[116,95,100,114,54,53]/1(c[45]/2(a[61],c[110]/3(i2,a[101],a[101])))",
    "t_dr66 c[116,95,100,114,54,54]/1(c[45]/2(a[61],c[110]/3(i8,a[101],a[101])))",
    "t_dr67 c[116,95,100,114,54,55]/1(c[45]/2(a[60],c[110]/3(i2,a[101],a[101])))",
    "t_dr68 c[116,95,100,114,54,56]/1(c[45]/2(a[62],c[110]/3(i8,a[101],a[101])))",
    "t_dr69 c[116,95,100,114,54,57]/1(c[45]/2(a[62],c[110]/3(i2,a[101],a[101])))",
    "t_dr70 c[116,95,100,114,55,48]/1(c[45]/2(c[45]/2(a[61],c[110]/3(i2,a[101],a[101])),c[110]/3(i8,a[101],a[101])))",
    "t_dr71 c[116,95,100,114,55,49]/1(c[110]/3(i2,a[101],a[101]))",
    "t_dr72",
    "t_dr73",
    "t_dr74 c[116,95,100,114,55,52]/1(a[60])",
    "t_dr75",
    "t_dr76",
    "t_dr77 c[116,95,100,114,55,55]/1(c[110]/3(i2,a[101],a[101]))",
    "t_dr78 c[116,95,100,114,55,56]/1(c[45]/2(a[60],c[110]/3(i8,a[101],a[101])))",
    "t_dr79 c[116,95,100,114,55,57]/1(c[45]/2(a[62],c[110]/3(i2,a[101],a[101])))",
    "t_dr80 c[116,95,100,114,56,48]/1(c[45]/2(a[61],c[110]/3(c[110]/3(i2,a[101],a[101]),i5,c[110]/3(i8,a[101],a[101]))))",
    "t_dr81 c[116,95,100,114,56,49]/1(c[45]/2(a[60],c[109]/3(a[97],i3,a[98])))",
    "t_dr82 c[116,95,100,114,56,50]/1(c[45]/2(a[60],c[110]/3(i5,a[101],a[101])))",
    "t_dr83 c[116,95,100,114,56,51]/1(c[45]/2(a[62],c[110]/3(i5,a[101],a[101])))",
    "t_dr84 c[116,95,100,114,56,52]/1(c[45]/2(a[62],c[110]/3(i5,a[101],a[101])))",
    "t_dr85 c[116,95,100,114,56,53]/1(c[45]/2(a[60],c[110]/3(i5,a[101],a[101])))",
    "t_dr86 c[116,95,100,114,56,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[102,111,111])))",
    "t_dr87 c[116,95,100,114,56,55]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[117,105,110,116])))",
    "t_dr88 c[116,95,100,114,56,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,116,114,101,101],c[116]/5(a[109],a[109,118],a[60],c[116]/5(a[102],a[102,118],a[60],a[116],a[116]),c[116]/5(a[115],a[115,118],a[60],a[116],a[116])))))",
    "t_dr89 c[116,95,100,114,56,57]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_dr90 c[116,95,100,114,57,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],f1.5)))",
    "t_dr91 c[116,95,100,114,57,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,116,114,101,101],a[102,111,111])))",
    "t_dr92 c[116,95,100,114,57,50]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_dr93 c[116,95,100,114,57,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,116,114,101,101],i42)))",
    "t_dr94 c[116,95,100,114,57,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,116,114,101,101],c[116]/2(a[97],a[98]))))",
    "t_dr95 c[116,95,100,114,57,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,116,114,101,101],c[110]/3(i1,a[101],a[101]))))",
    "t_dr96 c[116,95,100,114,57,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,116,114,101,101],c[110]/3(i1,a[101],a[101]))))",
    "t_dr97 c[116,95,100,114,57,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,116,114,101,101],c[110]/3(i1,a[101],a[101]))))",
    "t_dr98 c[116,95,100,114,57,56]/1(c[45]/2(a[62],c[91,124,93]/2(a[99],nil)))",
    "t_dr99 c[116,95,100,114,57,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[98,116,114,101,101],s[115])))",
    "t_dr100 c[116,95,100,114,49,48,48]/1(a[121,101,115])",
    "t_dr101 c[116,95,100,114,49,48,49]/1(a[121,101,115])",
    "t_dr102 c[116,95,100,114,49,48,50]/1(a[121,101,115])",
    "t_dr103 c[116,95,100,114,49,48,51]/1(a[121,101,115])",
    "t_dr104",
    "t_dr105",
    "t_dr106",
    "t_dr107",
    "t_dr108",
    "t_dr109",
    "t_dr110 c[116,95,100,114,49,49,48]/1(a[121,101,115])",
    "t_dr111 c[116,95,100,114,49,49,49]/1(a[121,101,115])",
    "t_dr112 c[116,95,100,114,49,49,50]/1(a[121,101,115])",
    "t_dr113 c[116,95,100,114,49,49,51]/1(a[121,101,115])",
    "t_dr114 c[116,95,100,114,49,49,52]/1(a[121,101,115])",
    "t_dr115",
    "t_dr116",
    "t_dr117",
    "t_dr118",
    "t_dr119 c[116,95,100,114,49,49,57]/1(a[121,101,115])",
    "t_dr120 c[116,95,100,114,49,50,48]/1(a[121,101,115])",
    "t_dr121",
    "t_dr122 c[116,95,100,114,49,50,50]/1(a[121,101,115])",
    "t_dr123 c[116,95,100,114,49,50,51]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],i1)))",
    "t_dr124 c[116,95,100,114,49,50,52]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],s[115])))",
    "t_dr125 c[116,95,100,114,49,50,53]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],c[102]/1(a[120]))))",
    "t_dr126 c[116,95,100,114,49,50,54]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_dr127 c[116,95,100,114,49,50,55]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],c[91,124,93]/2(a[97],nil))))",
    "t_dr128 c[116,95,100,114,49,50,56]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[97,116,111,109],f1.5)))",
    "t_dr129 c[116,95,100,114,49,50,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116],a[102,111,111])))",
    "t_dr130 c[116,95,100,114,49,51,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116],a[102,111,111])))",
    "t_dr131 c[116,95,100,114,49,51,49]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[100,105,99,116],a[102,111,111])))"
]

function _dr_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _DR_CASES]
    text =
        _DR_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _DR_CASES
        ])
    f = joinpath(mktempdir(), "dictrec.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _dr_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_DR}()
    ld = LK.PL_local_data{_DR}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _dr_enc(ball::_DR)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_drs(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_DR, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _dr_enc(mk_expr(_DR, _DR[_drs(name), lk_answers(ld, (a:a)...)...]))
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


@testset "dict-record rows: the kernel's answers are swipl's (dr01-dr131)" begin
    f, names = _dr_file()
    kl, _, _ = _dr_kernel(f, names)
    @test length(kl) == length(_DR_PINNED)
    for (k, p) in zip(kl, _DR_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

@testset "the dict-record rows are not vacuous (dr01-dr131)" begin
    rows = _DR_PINNED[2:end]                                                       # the driver's first line is `ok`
    @test _DR_PINNED[1] == "ok"
    @test length(rows) == length(_DR_CASES) == 131
    code(t) = "[" * join(Int.(collect(t)), ",") * "]"
    @test count(l -> occursin(code("raised"), l), rows) == 37
    @test count(l -> occursin(code("type_error") * "/2", l), rows) == 27
    @test count(l -> occursin(code("instantiation_error"), l), rows) == 9
    @test count(l -> occursin(code("representation_error") * "/1", l), rows) == 1
    @test count(l -> occursin(code("btree"), l) && occursin(code("type_error"), l), rows) == 8
    # rows that fail have no answer after the name; rows that answer `yes`
    @test count(l -> occursin(r"^t_dr\d+$", l), rows) == 15
    @test count(l -> endswith(l, "(a" * code("yes") * ")"), rows) == 12
    # no answer holds a dict (a dict is a compound named `dict`)
    @test !any(l -> occursin(code("dict") * "/", l), _DR_PINNED)
    # the dict is checked before the key (dr129-dr131: a bad key and a non-dict raise type_error(dict, foo))
    @test all(l -> occursin(code("dict") * ",a" * code("foo"), l), rows[129:131])
    # the three setters differ in what they leave behind: b_set_dict undoes on backtracking (dr03), nb_set_dict keeps the new
    # value (dr22), and a compound value is DUPLICATED by nb_set_dict (dr31: X unbound) but LINKED by nb_link_dict (dr47: X = 1)
    @test endswith(_DR_PINNED[1 + 3], "c[45]/2(a[97],i1),c[91,124,93]/2(c[45]/2(a[98],i2),nil)))")
    @test endswith(_DR_PINNED[1 + 22], "c[45]/2(a[97],i9),c[91,124,93]/2(c[45]/2(a[98],i2),nil)))")
    @test endswith(_DR_PINNED[1 + 31], "(V0)")
    @test endswith(_DR_PINNED[1 + 47], "(i1)")
    # '$btree_find_node'/5: the node a search ends at and the `=`, `<`, `>` it reports (dr51 root, dr54 left of a miss, dr55 right of a miss)
    @test startswith(_DR_PINNED[1 + 51], "t_dr51 ") && occursin("c[45]/2(a[61],", _DR_PINNED[1 + 51])
    @test occursin("c[45]/2(a[60],", _DR_PINNED[1 + 54])
    @test occursin("c[45]/2(a[62],", _DR_PINNED[1 + 55])
end

# LK-ONLY rows (nothing to compare with swipl): the owner rows docs/r2_owners.tsv carries for the predicates the kernel REFUSES,
# each with what it is and the step that refused it. swipl DEFINES the first two and wait_for_input/3 (and has no malloc_property/1
# unless it runs on tcmalloc), so no pin could hold: the rows check the refusal is on the books and the kernel does not define them.
const _DR_REFUSED = [
    # (name, arity, what, step)
    ("\$atom_references", 2, "atom reference counts: the kernel's atoms carry no count (atom-GC family)", "D-0634 D5"),
    ("\$atom_completions", 2, "atom-table walk for console completion: the kernel's atoms are not an array (atom-GC family)", "D-0634 D5"),
    ("malloc_property", 1, "registered only on a tcmalloc process (pl-alloc.c:1782)", "REFUSED (no tcmalloc)"),
    ("wait_for_input", 3, "polls OS descriptors of streams (pl-file.c:2752): a kernel stream has none", "REFUSED (no descriptors)")
]

@testset "LK-ONLY: the REFUSED owner rows are on the books and the kernel does not define the predicates" begin
    owners = Dict{String, String}()
    for l in eachline(joinpath(@__DIR__, "..", "..", "docs", "r2_owners.tsv"))
        (isempty(l) || startswith(l, '#')) && continue
        cols = split(l, '\t')
        length(cols) >= 2 && (owners[String(cols[1])] = String(cols[2]))
    end
    gd = LK.PL_global_data{_DR}()
    for (name, arity, what, step) in _DR_REFUSED
        @test !isempty(what) && !isempty(step)
        @test get(owners, "pred:$name/$arity", "") == "REFUSED"
        proc = LK.isCurrentProcedure(sym_key(_drs(name)), arity, LK.MODULE_user(gd))
        @test proc === nothing || !LK.isDefinedProcedure(gd, proc)
    end
end

# LK-ONLY rows lkb1-lkb3 (nothing to compare with swipl): a position PAST the compound. The tree n(1,e,e) has arity 3, so an argument
# number of 4 is one past its last argument; swipl's answer is out of range there (no pin). The kernel refuses each of the three
# positions (key, left, right) with type_error(btree, Tree) (bounds checking: the named DIVERGES in src/pl-btree.jl).
const _DR_LKB = [
    ("lkb1", raw"'$btree_find_node'(m, n(1,e,e), 0x010403, N, A), R = A-N"),   # left position 4 > arity 3
    ("lkb2", raw"'$btree_find_node'(m, n(1,e,e), 0x010204, N, A), R = A-N"),   # right position 4 > arity 3
    ("lkb3", raw"'$btree_find_node'(m, n(1,e,e), 0x040203, N, A), R = A-N")    # key position 4 > arity 3
]

@testset "LK-ONLY: a \$btree_find_node/5 position past the compound is a type error (lkb1-lkb3)" begin
    code(t) = "[" * join(Int.(collect(t)), ",") * "]"
    names = String[id for (id, _) in _DR_LKB]
    text =
        join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _DR_LKB
        ])
    f = joinpath(mktempdir(), "dictrec_lkb.pl")
    write(f, text)
    kl, _, _ = _dr_kernel(f, ["t_$(n)" for n in names])
    @test kl[1] == "ok"
    @test length(kl) == length(_DR_LKB) + 1
    for (n, l) in zip(names, kl[2:end])
        # the answer is `raised(type_error(btree, n(1,e,e)))`, the tree as the caller wrote it (as dr95-dr97)
        @test l == "t_$(n) " * "c" * code("t_$(n)") * "/1(c" * code("raised") * "/1(c" * code("type_error") *
                  "/2(a" * code("btree") * ",c" * code("n") * "/3(i1,a" * code("e") * ",a" * code("e") * "))))"
    end
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    # the pinned table is the driver's whole output (the inert-testset guard: an assertion either way)
    @test length(_DR_PINNED) == length(_DR_CASES) + 1
    if swipl === nothing
        @info "DICT-REC LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _dr_file()
        @test _dr_swipl_lines(f, names) == _DR_PINNED
    end
end
