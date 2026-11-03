# ORIGINAL: a LIVE differential of the load-time slice of boot/tabling.pl's `:- table` path (TAB1-min; audit D-0387 item 2,
# swipl-devel 10.1.19, cbf4e1896275) against swipl at the pin. Rows tmt: '$tbl_trienode'/1 and '$tbl_is_trienode'/1
# (pl-tabling.c:6253-6277). Further groups are appended with their commits (tmw: '$c_wrap_predicate'/5, tmc: a clause added after the wrap).
#   * A PROGRAM consulted by the kernel's loader and cases `t_<id>(R)` run in order in one database, each wrapped in
#     `catch(Goal, error(SsuE, _), R = raised(SsuE))`; the driver is test_event_swipl.jl's (`enc`oded answers).
#   * Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, evidence/TAB1MIN/tm_rows.out, two byte-identical runs); with
#     `swipl` on PATH the live answers are compared with the pins too.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer; the gate decides.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — these built-ins ride the term layer through the FLI (unify, get, strip module)
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TM = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tms(x) = lk_sym(_TM, Symbol(x))

_tm_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _tm_enc(t::_TM, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _tm_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _tm_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _tm_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_tm_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _TM_DRIVER = raw"""
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

function _tm_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _TM_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the program: `tm_yn/2` turns a goal into `yes`/`no` (the answers stay atoms: the reserved symbol itself is never encoded).
const _TM_PROGRAM = raw"""
:- dynamic tm_hold/1.
tm_yn(G, R) :- ( call(G) -> R = yes ; R = no ).
"""

# tmt: '$tbl_trienode'/1 and '$tbl_is_trienode'/1.
const _TM_CASES = [
    ("tmt01", raw"'$tbl_trienode'(X), ( atom(X) -> R = atom ; R = notatom )"),
    ("tmt02", raw"'$tbl_trienode'(X), ( atomic(X) -> R = atomic ; R = notatomic )"),
    ("tmt03", raw"'$tbl_trienode'(X), tm_yn('$tbl_is_trienode'(X), R)"),
    ("tmt04", raw"tm_yn('$tbl_is_trienode'(a), R)"),
    ("tmt05", raw"tm_yn('$tbl_is_trienode'(trienode), R)"),
    ("tmt06", raw"tm_yn('$tbl_is_trienode'(_), R)"),
    ("tmt07", raw"tm_yn('$tbl_is_trienode'(f(a)), R)"),
    ("tmt08", raw"tm_yn('$tbl_is_trienode'([]), R)"),
    ("tmt09", raw"tm_yn('$tbl_is_trienode'(1), R)"),
    ("tmt10", raw"'$tbl_trienode'(X), '$tbl_trienode'(Y), ( X == Y -> R = same ; R = diff )"),
    ("tmt11", raw"'$tbl_trienode'(X), ( X == trienode -> R = eqtext ; R = neqtext )"),
    ("tmt12", raw"tm_yn('$tbl_trienode'(a), R)"),
    ("tmt13", raw"tm_yn('$tbl_trienode'(trienode), R)"),
    ("tmt14", raw"'$tbl_trienode'(X), Y = f(X), arg(1, Y, Z), tm_yn('$tbl_is_trienode'(Z), R)"),
    ("tmt15", raw"'$tbl_trienode'(X), compare(O, X, aaa), R = O"),
    ("tmt16", raw"'$tbl_trienode'(X), compare(O, X, []), R = O"),
    ("tmt17", raw"'$tbl_trienode'(X), ( var(X) -> R = var ; R = nonvar )"),
    ("tmt18", raw"'$tbl_trienode'(X), copy_term(X, Y), tm_yn('$tbl_is_trienode'(Y), R)"),
    ("tmt19", raw"findall(X, '$tbl_trienode'(X), L), length(L, R)"),
    ("tmt20", raw"retractall(tm_hold(_)), '$tbl_trienode'(X), assertz(tm_hold(X)), tm_hold(Y), tm_yn('$tbl_is_trienode'(Y), R)"),
    ("tmt21", raw"'$get_predicate_attribute'(system:'$tbl_trienode'(_), foreign, V), R = V"),
    ("tmt22", raw"'$get_predicate_attribute'(system:'$tbl_is_trienode'(_), foreign, V), R = V")
]

# the pins are filled by evidence/TAB1MIN/gen_rows.py --fill from swipl's output
const _TM_PINNED = [
    "ok",
    "t_tmt01 c[116,95,116,109,116,48,49]/1(a[110,111,116,97,116,111,109])",
    "t_tmt02 c[116,95,116,109,116,48,50]/1(a[97,116,111,109,105,99])",
    "t_tmt03 c[116,95,116,109,116,48,51]/1(a[121,101,115])",
    "t_tmt04 c[116,95,116,109,116,48,52]/1(a[110,111])",
    "t_tmt05 c[116,95,116,109,116,48,53]/1(a[110,111])",
    "t_tmt06 c[116,95,116,109,116,48,54]/1(a[110,111])",
    "t_tmt07 c[116,95,116,109,116,48,55]/1(a[110,111])",
    "t_tmt08 c[116,95,116,109,116,48,56]/1(a[110,111])",
    "t_tmt09 c[116,95,116,109,116,48,57]/1(a[110,111])",
    "t_tmt10 c[116,95,116,109,116,49,48]/1(a[115,97,109,101])",
    "t_tmt11 c[116,95,116,109,116,49,49]/1(a[110,101,113,116,101,120,116])",
    "t_tmt12 c[116,95,116,109,116,49,50]/1(a[110,111])",
    "t_tmt13 c[116,95,116,109,116,49,51]/1(a[110,111])",
    "t_tmt14 c[116,95,116,109,116,49,52]/1(a[121,101,115])",
    "t_tmt15 c[116,95,116,109,116,49,53]/1(a[60])",
    "t_tmt16 c[116,95,116,109,116,49,54]/1(a[62])",
    "t_tmt17 c[116,95,116,109,116,49,55]/1(a[110,111,110,118,97,114])",
    "t_tmt18 c[116,95,116,109,116,49,56]/1(a[121,101,115])",
    "t_tmt19 c[116,95,116,109,116,49,57]/1(i1)",
    "t_tmt20 c[116,95,116,109,116,50,48]/1(a[121,101,115])",
    "t_tmt21 c[116,95,116,109,116,50,49]/1(i1)",
    "t_tmt22 c[116,95,116,109,116,50,50]/1(i1)"
]

function _tm_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _TM_CASES]
    text =
        _TM_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _TM_CASES
        ])
    f = joinpath(mktempdir(), "tabling_min.pl")
    write(f, text)
    return f, names
end

"A fresh kernel with the file consulted: `(gd, ld, first line of the driver's output)`."
function _tm_load(path::String)
    gd = LK.PL_global_data{_TM}()
    ld = LK.PL_local_data{_TM}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    return gd, ld, (st === :ok ? "ok" : "exc " * _tm_enc(ball::_TM))
end

"The driver's line for `pred/1` (every answer, at most 50), the functor written as `asname`."
function _tm_ask(gd, ld, pred::String, asname::String=pred)::String
    proc = LK.isCurrentProcedure(sym_key(_tms(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$asname undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_TM, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(
                sols, _tm_enc(mk_expr(_TM, _TM[_tms(asname), lk_answers(ld, (a:a)...)...]))
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
    return asname * join(" " .* sols)
end

"The kernel's lines for `names` after consulting `path`."
function _tm_kernel(path::String, names::Vector{String})
    gd, ld, st = _tm_load(path)
    out = [st]
    for name in names
        push!(out, _tm_ask(gd, ld, name))
    end
    return out, gd, ld
end

@testset "tabling minimum as swipl's (tmt)" begin
    f, names = _tm_file()
    kl, _, _ = _tm_kernel(f, names)
    @test length(kl) == length(_TM_PINNED)
    for (k, p) in zip(kl, _TM_PINNED)
        k == p || println(stderr, "  ours  ", k, "\n  swipl ", p)
        @test k == p
    end
end

@testset "the tabling minimum rows are not vacuous" begin
    @test _TM_PINNED[1] == "ok"
    @test length(_TM_PINNED) == length(_TM_CASES) + 1
    for pre in ("tmt",)
        ids = [id for (id, _) in _TM_CASES if startswith(id, pre)]
        @test !isempty([l for l in _TM_PINNED if any(id -> startswith(l, "t_$id "), ids)])
    end
    line(id) = only(filter(l -> startswith(l, "t_$id "), _TM_PINNED))
    @test line("tmt03") != line("tmt04")          # the node is recognised, other terms are not
    @test line("tmt10") != line("tmt11")          # the node is the same symbol each time, not the text atom
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_TM_PINNED) == length(_TM_CASES) + 1
    if swipl === nothing
        @info "TAB1MIN LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _tm_file()
        @test _tm_swipl_lines(f, names) == _TM_PINNED
    end
end
