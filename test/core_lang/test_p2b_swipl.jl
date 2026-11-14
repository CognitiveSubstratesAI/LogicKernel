# ORIGINAL: a LIVE differential of P2b's pl-prims.c predicates — sub_atom_icasechk/3 (pl-prims.c 5099-5170) and '$seek_list'/4
# (pl-prims.c 3005-3030) — against swipl at the pin: rows q01-q37 (sub_atom_icasechk/3) and q40-q59 ('$seek_list'/4), as
# test_p2_swipl.jl's driver (a program consulted by the kernel's loader; cases `t_<id>(R)` run in order, each wrapped in
# `catch(Goal, error(E, _), R = raised(E))`; every answer line is swipl's, PINNED, two runs byte-identical, evidence/F6/gen_p2b.py).
#   * q08 and q17 pin swipl's own quirk: the narrow loop compares a needle character with the haystack's `toLower`, which is `c + 32`
#     for EVERY character (pl-ctype.h), so a needle '@' matches a haystack ' ' and a needle NUL matches the byte 0xE0.
#   * UNVERIFIED on the kernel: gate decides (nothing was compiled when these rows were written): every kernel answer.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — the built-ins ride the term layer through PL_unify_integer and PL_get_int64_ex only
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _P2B = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_p2bs(x) = lk_sym(_P2B, Symbol(x))


_p2b_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _p2b_enc(t::_P2B, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _p2b_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _p2b_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _p2b_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_p2b_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side: test/core_lang/test_ssu_swipl.jl's driver (consult, then every answer of each t_<id>/1, `enc`oded)
const _P2B_DRIVER = raw"""
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
function _p2b_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _P2B_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end



# the program: helpers that build what a row needs without a library (a counted list; a wide-character atom)
const _P2B_PROGRAM = raw"""
p2_nl(0, []) :- !.
p2_nl(N, [N|T]) :- N1 is N-1, p2_nl(N1, T).
p2_as(0, []) :- !.
p2_as(N, [a|T]) :- N1 is N-1, p2_as(N1, T).
p2_open([], _) :- !.
p2_open([X|Xs], [X|Ys]) :- p2_open(Xs, Ys).
p2_wide(A) :- atom_codes(A, [945, 98, 233]).
p2_ty(X, T) :- ( atom(X) -> T = atom ; string(X) -> T = string ; T = other ).
"""

const _P2B_CASES = [
    ("q01", raw"sub_atom_icasechk('Hello World', S, world), R = S"),
    ("q02", raw"sub_atom_icasechk('Hello World', S, 'World'), R = S"),
    ("q03", raw"sub_atom_icasechk(hello, 0, hel), R = yes"),
    ("q04", raw"sub_atom_icasechk(hello, 1, hel), R = yes"),
    ("q05", raw"sub_atom_icasechk('aXbXc', S, x), R = S"),
    ("q06", raw"sub_atom_icasechk('aXbxc', S, 'X'), R = S"),
    ("q07", raw"sub_atom_icasechk(abc, S, 'B'), R = S"),
    ("q08", raw"sub_atom_icasechk(' ', S, '@'), R = S"),
    ("q09", raw"sub_atom_icasechk(abc, S, ''), R = S"),
    ("q10", raw"sub_atom_icasechk(abc, 5, ''), R = yes"),
    ("q11", raw"sub_atom_icasechk(abc, 3, ''), R = yes"),
    ("q12", raw"sub_atom_icasechk(123456, S, '34'), R = S"),
    ("q13", raw"sub_atom_icasechk([97,66,99], S, bc), R = S"),
    ("q14", raw"p2_wide(W), sub_atom_icasechk(W, S, 'bé'), R = S"),
    (
        "q15",
        raw"atom_codes(H, [913,66,201]), atom_codes(N, [945,98,233]), sub_atom_icasechk(H, S, N), R = S"
    ),
    (
        "q16",
        raw"atom_codes(H, [192,201]), atom_codes(N, [224,233]), sub_atom_icasechk(H, S, N), R = S"
    ),
    (
        "q17",
        raw"atom_codes(H, [224]), atom_codes(N, [0]), sub_atom_icasechk(H, S, N), R = S"
    ),
    ("q18", raw"sub_atom_icasechk(_, S, a), R = S"),
    ("q19", raw"sub_atom_icasechk(abc, S, f(x)), R = S"),
    ("q20", raw"sub_atom_icasechk(abc, a, b), R = yes"),
    ("q21", raw"sub_atom_icasechk(abc, -1, a), R = yes"),
    ("q22", raw"sub_atom_icasechk(abc, S, _), R = S"),
    ("q23", raw"sub_atom_icasechk(abc, 2, c), R = yes"),
    ("q24", raw"sub_atom_icasechk(abcabc, 1, abc), R = yes"),
    ("q25", raw"sub_atom_icasechk(xabab, S, 'AB'), R = S"),
    ("q26", raw"findall(S, sub_atom_icasechk(abab, S, ab), R)"),
    ("q27", raw"string_concat('Hel', lo, S0), sub_atom_icasechk(S0, S, ell), R = S"),
    ("q28", raw"p2_wide(W), sub_atom_icasechk(W, S, b), R = S"),
    ("q29", raw"sub_atom_icasechk(abc, 1.0, b), R = yes"),
    ("q30", raw"sub_atom_icasechk(abc, 100000000000000000000, b), R = yes"),
    ("q31", raw"sub_atom_icasechk(abc, S, abcd), R = S"),
    ("q32", raw"sub_atom_icasechk(f(x), S, a), R = S"),
    ("q33", raw"sub_atom_icasechk(abc, 0, [97,98]), R = yes"),
    (
        "q34",
        raw"atom_codes(H, [945,215]), atom_codes(N, [247]), sub_atom_icasechk(H, S, N), R = S"
    ),
    (
        "q35",
        raw"atom_codes(H, [215]), atom_codes(N, [247]), sub_atom_icasechk(H, S, N), R = S"
    ),
    ("q36", raw"p2_wide(W), sub_atom_icasechk(W, 1, 'bé'), R = yes"),
    ("q37", raw"sub_atom_icasechk([215], S, [247]), R = S"),
    ("q40", raw"'$seek_list'(2, [a,b,c], N, T), R = N-T"),
    ("q41", raw"'$seek_list'(5, [a,b], N, T), R = N-T"),
    ("q42", raw"'$seek_list'(0, [a,b], N, T), R = N-T"),
    ("q43", raw"'$seek_list'(3, [a|X], N, T), ( T == X -> R = N-same ; R = N-other )"),
    ("q44", raw"'$seek_list'(2, foo, N, T), R = N-T"),
    ("q45", raw"'$seek_list'(-1, [a], N, T), R = N-T"),
    ("q46", raw"'$seek_list'(a, [a], N, T), R = N-T"),
    ("q47", raw"'$seek_list'(_, [a], N, T), R = N-T"),
    ("q48", raw"'$seek_list'(3, [a,b,c|d], N, T), R = N-T"),
    ("q49", raw"'$seek_list'(1, [a,b,c], N, T), R = N-T"),
    ("q50", raw"'$seek_list'(1, [a,b,c], 1, T), R = T"),
    ("q51", raw"'$seek_list'(1, [a,b,c], 0, [b,c]), R = yes"),
    ("q52", raw"'$seek_list'(1, L, N, T), ( T == L -> R = N-same ; R = N-other )"),
    ("q53", raw"'$seek_list'(100000000000, [a,b], N, T), R = N-T"),
    ("q54", raw"p2_nl(2500, L), '$seek_list'(2000, L, N, T), length(T, Len), R = N-Len"),
    ("q55", raw"L = [a|L], '$seek_list'(3, L, N, _), R = N"),
    ("q56", raw"'$seek_list'(1.5, [a], N, T), R = N-T"),
    ("q57", raw"'$seek_list'(99999999999999999999, [a], N, T), R = N-T"),
    ("q58", raw"'$seek_list'(1, [a,b], N, a), R = N"),
    ("q59", raw"findall(N-T, '$seek_list'(1, [a,b], N, T), R)")
]

# swipl 10.1.19's answer lines (the pin's swipl), `ok` first, then one line per case
const _P2B_PINNED = [
    "ok",
    "t_q01 c[116,95,113,48,49]/1(i6)",
    "t_q02 c[116,95,113,48,50]/1(i6)",
    "t_q03 c[116,95,113,48,51]/1(a[121,101,115])",
    "t_q04",
    "t_q05 c[116,95,113,48,53]/1(i1)",
    "t_q06 c[116,95,113,48,54]/1(i1)",
    "t_q07",
    "t_q08 c[116,95,113,48,56]/1(i0)",
    "t_q09 c[116,95,113,48,57]/1(i0)",
    "t_q10",
    "t_q11 c[116,95,113,49,49]/1(a[121,101,115])",
    "t_q12 c[116,95,113,49,50]/1(i2)",
    "t_q13 c[116,95,113,49,51]/1(i1)",
    "t_q14 c[116,95,113,49,52]/1(i1)",
    "t_q15 c[116,95,113,49,53]/1(i0)",
    "t_q16 c[116,95,113,49,54]/1(i0)",
    "t_q17 c[116,95,113,49,55]/1(i0)",
    "t_q18 c[116,95,113,49,56]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_q19 c[116,95,113,49,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],c[102]/1(a[120]))))",
    "t_q20 c[116,95,113,50,48]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_q21 c[116,95,113,50,49]/1(c[114,97,105,115,101,100]/1(c[100,111,109,97,105,110,95,101,114,114,111,114]/2(a[110,111,116,95,108,101,115,115,95,116,104,97,110,95,122,101,114,111],i-1)))",
    "t_q22 c[116,95,113,50,50]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_q23 c[116,95,113,50,51]/1(a[121,101,115])",
    "t_q24",
    "t_q25",
    "t_q26 c[116,95,113,50,54]/1(c[91,124,93]/2(i0,nil))",
    "t_q27 c[116,95,113,50,55]/1(i1)",
    "t_q28 c[116,95,113,50,56]/1(i1)",
    "t_q29 c[116,95,113,50,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],f1.0)))",
    "t_q30 c[116,95,113,51,48]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[115,105,122,101,95,116])))",
    "t_q31",
    "t_q32 c[116,95,113,51,50]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[115,116,114,105,110,103],c[102]/1(a[120]))))",
    "t_q33 c[116,95,113,51,51]/1(a[121,101,115])",
    "t_q34",
    "t_q35 c[116,95,113,51,53]/1(i0)",
    "t_q36 c[116,95,113,51,54]/1(a[121,101,115])",
    "t_q37 c[116,95,113,51,55]/1(i0)",
    "t_q40 c[116,95,113,52,48]/1(c[45]/2(i0,c[91,124,93]/2(a[99],nil)))",
    "t_q41 c[116,95,113,52,49]/1(c[45]/2(i3,nil))",
    "t_q42 c[116,95,113,52,50]/1(c[45]/2(i0,c[91,124,93]/2(a[97],c[91,124,93]/2(a[98],nil))))",
    "t_q43 c[116,95,113,52,51]/1(c[45]/2(i2,a[115,97,109,101]))",
    "t_q44 c[116,95,113,52,52]/1(c[45]/2(i2,a[102,111,111]))",
    "t_q45 c[116,95,113,52,53]/1(c[45]/2(i-1,c[91,124,93]/2(a[97],nil)))",
    "t_q46 c[116,95,113,52,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],a[97])))",
    "t_q47 c[116,95,113,52,55]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_q48 c[116,95,113,52,56]/1(c[45]/2(i0,a[100]))",
    "t_q49 c[116,95,113,52,57]/1(c[45]/2(i0,c[91,124,93]/2(a[98],c[91,124,93]/2(a[99],nil))))",
    "t_q50",
    "t_q51 c[116,95,113,53,49]/1(a[121,101,115])",
    "t_q52 c[116,95,113,53,50]/1(c[45]/2(i1,a[115,97,109,101]))",
    "t_q53 c[116,95,113,53,51]/1(c[45]/2(i99999999998,nil))",
    "t_q54 c[116,95,113,53,52]/1(c[45]/2(i0,i500))",
    "t_q55 c[116,95,113,53,53]/1(i0)",
    "t_q56 c[116,95,113,53,54]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[105,110,116,101,103,101,114],f1.5)))",
    "t_q57 c[116,95,113,53,55]/1(c[114,97,105,115,101,100]/1(c[114,101,112,114,101,115,101,110,116,97,116,105,111,110,95,101,114,114,111,114]/1(a[105,110,116,54,52,95,116])))",
    "t_q58",
    "t_q59 c[116,95,113,53,57]/1(c[91,124,93]/2(c[45]/2(i0,c[91,124,93]/2(a[98],nil)),nil))"
]

function _p2b_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _P2B_CASES]
    text =
        _P2B_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _P2B_CASES
        ])
    f = joinpath(mktempdir(), "p2b_text.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _p2b_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_P2B}()
    ld = LK.PL_local_data{_P2B}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _p2b_enc(ball::_P2B)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_p2bs(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_P2B, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _p2b_enc(mk_expr(_P2B, _P2B[_p2bs(name), lk_answers(ld, (a:a)...)...]))
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



@testset "P2b predicates as swipl's (q01-q59)" begin
    f, names = _p2b_file()
    kl, _, _ = _p2b_kernel(f, names)
    @test length(kl) == length(_P2B_PINNED)
    for (k, p) in zip(kl, _P2B_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

@testset "the P2b rows are not vacuous" begin
    # the program loaded; every case has a line; answering rows answer, failing rows have none, raising rows raise
    @test _P2B_PINNED[1] == "ok"
    @test length(_P2B_PINNED) == length(_P2B_CASES) + 1
    @test count(l -> occursin(" i", l) || occursin(" c[45]/2(i", l), _P2B_PINNED) >= 20
    @test any(l -> !occursin(" ", l) && startswith(l, "t_q"), _P2B_PINNED)           # a row without an answer: it failed
    @test count(l -> occursin("[114,97,105,115,101,100]", l), _P2B_PINNED) >= 8   # the error rows (raised)
    for id in ("q01", "q08", "q15", "q17", "q35", "q36", "q37", "q40", "q41", "q54")
        @test any(l -> startswith(l, "t_$id ") && occursin(" ", l), _P2B_PINNED)   # an answer
    end
    for id in ("q04", "q07", "q10", "q24", "q25", "q31", "q34", "q50", "q58")
        @test any(l -> l == "t_$id", _P2B_PINNED)                                   # no answer: it failed
    end
end

@testset "the P2b pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_P2B_PINNED) == length(_P2B_CASES) + 1
    if swipl === nothing
        @info "P2b LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _p2b_file()
        @test _p2b_swipl_lines(f, names) == _P2B_PINNED
    end
end
