# ORIGINAL: the stack limit's error against swipl 10.1.16 (V5d), and what the kernel does where upstream ends the process; upstream's own unit is in test/core_lang/test_resource_error.jl.
# test/core_lang/test_stack_overflow_swipl.jl — V5d's gate (port_inventory row V5; user, 2026-10-07):
#   * three programs that overflow the local stack — through choice points (SWI's own
#     `local_overflow`), a non-tail recursion that builds a term, and one that does not — run through
#     the query API under a limit of 1 000 000 bytes (the kernel's: 125 000 positions of the local
#     stack alone) and consulted by swipl under `stack_limit` 1 000 000: the FORMAL identical,
#     `resource_error(stack)`, and the context compared BY KIND, as decided since Q-B — swipl's a
#     `stack_overflow{…}` dict, the kernel's the stack's name atom `local` (upstream's own fallback),
#     an interim until dicts, so this pin fails when the dict is built;
#   * recovery: after the error the same local data runs the next query, its spare reserved again;
#   * a SECOND overflow before the first is recovered from: upstream ends the process; the kernel
#     throws upstream's message and marks the local data unusable — every later query on it is
#     refused, while a fresh local data on the same database runs (user, 2026-10-07).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _SO = lk_term_type(Union{Int64, Float64, String})
_sos(x) = lk_sym(_SO, Symbol(x))
_sof(f, xs::_SO...) = mk_expr(_SO, _SO[_sos(f), xs...])
_soconj(a::_SO, b::_SO) = _sof(",", a, b)
const _SOX = lk_var(_SO, UInt64(1))

# the clauses, as both systems load them: Prolog text, and the kernel's (head, body)
const _SO_PROGRAM = [
    ("choice.", _sos("choice"), nothing),
    ("choice.", _sos("choice"), nothing),
    ("local_overflow :- choice, local_overflow.", _sos("local_overflow"),
        _soconj(_sos("choice"), _sos("local_overflow"))),
    ("z.", _sos("z"), nothing),
    (
        "r(X) :- r(f(X)), z.",
        _sof("r", _SOX),
        _soconj(_sof("r", _sof("f", _SOX)), _sos("z"))
    ),
    ("s(X) :- s(X), z.", _sof("s", _SOX), _soconj(_sof("s", _SOX), _sos("z")))
]
# the goals: (Prolog text, predicate name, its argument or nothing)
const _SO_GOALS = [
    ("local_overflow", "local_overflow", nothing), ("r(a)", "r", _sos("a")),
    ("s(a)", "s", _sos("a"))
]
const _SO_LIMIT_BYTES = 1_000_000

"A database holding the program, and a local data of its own under the limit."
function _sodb()
    gd = LK.PL_global_data{_SO}()
    ld = LK.PL_local_data{_SO}()
    user = LK.MODULE_user(gd)
    for (_, h, b) in _SO_PROGRAM
        name, ar = kind(h) === SYM ? (h, 0) : (child(h, 1), nchildren(h) - 1)
        pr = LK.lookupProcedure(name, ar, user)
        cl = LK.compileClause(gd, ld, h, b, pr, user)
        LK.assertDefinition!(gd, pr.definition, cl::LK.Clause{_SO}, LK.CL_END)
    end
    ld.stacks_limit = _SO_LIMIT_BYTES ÷ 8
    return gd, ld
end

"Goal `name(arg)` (or `name`) through the query API: `(rc, formal, context)`, nothing for no ball."
function _sorun(gd, ld, name::String, arg)
    ar = arg === nothing ? 0 : 1
    proc = LK.lookupProcedure(_sos(name), ar, LK.MODULE_user(gd))
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, ar)
    ar == 1 && (ld.slots[a + 1] = arg)
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    ex = LK.PL_exception(ld, qid)
    ball = ex == 0 ? nothing : LK.resolve_term(ld, ld.slots[ex + 1])
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    ball === nothing && return (rc, nothing, nothing)
    return (rc, child(ball, 2), child(ball, 3))
end

"A context's kind, as the swipl side writes it: `dict(Tag)`, `atom(Name)` or `other`."
_sokind(c::_SO) = kind(c) === SYM ? "atom($(lk_name(c)))" : "other"

const _SO_SWIPL = Sys.which("swipl")
const _SO_SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

"swipl's outcome of each goal under the limit: `formal | context kind`, one line each."
function _soswipl()::Vector{String}
    prog = IOBuffer()
    println(prog, ":- initialization(main, main).")
    foreach(((t, _, _),) -> println(prog, t), _SO_PROGRAM)
    print(
        prog,
        raw"""
        kind(C, K) :- ( is_dict(C, T) -> format(atom(K), "dict(~w)", [T])
                      ; atom(C) -> format(atom(K), "atom(~w)", [C])
                      ; K = other ).
        r1(G) :- catch(( G -> writeln(no_error) ; writeln(no_error) ), error(F, C),
                       ( kind(C, K), write_canonical(F), write(' | '), writeln(K) )).
        """
    )
    println(
        prog, "main :- set_prolog_flag(stack_limit, $(_SO_LIMIT_BYTES)), ",
        join(("r1($t)" for (t, _, _) in _SO_GOALS), ", "), "."
    )
    out = mktempdir() do d
        f = joinpath(d, "overflow.pl")
        write(f, String(take!(prog)))
        read(`swipl -q $f`, String)
    end
    return split(chomp(out), '\n')
end

@testset "the stack limit's error, against swipl (formal exact, context by kind; Q-B)" begin
    ours = String[]
    for (_, name, arg) in _SO_GOALS
        gd, ld = _sodb()
        rc, formal, ctx = _sorun(gd, ld, name, arg)
        @test rc == LK.PL_S_EXCEPTION
        push!(
            ours,
            "$(lk_name(child(formal, 1)))($(lk_name(child(formal, 2)))) | $(_sokind(ctx))"
        )
    end
    @test all(==("resource_error(stack) | atom(local)"), ours)    # pinned: the interim
    if _SO_SWIPL !== nothing
        theirs = _soswipl()
        @test length(theirs) == length(_SO_GOALS)
        for (o, t) in zip(ours, theirs)
            of, oc = split(o, " | ")
            tf, tc = split(t, " | ")
            @test of == tf                          # the formal, exactly
            # the context by kind (Q-B): the dict, until the kernel builds it
            @test tc == "dict(stack_overflow)" && oc == "atom(local)"
        end
    elseif _SO_SWIPL_REQUIRED
        @test _SO_SWIPL !== nothing                 # LOGICKERNEL_REQUIRE_SWIPL=1
    end
end

@testset "after the error: the next query runs, the spare reserved again" begin
    gd, ld = _sodb()
    rc, _, _ = _sorun(gd, ld, "local_overflow", nothing)
    @test rc == LK.PL_S_EXCEPTION
    @test !ld.outofstack && !ld.exception_processing && ld.exception_term == 0
    @test ld.local_spare == ld.local_def_spare
    @test _sorun(gd, ld, "z", nothing)[1] == LK.PL_S_LAST
    # and overflows again, cleanly — only when recovered: with `exception.processing` stuck, every
    # overflow stretches the limit by 1 MiB more (grow_stacks' error condition), without end
    if !ld.exception_processing
        @test _sorun(gd, ld, "r", _sos("a"))[1] == LK.PL_S_EXCEPTION
    end
end

@testset "a second overflow before recovery: the local data is unusable, later queries refused" begin
    gd, ld = _sodb()
    # the first overflow's flag still set, as when a handler overflows again before the error is
    # recovered from (no catch/3 runs one until V9)
    ld.outofstack = true
    err = try
        _sorun(gd, ld, "local_overflow", nothing)
        nothing
    catch e
        e
    end
    @test err isa ErrorException &&
        occursin("failed to recover from local-overflow", err.msg) &&
        occursin("Sorry, cannot continue", err.msg)
    @test ld.unusable && ld.query == 0              # the query abandoned, the engine marked
    refused = try
        _sorun(gd, ld, "z", nothing)
        nothing
    catch e
        e
    end
    @test refused isa ErrorException && occursin("unusable", refused.msg)
    @test ld.query == 0 && ld.nqueries == 0
    # the database is not broken: a fresh local data runs on it
    ld2 = LK.PL_local_data{_SO}()
    @test _sorun(gd, ld2, "z", nothing)[1] == LK.PL_S_LAST
end
