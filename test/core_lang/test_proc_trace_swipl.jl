# ORIGINAL: a differential of '$cgc_params'/6, '$default_predicate'/2 and copy_predicate_clauses/2 (pl-proc.c) against swipl at the pin, and LK-ONLY testsets of the C API's view of the stack (pl-trace.c); test/core_lang/test_dwim_swipl.jl's harness
# test/core_lang/test_proc_trace_swipl.jl — PROC-TRACE. Part one: `$cgc_params`/6, `$default_predicate`/2 and copy_predicate_clauses/2,
# through a PROGRAM (the pattern of test/core_lang/test_dwim_swipl.jl): test_proc_trace_swipl.pl holds the rows, each a predicate
# `tN(R)`; the kernel consults the program and enumerates every solution of every tN/1, and its lines are compared with
# test_proc_trace_swipl.out — swipl 10.1.20's own (the pin binary, ~/.local/bin/swipl), printed by the driver below (`ok`, then
# one line per row: its name and every solution). When the pin binary is there the .out is checked against a live run as well, so
# it cannot go stale. The rows run once, in order, on the state the earlier rows left (the `$cgc_params` rows put the defaults back).
# Part two (LK-ONLY): PL_get_context, PL_step_context, PL_describe_context and PL_backtrace are C API only (pl-trace.c:1671,
# :1694, :1716-1769, :1439 via :1368-1435), so swipl cannot be queried on them. The testsets look at a stack a choice point keeps
# alive (ctx_a -> ctx_b -> ctx_c, and a foreign frame, in test_proc_trace_swipl.pl) and pin only the SHAPES of the texts,
# `[<level>] name/arity [PC=n in clause k]` and `<foreign>`: the program counter offsets are the kernel's own.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TL = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tls(::Type{T}, x) where {T} = lk_sym(T, Symbol(x))

_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
function enc(t::T, seen::Vector{UInt64}=UInt64[])::String where {T}
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

const _PT_PL = joinpath(@__DIR__, "test_proc_trace_swipl.pl")
const _PT_OUT = joinpath(@__DIR__, "test_proc_trace_swipl.out")
const _PT_SWIPL = joinpath(homedir(), ".local", "bin", "swipl")   # the pin binary

# the rows t0-t8 are `$cgc_params`/6, t9-t15 `$default_predicate`/2, the rest copy_predicate_clauses/2
const _PT_CGC_ROWS = 9
const _PT_DP_ROWS = 7

# the rows' names, in the order of the program
_pt_names() =
    unique([String(m[1]) for m in eachmatch(r"^(t\d+)\(R\) :-"m, read(_PT_PL, String))])

# the kernel's lines: `ok` (the program loaded), then each row's name and solutions
function kernel_lines(
    ::Type{T}, path::String, names::Vector{String}
)::Vector{String} where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * enc(ball::T)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_tls(T, name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        pvm = LK.PutVarMap()
        LK.putSlotValue!(ld, a + 1, mk_var(T, LK.fresh_var_keys!(1)), pvm)
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        notported = false
        while (n += 1) <= 100
            rc = try
                LK.PL_next_solution(gd, ld, qid)
            catch e
                e isa LK.NotPortedError || rethrow()
                notported = true
                break
            end
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    try
                        enc(mk_expr(T, T[_tls(T, name), lk_answers(ld, (a:a)...)...]))
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
        if notported
            push!(out, "$name notported")    # the run's ld is thrown away: the query stays open
            return out
        end
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        push!(out, "$name" * join(" " .* sols))
    end
    return out
end

# the driver swipl runs to print its lines (the .out is its output)
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
        read(pipeline(`$_PT_SWIPL -q $f`; stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# ONE extractor for both sides: how many times a line holds an atom (as `enc` writes it)
_pt_count(lines, word) = sum(l -> length(findall(_codes(word), l)), lines; init=0)

@testset "PROCTRACE-1: \$cgc_params/6, \$default_predicate/2, copy_predicate_clauses/2 == swipl's answers (the .out), through a program" begin
    names = _pt_names()
    expected = String.(readlines(_PT_OUT))
    # not a vacuous agreement: the .out has a line per row, and the rows' own evidence is in it
    @test length(names) == 35 && names == ["t$i" for i in 0:34]
    @test length(expected) == length(names) + 1 && expected[1] == "ok"
    @test all(i -> startswith(expected[i + 1], names[i] * " "), eachindex(names))
    ec = expected[2:(_PT_CGC_ROWS + 1)]
    ed = expected[(_PT_CGC_ROWS + 2):(_PT_CGC_ROWS + _PT_DP_ROWS + 1)]
    ep = expected[(_PT_CGC_ROWS + _PT_DP_ROWS + 2):end]
    @test length(ec) == _PT_CGC_ROWS && length(ed) == _PT_DP_ROWS && length(ep) == 19
    # the $cgc_params rows hold the old values (8, 0.03, 1.0), the set ones (5, 0.5, 2.0), the partial effects, the errors
    @test count(l -> occursin("f0.03", l), ec) == _PT_CGC_ROWS - 2       # every row but t2 (4.0, 5.0) and t5 (0.7)
    @test occursin("i5,f0.5,f2.0", ec[2]) && occursin("i3,f4.0,f5.0", ec[3])
    @test occursin("i4,f0.03,f1.0", ec[5]) && occursin("i4,f0.7,f1.0", ec[6])
    @test _pt_count(ec, "type_error") == 4 && _pt_count(ec, "instantiation_error") == 1
    # the $default_predicate rows: both answers are in them
    @test count(l -> occursin("a[116,114,117,101]", l), ed) == 3 &&
        count(l -> occursin("a[102,97,108,115,101]", l), ed) == 3
    # the copy rows: the answer lists (every row holds a number or an error), the permission errors, the module-sensitive rows
    @test _pt_count(ep, "permission_error") == 3 && _pt_count(ep, "private_procedure") == 1
    @test _pt_count(ep, "static_procedure") == 2 && _pt_count(ep, "neg") == 1
    @test occursin("i3", ep[7]) && occursin("i2", ep[7])           # t22: cpa's call reaches cpx:baz (3), the copy cpb's baz (2)
    @test occursin("i1,i1", ep[18]) && occursin("i2,i2", ep[18])  # t33: the non-last call re-pointed too
    @test occursin("i1", ep[19]) && occursin("i2", ep[19])         # t34: the `@/2` module operand re-pointed

    kl = kernel_lines(_TL, _PT_PL, names)
    @test length(kl) == length(expected)
    # the same extractor over the kernel's lines
    kc = kl[2:min(_PT_CGC_ROWS + 1, end)]
    kd = kl[min(_PT_CGC_ROWS + 2, end + 1):min(_PT_CGC_ROWS + _PT_DP_ROWS + 1, end)]
    kp = kl[min(_PT_CGC_ROWS + _PT_DP_ROWS + 2, end + 1):end]
    @test _pt_count(kc, "type_error") == _pt_count(ec, "type_error") == 4
    @test _pt_count(kd, "true") == _pt_count(ed, "true") && _pt_count(kd, "true") == 3
    @test _pt_count(kp, "permission_error") == _pt_count(ep, "permission_error") == 3
    @test _pt_count(kp, "static_procedure") == _pt_count(ep, "static_procedure") == 2
    for i in eachindex(kl)
        @test (i, kl[i]) == (i, expected[i])
    end

    if get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" || !isfile(_PT_SWIPL)
        @info "PROC-TRACE DIFFERENTIAL NOT RUN LIVE: the pin binary $(_PT_SWIPL) is not here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        @test swipl_lines(_PT_PL, names) == expected                          # the .out is swipl's, still
    end
end

# ── LK-ONLY: the C API's view of the stack ───────────────────────────────────────────────────────────────────────────────
# One query on `name`/1 of the program, run to its FIRST solution (a choice point keeps its frames alive), then `f` looks at the
# engine. LK-ONLY: pl-trace.c's PL_get_context (:1671), PL_step_context (:1694), PL_describe_context (:1716) and PL_backtrace
# (:1439, _PL_backtrace :1368) have no Prolog entry, so there is no swipl answer to compare with.
function _pt_with_stack(f, ::Type{T}, name::String) where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    st, ball = LK.load_file!(gd, ld, _PT_PL)
    st === :ok || error("the program did not load: " * enc(ball::T))
    proc = LK.isCurrentProcedure(sym_key(_tls(T, name)), 1, LK.MODULE_user(gd))
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    pvm = LK.PutVarMap()
    LK.putSlotValue!(ld, a + 1, mk_var(T, LK.fresh_var_keys!(1)), pvm)
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    try
        rc = LK.PL_next_solution(gd, ld, qid)
        return f(gd, ld, a, rc)
    finally
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
    end
end

# the frame records (pool indexes) of the live frames whose predicate is `name`/`arity`
function _pt_frames(ld::LK.PL_local_data{T}, name::String, arity::Int) where {T}
    key = sym_key(_tls(T, name))
    return [
        i for i in eachindex(ld.frames) if LK._onStackLocal(ld, i) &&
        ld.frames[i].predicate !== nothing &&
        ld.frames[i].predicate.functor_name == key && ld.frames[i].predicate.arity == arity
    ]
end

# `[<level>] name/arity rest` -> (level, name, arity, rest), or nothing
function _pt_parse(text::AbstractString)
    m = match(r"^\[(\d+)\] (?:\w+:)?(\w+)/(\d+) (.*)$", text)
    m === nothing && return nothing
    return (parse(Int, m[1]), String(m[2]), parse(Int, m[3]), String(m[4]))
end

# `_PL_backtrace` into a string
function _pt_backtrace(ld, depth::Int, flags::Int)::Vector{String}
    buf = zeros(UInt8, 8192)
    out = LK.Sopen_string(buf, length(buf), "w")
    LK._PL_backtrace(ld, out, depth, flags)
    return String.(split(String(buf[1:(out.bufp - 1)]), '\n'; keepempty=false))
end

@testset "PROCTRACE-2 (LK-ONLY): PL_get_context / PL_step_context / PL_describe_context walk the frames of ctx_a -> ctx_b -> ctx_c" begin
    _pt_with_stack(_TL, "ctx_a") do gd, ld, a, rc
        T = typeof(gd).parameters[1]
        @test rc == LK.PL_S_TRUE                    # a choice point is left: the frames stay
        F = Int(lk_value(lk_answers(ld, (a:a)...)[1]))   # prolog_current_frame/1: ctx_c's frame position
        idxs = [i for i in _pt_frames(ld, "ctx_c", 1) if ld.frames[i].base == F]
        @test length(idxs) == 1
        idx = idxs[1]

        # PL_get_context (pl-trace.c:1671): the engine's own position; always a context
        c0 = LK.PL_get_context(ld, 0)
        @test c0 isa LK.pl_context_t{T} && c0.ld === ld && c0.qf == ld.query

        # PL_describe_context (:1716) and PL_step_context (:1694): ctx_c, ctx_b, ctx_a, then the end
        ctx = LK.pl_context_t{T}(ld, ld.query, idx, nothing)
        texts = String[]
        full, n = LK.PL_describe_context(ctx, 256)
        push!(texts, full)
        @test n == ncodeunits(full) > 0
        while LK.PL_step_context(ctx)
            push!(texts, LK.PL_describe_context(ctx, 256)[1])
            length(texts) < 10 || break
        end
        @test length(texts) == 3
        P = _pt_parse.(texts)
        @test all(p -> p !== nothing, P)
        @test [p[2] for p in P] == ["ctx_c", "ctx_b", "ctx_a"] && all(p -> p[3] == 1, P)
        @test occursin(r"^\[PC=-1 in clause 1\]$", P[1][4])     # no continuation point was given
        @test occursin(r"^\[PC=\d+ in clause 1\]$", P[2][4]) && occursin(r"^\[PC=\d+ in clause 1\]$", P[3][4])
        @test P[1][1] == P[2][1] + 1 && P[2][1] == P[3][1] + 1    # each frame one level deeper than its parent
        @test ctx.fr == 0 && !LK.PL_step_context(ctx)             # the end of the stack
        @test LK.PL_describe_context(ctx, 256) == ("", 0)         # no frame: no text

        # the buffer: the text is cut to len-1 bytes, the count is the whole text's
        cc = LK.pl_context_t{T}(ld, ld.query, idx, nothing)
        short, ns = LK.PL_describe_context(cc, 5)
        @test short == full[1:4] && ns == n && ncodeunits(short) == 4
        @test LK.PL_describe_context(cc, 0) == ("", n)
        # a frame reference that is no frame of the stack
        bad = LK.pl_context_t{T}(ld, 0, length(ld.frames) + 5, nothing)
        @test startswith(LK.PL_describe_context(bad, 256)[1], "<invalid frame reference ")
        @test !LK.PL_step_context(bad)

        # PL_backtrace (:1439, _PL_backtrace :1368-1435): the frames from the engine's frame outwards, one line each
        old = (ld.query, ld.environment_frame)
        ld.query = 0
        ld.environment_frame = idx
        try
            lines = _pt_backtrace(ld, 10, LK.PL_BT_SAFE)
            @test length(lines) == 3
            @test all(l -> startswith(l, "  ["), lines)
            @test [_pt_parse(strip(l))[2] for l in lines] == ["ctx_c", "ctx_b", "ctx_a"]
            @test [_pt_parse(strip(l))[1:3] for l in lines] == [p[1:3] for p in P]   # the same levels and predicates as the walk
            @test _pt_backtrace(ld, 2, LK.PL_BT_SAFE) == lines[1:2]          # depth: the first two
            @test _pt_backtrace(ld, -2, LK.PL_BT_SAFE) == lines[2:3]         # depth < 0: the outermost two
            @test _pt_backtrace(ld, 10, LK.PL_BT_SAFE | LK.PL_BT_USER) == lines   # user predicates are all debug frames
            @test_throws LK.NotPortedError _pt_backtrace(ld, 10, 0)           # the tracer's goal writer is DBG2's
        finally
            ld.query, ld.environment_frame = old
        end
        @test_throws LK.NotPortedError LK.PL_interrupt(ld, 2)                # the interactive handler is DBG2's
    end
end

@testset "PROCTRACE-3 (LK-ONLY): PL_describe_context of a foreign frame (repeat/0 kept by its choice point)" begin
    _pt_with_stack(_TL, "ctx_f") do gd, ld, a, rc
        T = typeof(gd).parameters[1]
        @test rc == LK.PL_S_TRUE
        idxs = _pt_frames(ld, "repeat", 0)
        @test length(idxs) == 1
        ctx = LK.pl_context_t{T}(ld, ld.query, idxs[1], nothing)
        text, n = LK.PL_describe_context(ctx, 256)
        p = _pt_parse(text)
        @test p !== nothing && p[2] == "repeat" && p[3] == 0 && p[4] == "<foreign>"
        @test n == ncodeunits(text)
        # one step up: ctx_f's own frame, a clause frame
        @test LK.PL_step_context(ctx)
        p2 = _pt_parse(LK.PL_describe_context(ctx, 256)[1])
        @test p2 !== nothing && p2[2] == "ctx_f" && occursin(r"^\[PC=\d+ in clause 1\]$", p2[4])
    end
end
