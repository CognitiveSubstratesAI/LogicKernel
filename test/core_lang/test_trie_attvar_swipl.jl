# ORIGINAL: a differential of TR3's attributed variables in tries (pl-trie.c O_TRIE_ATTVAR: trie_lookup_abstract and unify_key) against swipl at
# the pin (10.1.20, 18168e62), the rows of tests/tabling/test_trie_attvars.pl (simple, plain, nesting, nesting2, shared, unify_true,
# unify_fail_1/2, unify_shared, unify_multi, unify_beside_constants(_fail), unify_beside_variable) with the setup written by put_attr/freeze
# allow-new-artifact: TR3, the attributed-variable rows of the trie port, after test/core_lang/test_trie_preds_swipl.{jl,pl,out}
# test/core_lang/test_trie_attvar_swipl.jl - through a PROGRAM (the pattern of test_trie_preds_swipl.jl): test_trie_attvar_swipl.pl holds the
# rows, test_trie_attvar_swipl.out swipl's own lines (`ok`, then a row's name and its answer). TWO GROUPS:
#   aN rows (trie_insert/4, trie_term/2, trie_lookup/3: TR1 + TR3): run always, compared with the .out and, when `swipl` is on PATH, live;
#   gN rows (the upstream tests through trie_gen/2): # runs once TR2 is stacked - the testset probes `trie_gen/2` in the kernel and runs only
#        then (the rows are in the .out already, from swipl).
# (upstream also runs every test with trie_gen_compiled/2: compiled tries are TR4's.)
# The kill rows are `@test`s INSIDE testsets (a top-level failing `@test` gives no verdict in CI mode).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE - built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TP = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})

_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
function enc(t::_TP, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _TRIE_PL = joinpath(@__DIR__, "test_trie_attvar_swipl.pl")
const _TRIE_OUT = joinpath(@__DIR__, "test_trie_attvar_swipl.out")

# the rows' names, in the order of a program
_row_names(path::String, re::Regex) =
    unique([String(m[1]) for m in eachmatch(re, read(path, String))])
_a_names() = _row_names(_TRIE_PL, r"^(a\d+)\(R\) :-"m)
_g_names() = _row_names(_TRIE_PL, r"^(g\d+)\(R\) :-"m)

# a fresh kernel with `path` consulted: `(gd, ld, "ok" or "exc <ball>")`
function _tp_load(::Type{T}, path::String) where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    return gd, ld, (st === :ok ? "ok" : "exc " * enc(ball::T))
end

# the driver's line for the row `name`/1 (every answer, at most 100): the name, then each solution
function _tp_row(
    gd::LK.PL_global_data{T}, ld::LK.PL_local_data{T}, name::String
)::String where {T}
    proc = LK.isCurrentProcedure(sym_key(lk_sym(T, Symbol(name))), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$name undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(T, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 100
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(
                sols,
                try
                    enc(
                        mk_expr(T, T[lk_sym(T, Symbol(name)), lk_answers(ld, (a:a)...)...])
                    )
                catch e
                    "export-error " * first(sprint(showerror, e), 80)
                end
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
    return "$name" * join(" " .* sols)
end

# the kernel's lines: `ok` (the program loaded), then each row's name and solutions
function kernel_lines(path::String, names::Vector{String})::Vector{String}
    gd, ld, st = _tp_load(_TP, path)
    return vcat([st], [_tp_row(gd, ld, name) for name in names])
end

# the driver swipl runs to print its lines (the .out is its output; the text of test_sys_swipl.jl's DRIVER)
const DRIVER = raw"""
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
    catch(findnsols(100, G, G, Gs), _, Gs = [exception]),
    forall(member(S, Gs), ( S == exception -> write(' exception') ; write(' '), enc(S) )), nl.
fz_run(File, Ns) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(member(N, Ns), fz_pred(N)).
"""
function swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

_ea(s::String) = "a" * _codes(s)
_ei(n::Integer) = "i$n"
_el(items::Vector{String}) = foldr((x, acc) -> "c[91,124,93]/2($x,$acc)", items; init="nil")
_er(name::String, answer::String) = "$name c" * _codes(name) * "/1($answer)"
_atoms(xs...) = _el([_ea(String(x)) for x in xs])

# does the kernel have trie_gen/2 (TR2)? a probe row, run in a fresh kernel
function _has_trie_gen()::Bool
    f = tempname() * ".pl"
    write(
        f,
        "probe(R) :- catch(( trie_new(T), trie_insert(T, a), trie_gen(T, _), R = yes ), _, R = no).\n"
    )
    gd, ld, st = _tp_load(_TP, f)
    rm(f)
    st == "ok" || return false
    return _tp_row(gd, ld, "probe") == _er("probe", _ea("yes"))
end

function _compare_rows(names::Vector{String}, expected_all::Vector{String})
    expected = [l for l in expected_all if any(n -> startswith(l, n * " "), names)]
    @test length(expected) == length(names) && !isempty(names)
    gd, ld, st = _tp_load(_TP, _TRIE_PL)
    @test st == "ok"
    for (n, e) in zip(names, expected)
        @test (n, _tp_row(gd, ld, n)) == (n, e)
    end
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "ATTVAR-TRIE DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked)."
    else
        @test [
            l for l in swipl_lines(_TRIE_PL, vcat(_a_names(), _g_names())) if
            any(n -> startswith(l, n * " "), names)
        ] == expected
    end
end

@testset "TR3: attributed variables in tries (rows through trie_insert/trie_term/trie_lookup) == swipl's answers" begin
    an = _a_names()
    expected = String.(readlines(_TRIE_OUT))
    @test length(an) == 17 && length(_g_names()) == 16
    @test expected[1] == "ok" && length(expected) == 1 + length(an) + length(_g_names())
    @test !any(l -> occursin(r"export-error|undefined| exception$", l), expected)
    _compare_rows(an, expected)
    # the named answers (swipl's, built from pieces): the attribute comes back, a shared attvar is one, a frozen goal runs on unification
    row(n) = (l=first(filter(l -> startswith(l, n * " "), expected)); l)
    @test row("a1") == _er("a1", _ea("v")) && row("a2") == _er("a2", _ea("v"))
    @test row("a5") == _er("a5", _atoms("same", "v")) &&
        row("a15") == _er("a15", _el([_ei(1), _ei(2), _ea("same"), _ea("other")]))
    @test row("a6") == _er("a6", _ea("yes")) && row("a7") == _er("a7", _ea("no")) &&
        row("a8") == _er("a8", _ea("no"))
    @test row("a9") == _er("a9", _ei(2)) && row("a12") == _er("a12", _ea("yes"))
    @test row("a14") == _er("a14", _atoms("yes", "yes", "no"))
    @test row("a16") == _er("a16", _el([_ea("b"), _el([_ea("b")])]))
end

# runs once TR2 is stacked: the upstream tests through trie_gen/2
@testset "TR3: the upstream tests through trie_gen/2 (runs once TR2 is stacked)" begin
    if _has_trie_gen()
        _compare_rows(_g_names(), String.(readlines(_TRIE_OUT)))
    else
        @info "trie_gen/2 is not in the kernel yet (TR2): the g rows are not run"
        @test true
    end
end
