# ORIGINAL: a differential of TR2's trie enumeration (pl-trie.c: trie_gen/2,3, '$trie_gen_node'/3, '$trie_property'/2) against swipl at the pin
# (10.1.20, 18168e62), the cases of tests/tabling/test_trie_index.pl and test_trie_children.pl that those predicates answer
# allow-new-artifact: TR2 part 2, the enumeration rows of the trie port, after test/core_lang/test_trie_preds_swipl.{jl,pl,out}
# test/core_lang/test_trie_gen_swipl.jl — through a PROGRAM (the pattern of test_trie_preds_swipl.jl): test_trie_gen_swipl.pl holds the rows
# `tN(R)`, the kernel enumerates every solution of every tN/1 and its lines are compared with test_trie_gen_swipl.out (swipl's own, printed by the
# driver below); when `swipl` is on PATH the .out is checked against a live run as well.
# NOT HERE, with the reason: attributed_query, stored_attvar_beside_constants (attributed variables in keys: TR3, a named refusal here);
# stack_shift and garbage_collection_between_answers (the kernel has no collector: the replay path is exercised by ld.trie_gen_force_epoch below);
# generated_shapes (random: the rows are a fixed list); the thread, tabling and compiled (trie_gen_compiled: TR4) tests; '$trie_property'
# invalidated/reevaluated/idg_* (the IDG is TB6's: those names FAIL here, as swipl's do for a trie with no IDG, row t21);
# trie_insert_insert/3, trie_lookup_gen/3, trie_lookup_delete/3 are not defined at the pin (O_NESTED_TRIES is defined nowhere).
# KNOWN DIFFERENCES (named): the node handle of '$trie_gen_node'/3 is an integer here, a pointer in swipl (rows never print one, t17 checks it
# through trie_term/2); wait and deadlock are the constant 0 (single thread, owner TH1).
# The kill rows are `@test`s INSIDE testsets (a top-level failing `@test` gives no verdict in CI mode).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
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

const _TRIE_PL = joinpath(@__DIR__, "test_trie_gen_swipl.pl")
const _TRIE_OUT = joinpath(@__DIR__, "test_trie_gen_swipl.out")

# the rows' names, in the order of a program
_row_names(path::String, re::Regex) =
    unique([String(m[1]) for m in eachmatch(re, read(path, String))])
_trie_names() = _row_names(_TRIE_PL, r"^(t\d+)\(R\) :-"m)

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
function kernel_lines(
    path::String, names::Vector{String}; force_epoch::Bool=false
)::Vector{String}
    gd, ld, st = _tp_load(_TP, path)
    ld.trie_gen_force_epoch = force_epoch
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


# the answers of single rows, built from pieces (equal to the .out's, which is swipl's)
_codes2(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
_ea(s::String) = "a" * _codes2(s)
_ei(n::Integer) = "i$n"
_el(items::Vector{String}) = foldr((x, acc) -> "c[91,124,93]/2($x,$acc)", items; init="nil")
_ec(f::String, args::String...) =
    "c" * _codes2(f) * "/$(length(args))(" * join(args, ",") * ")"
_row(name::String, ans::String) = "$name c$(_codes2(name))/1($ans)"

@testset "TR2: trie_gen/2,3, \$trie_gen_node/3, \$trie_property/2 == swipl's answers (the .out), through a program" begin
    names = _trie_names()
    expected = String.(readlines(_TRIE_OUT))
    @test length(names) >= 30
    @test length(expected) == length(names) + 1 && expected[1] == "ok"
    @test all(i -> startswith(expected[i + 1], names[i] * " "), eachindex(names))
    @test !any(l -> occursin(r"export-error|undefined| exception$", l), expected)
    @test !any(l -> occursin(r"0x[0-9a-f]{6}", l), expected)
    @test count(l -> occursin(_codes("type_error"), l), expected) >= 1
    @test count(l -> occursin(_codes("existence_error"), l), expected) >= 1
    @test any(l -> occursin(_codes("instantiation_error"), l), expected)

    kl = kernel_lines(_TRIE_PL, names)
    @test length(kl) == length(expected)
    for i in eachindex(kl)
        @test (i, kl[i]) == (i, expected[i])
    end

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "TRIE-GEN DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        @test swipl_lines(_TRIE_PL, names) == expected
    end
end

# The kill rows: single rows, each fails on its own when the one thing it names breaks.
@testset "TR2 kill rows: answers of single rows" begin
    names = _trie_names()
    kl = Dict(zip(["ok"; names], kernel_lines(_TRIE_PL, names)))
    @test kl["t2"] == _row("t2", _el([_ei(1), _ei(2)]))                                # a query f(X) prunes the other functor
    @test kl["t3"] == _row("t3", _el([_ec("f", _ei(2))]))                              # a bound Value
    @test kl["t4"] == _row("t4", _ea("no"))                                           # an empty trie has no answer
    @test kl["t11"] ==
        _row("t11", _el([_ec("f", _ei(1)), _ec("f", _ei(2)), _ec("f", _ei(4))]))   # a node deleted between answers
    @test kl["t30"] ==
        _row("t30", _el([_ec("f", _ei(1)), _ec("f", _ei(3)), _ec("f", _ei(4))]))   # the leaf the state is positioned on is deleted
    @test kl["t31"] == _row("t31", _el([_ec("f", _ei(1)), _ec("f", _ei(4))]))     # two leaves ahead deleted
    @test kl["t12"] ==
        _row("t12", _el([_ec("f", _ei(1)), _ec("f", _ei(2)), _ec("f", _ei(9))]))   # a node inserted between answers
    @test kl["t15"] == _row("t15", _ec("-", _ei(500), _ei(250000)))                    # half deleted: 500 answers
    @test kl["t16"] == _row("t16", _ea("none"))                                       # all deleted: none
    @test kl["t18"] == _row("t18", _el([_ec("f", _ea("a")), _ec("f", _ea("c"))]))      # Value bound: the leaves with it
    @test kl["t20"] == _row(
        "t20",
        _ec(
            "-",
            _ec("-", _ec("lookup_count", _ei(3)), _ec("gen_call_count", _ei(0))),
            _ec("gen_call_count", _ei(1))
        )
    )
    @test kl["t21"] == _row("t21", "nil")                                             # idg_*, invalidated, compiled_size, unknown names: fail
    @test kl["t22"] == _row("t22", _ea("no"))
    # a 40-variable prefix: 39 of the 40 answers (the variable mask overflows the scan bit)
    @test kl["t13"] == _row("t13", _el([_ei(i) for i in 2:40]))
end

# The replay path: with the epoch advancing at every call the kept cursors are rebuilt from the root; the answers must not change.
@testset "TR2: restore_cursor! replay (ld.trie_gen_force_epoch) gives the same answers" begin
    names = _trie_names()
    expected = String.(readlines(_TRIE_OUT))
    kl = kernel_lines(_TRIE_PL, names; force_epoch=true)
    @test length(kl) == length(expected)
    for i in eachindex(kl)
        @test (i, kl[i]) == (i, expected[i])
    end
end

# No state leaks: after every row has run to its end or been cut, the pool of trie_gen's states has none live.
@testset "TR2: no trie_gen state stays live" begin
    gd, ld, st = _tp_load(_TP, _TRIE_PL)
    @test st == "ok"
    for name in _trie_names()
        _tp_row(gd, ld, name)
        @test ld.trie_gens.live == 0
    end
end

# White box: a redo takes THIS activation's Key (pl-trie.c trie_gen_raw: `state->query = ...` on every retry). Through the VM the reference
# of a redo is always the first call's (the frame's argument slots), so no answer can tell; the record of the state holds it. swipl cannot
# answer this (the record is the engine's); the row calls trie_gen/2 by hand, the redo with ANOTHER pair of references.
@testset "TR2: a redo of trie_gen/2 keeps the Key reference of its own activation (white box)" begin
    gd, ld, st = _tp_load(_TP, _TRIE_PL)
    @test st == "ok"
    proc = LK.isCurrentProcedure(sym_key(lk_sym(_TP, :wb_trie)), 1, LK.MODULE_user(gd))
    @test proc !== nothing && LK.isDefinedProcedure(gd, proc)
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_TP, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a)
    @test LK.PL_next_solution(gd, ld, qid) in (LK.PL_S_TRUE, LK.PL_S_LAST)   # `a` holds the trie
    b = LK.PL_new_term_refs(ld, 2)
    LK.PL_put_term(ld, b, a)
    LK.PL_put_variable(ld, b + 1)
    ctx = LK.foreign_context{_TP}(LK.FRG_FIRST_CALL, UInt(0), nothing)
    rc = LK.pl_trie_gen2_va(ld, b, 2, ctx)
    @test rc != LK.FTRUE && rc != LK.FFALSE                # a retry word: more leaves follow
    @test enc(lk_answer(ld, b + 1)) == _ec("f", _ei(1))
    k = LK.PL_foreign_context_address(LK.foreign_context{_TP}(LK.FRG_REDO, rc, nothing))
    @test ld.trie_gens.states[k].key == b + 1
    c = LK.PL_new_term_refs(ld, 2)                         # the redo's references: another pair
    LK.PL_put_term(ld, c, a)
    LK.PL_put_variable(ld, c + 1)
    ctx.control = LK.FRG_REDO
    ctx.context = rc
    rc2 = LK.pl_trie_gen2_va(ld, c, 2, ctx)
    @test rc2 != LK.FTRUE && rc2 != LK.FFALSE
    @test enc(lk_answer(ld, c + 1)) == _ec("f", _ei(2))
    @test ld.trie_gens.states[k].key == c + 1              # this activation's reference, not the first call's
    ctx.control = LK.FRG_CUTTED
    ctx.context = rc2
    @test LK.pl_trie_gen2_va(ld, c, 2, ctx) == LK.FTRUE
    @test ld.trie_gens.live == 0
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
end
