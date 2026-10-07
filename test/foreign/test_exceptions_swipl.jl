# ORIGINAL: V5b's gate — the exception path's entries (an undefined procedure; the exception classes) against libswipl and a live swipl; upstream has no such test.
# test/foreign/test_exceptions_swipl.jl — what raises an exception into the query (port_inventory row
# V5, V5b), against swipl:
#
#   * an UNDEFINED PROCEDURE (`S_UNDEF`, the `unknown` flag's default `error`): the query's return
#     code under each flag combination, the next term reference, the exception pending or not, and
#     the error term — `existence_error(procedure, Name/Arity)` with the CALLER in its context, which
#     the last-call optimisation decides — pinned to libswipl's (probed 2026-10-05 through the C query
#     API, scratchpad v5err/qerr.c over qprog.pl); the system predicate `$c_call_prolog/0` is
#     qualified, `system:'$c_call_prolog'/0`, as the probe's (since V5c, as decided since Q-A);
#   * the `CHP_DEBUG` choice point `S_UNDEF` pushes, read back from its record;
#   * the EXCEPTION CLASSES (`classify_exception`, which decides whether a raise replaces a pending
#     ball): every ordered pair of a set of balls, the more urgent one as swipl's own
#     `'$urgent_exception'/3` picks it — including upstream defect #5 (docs/upstream_reports.md),
#     ported as is: `error(resource_error(stack), _)` ranks as an ordinary error;
#   * `PL_raise_exception`'s rule, from the same live table: a ball raised over a pending one
#     replaces it iff its class is not lower — swipl's `'$urgent_exception'/3` with the pair reversed.
#
# swipl present ⇒ the live differential runs. Absent: an ERROR when LOGICKERNEL_REQUIRE_SWIPL=1,
# otherwise a LOUD note plus an assertion that it was not required — never a silent pass.
using Test, LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "db", "index_testlib.jl"))
const _E = lk_term_type(Union{Int64, Float64, String})
const LKE = LogicKernel
_es(x::Symbol) = lk_sym(_E, x)
_eg(x) = lk_gnd(_E, x)
_ef(f::Symbol, xs::_E...) = mk_expr(_E, _E[_es(f), xs...])
_ev(k::Int) = mk_var(_E, UInt64(k))

# The libswipl probe's program (qprog.pl), `true` (refused in a body until V9) as a fact `z`: `p2`'s
# undefined call is still not the last.
function _edb()
    db = IxDB{_E}()
    user = LKE.MODULE_user(db.gd)
    add!(head, body) = begin
        name, n = kind(head) === SYM ? (head, 0) : (child(head, 1), nchildren(head) - 1)
        pr = LKE.lookupProcedure(name, n, user)
        cl = LKE.compileClause(db.gd, db.ld, head, body, pr, user)
        LKE.assertDefinition!(db.gd, pr.definition, cl, LKE.CL_END)
    end
    X = _ev(1)
    add!(_ef(:p, X), _ef(:foo, X))                                  # p(X) :- foo(X).
    add!(_ef(:p2, X), _ef(Symbol(","), _ef(:foo, X), _es(:z)))      # p2(X) :- foo(X), z.
    add!(_ef(:p3, X), _ef(Symbol(","), _ef(:r, X), _ef(:foo, X)))   # p3(X) :- r(X), foo(X).
    add!(_ef(:r, _eg(1)), nothing)
    add!(_ef(:r, _eg(2)), nothing)
    add!(_es(:z), nothing)
    return db
end

"Run `name/1` on `arg` with `flags`: rc, the next term reference − qid, pending before/after close, the ball."
function _erun(db, name::Symbol, arg::_E, flags::UInt32)
    ld = db.ld
    proc = LKE.lookupProcedure(_es(name), 1, LKE.MODULE_user(db.gd))
    fid = LKE.PL_open_foreign_frame(ld)
    a = LKE.PL_new_term_refs(ld, 1)
    ld.slots[a + 1] = arg
    qid = LKE.PL_open_query(db.gd, ld, nothing, flags, proc, a)
    rc = LKE.PL_next_solution(db.gd, ld, qid)
    t = LKE.PL_new_term_ref(ld)
    LKE.PL_reset_term_refs(ld, t)
    tref = t - qid
    ex = LKE.PL_exception(ld, qid)
    ball = ex == 0 ? nothing : LKE.resolve_term(ld, ld.slots[ex + 1])
    before = ld.exception_term != 0
    after_arg = LKE.resolve_term(ld, ld.slots[a + 1])
    rc2 = rc == LKE.PL_S_EXCEPTION || rc == 0 ? LKE.PL_next_solution(db.gd, ld, qid) : -9
    LKE.PL_close_query(ld, qid)
    after = ld.exception_term != 0
    LKE.PL_close_foreign_frame(ld, fid)
    after && LKE.PL_clear_exception(ld)
    return (; rc, tref, before, after, ball, after_arg, rc2)
end

"The ball's formal and its context's predicate: `(formal, pi)`."
function _eparts(ball::_E)
    formal, ctx = child(ball, 2), child(ball, 3)
    pi = child(ctx, 2)
    return (formal, pi)
end

_eeq(a::_E, b::_E) = LKE.compareStandard(a, b) == 0
_epi(name::Symbol, n::Int) = _ef(:/, _es(name), _eg(n))
_eundef(name::Symbol, n::Int) = _ef(:existence_error, _es(:procedure), _epi(name, n))

const _ECE = LKE.PL_Q_CATCH_EXCEPTION | LKE.PL_Q_EXT_STATUS

@testset "an undefined procedure raises existence_error, its caller as libswipl's" begin
    db = _edb()
    # the caller, as libswipl's qerr.out: `system:'$c_call_prolog'/0` when the undefined call is the
    # query's own or a last call; otherwise the calling clause, a `user` predicate, unqualified
    dc = _ef(:(:), _es(:system), _epi(Symbol("\$c_call_prolog"), 0))
    for (name, arg, caller) in (
        (:foo, _eg(1), dc),                                       # foo/1 itself
        (:p, _eg(1), dc),                                         # p(X) :- foo(X).  (last call)
        (:p2, _eg(1), _epi(:p2, 1)),                              # p2(X) :- foo(X), z.
        (:p3, _ev(9), _epi(:p3, 1))                               # p3(X) :- r(X), foo(X).
    )
        r = _erun(db, name, arg, _ECE)
        @test r.rc == LKE.PL_S_EXCEPTION && r.tref == 46        # rc=-1 tref=46
        formal, pi = _eparts(r.ball)
        @test _eeq(formal, _eundef(:foo, 1))
        @test _eeq(pi, caller)
        @test !r.before && !r.after                             # caught: not pending
        @test r.rc2 == 0                                        # the next solution fails
    end
    r = _erun(db, :p3, _ev(9), _ECE)
    @test kind(r.after_arg) === VAR                             # Undo(QF->choice.mark): X unbound
    # the flags (qerr.out): CATCH alone returns false; PASS keeps it pending before and after close
    r = _erun(db, :foo, _eg(1), LKE.PL_Q_CATCH_EXCEPTION)
    @test r.rc == 0 && r.tref == 46 && r.ball !== nothing
    r = _erun(db, :foo, _eg(1), LKE.PL_Q_PASS_EXCEPTION | LKE.PL_Q_EXT_STATUS)
    @test r.rc == LKE.PL_S_EXCEPTION && r.before && r.after
    # with last_call_optimisation=false the last call keeps its parent: the caller is p/1 (swipl
    # live, `lcooff.pl`: context(p/1, _))
    db.ld.prolog_flag_last_call = false
    r = _erun(db, :p, _eg(1), _ECE)
    @test _eeq(_eparts(r.ball)[2], _epi(:p, 1))
    db.ld.prolog_flag_last_call = true
    # the stacks are as they were, over 10^3 raising queries
    ld = db.ld
    base = (ld.lTop, ld.nframes, ld.nchoices, ld.nfliframes, ld.nqueries, length(ld.trail))
    for _ in 1:1000
        _erun(db, :p3, _ev(9), _ECE)
    end
    @test (
        ld.lTop, ld.nframes, ld.nchoices, ld.nfliframes, ld.nqueries, length(ld.trail)
    ) == base
end

# Nothing reads S_UNDEF's choice point on the no-catcher path (b_throw discards every choice point
# above the query's) and the debugger's retry, its reader upstream, is not ported: so it is read
# back from its record, which stays readable after the drop until a push reuses it (V3). The dead
# records are first marked, so a record an earlier query left cannot pass.
@testset "S_UNDEF pushes upstream's CHP_DEBUG choice point for the undefined call's frame" begin
    db = _edb()
    ld = db.ld
    n0 = ld.nchoices
    for name in (:foo, :p2)                                     # the query's own call; a body call
        for k in (n0 + 1):length(ld.choices)
            ld.choices[k].type = LKE.CHP_JUMP
        end
        r = _erun(db, name, _eg(1), _ECE)
        @test r.rc == LKE.PL_S_EXCEPTION
        deb = [
            k for k in (n0 + 1):length(ld.choices) if ld.choices[k].type == LKE.CHP_DEBUG
        ]
        @test length(deb) == 1
        fr = ld.frames[ld.choices[only(deb)].frame]             # newChoice(CHP_DEBUG, FR)
        @test fr.predicate !== nothing &&
            sym_key(fr.predicate.name) == sym_key(_es(:foo)) &&
            fr.predicate.arity == 1
    end
end

# The balls whose classes are compared: one of each class, and the forms the classes hinge on.
const _EBALLS = (
    ("foo", _es(:foo)), ("f(x)", _ef(:f, _es(:x))),
    ("time_limit_exceeded", _es(:time_limit_exceeded)),
    ("time_limit_exceeded(1)", _ef(:time_limit_exceeded, _eg(1))),
    ("error(type_error(a,b),c)", _ef(:error, _ef(:type_error, _es(:a), _es(:b)), _es(:c))),
    ("error(resource_error,c)", _ef(:error, _es(:resource_error), _es(:c))),
    (
        "error(resource_error(stack),c)",
        _ef(:error, _ef(:resource_error, _es(:stack)), _es(:c))
    ),
    ("unwind(abort)", _ef(:unwind, _es(:abort))),
    ("unwind(halt(0))", _ef(:unwind, _ef(:halt, _eg(0)))),
    ("unwind(thread_exit(x))", _ef(:unwind, _ef(:thread_exit, _es(:x)))),
    ("unwind(x)", _ef(:unwind, _es(:x))),
    # the arity and the atom-or-compound tests each decide one of these
    ("error(x)", _ef(:error, _es(:x))), ("unwind(halt)", _ef(:unwind, _es(:halt))),
    ("time_limit_exceeded(1,2)", _ef(:time_limit_exceeded, _eg(1), _eg(2)))
)

"The kernel's pick of the more urgent of balls `i` and `j`, as `'\$urgent_exception'/3` picks: 1 or 2."
function _eurgent(ld, i::Int, j::Int)::Int
    c1 = LKE.classify_exception_p(ld, _EBALLS[i][2])
    c2 = LKE.classify_exception_p(ld, _EBALLS[j][2])
    return c2 > c1 ? 2 : 1
end

"Raise ball `i`, then ball `j` over it (`PL_raise_exception`): 2 if `j` is pending after, 1 if `i` is."
function _eraise(ld, i::Int, j::Int)::Int
    fid = LKE.PL_open_foreign_frame(ld)
    a = LKE.PL_new_term_refs(ld, 2)
    ld.slots[a + 1] = _EBALLS[i][2]
    ld.slots[a + 2] = _EBALLS[j][2]
    LKE.PL_raise_exception(ld, a)
    LKE.PL_raise_exception(ld, a + 1)
    @assert ld.exception_term == ld.exception_bin
    pending = LKE.resolve_term(ld, ld.slots[ld.exception_bin + 1])
    r = if _eeq(pending, _EBALLS[j][2])
        2
    elseif _eeq(pending, _EBALLS[i][2])
        1
    else
        0
    end
    LKE.PL_clear_exception(ld)
    LKE.PL_close_foreign_frame(ld, fid)
    return r
end

const _ESWIPL = Sys.which("swipl")
const _ESWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

@testset "the exception classes, as written: defect #5 included" begin
    ld = LKE.PL_local_data{_E}()
    cls(i) = LKE.classify_exception_p(ld, _EBALLS[i][2])
    @test cls(5) == LKE.EXCEPT_ERROR && cls(6) == LKE.EXCEPT_RESOURCE
    @test cls(7) == LKE.EXCEPT_ERROR                    # error(resource_error(stack),_) — #5, as is
    @test cls(8) == LKE.EXCEPT_ABORT && cls(9) == LKE.EXCEPT_HALT &&
        cls(11) == LKE.EXCEPT_UNWIND
    @test cls(12) == LKE.EXCEPT_OTHER && cls(13) == LKE.EXCEPT_UNWIND &&
        cls(14) == LKE.EXCEPT_OTHER
    @test LKE.classify_exception_p(ld, _ev(1)) == LKE.EXCEPT_NONE
end

@testset "a raise replaces a pending ball of a lower or equal class only" begin
    ld = LKE.PL_local_data{_E}()
    @test _eraise(ld, 5, 1) == 1                        # error(type_error(a,b),c) kept over foo
    @test _eraise(ld, 1, 5) == 2                        # foo replaced by the error
    @test _eraise(ld, 1, 2) == 2                        # foo, f(x): one class, the new one wins
    @test _eraise(ld, 9, 8) == 1                        # unwind(halt(0)) kept over unwind(abort)
    @test ld.exception_term == 0
end

if _ESWIPL !== nothing
    @testset "the exception classes == live swipl's '\$urgent_exception'/3" begin
        prog = IOBuffer()
        n = length(_EBALLS)
        for i in 1:n, j in 1:n
            i == j && continue
            println(
                prog,
                "u($i, $j) :- '\$urgent_exception'($(_EBALLS[i][1]), $(_EBALLS[j][1]), U), ",
                "( U == $(_EBALLS[j][1]) -> R = 2 ; R = 1 ), format(\"~d ~d ~d~n\", [$i, $j, R])."
            )
        end
        println(prog, ":- initialization((forall(clause(u(I, J), _), u(I, J)), halt)).")
        text = mktempdir() do d
            f = joinpath(d, "urgent.pl")
            write(f, String(take!(prog)))
            read(`swipl -q $f`, String)
        end
        bad = String[]
        urgent = Dict{Tuple{Int, Int}, Int}()
        ld = LKE.PL_local_data{_E}()
        for l in eachline(IOBuffer(text))
            i, j, r = parse.(Int, split(l))
            urgent[(i, j)] = r
            ours = _eurgent(ld, i, j)
            ours == r ||
                push!(bad, "$(_EBALLS[i][1]) vs $(_EBALLS[j][1]): swipl $r, kernel $ours")
        end
        # PL_raise_exception from the same table: `j` raised over a pending `i` replaces it iff
        # class(j) >= class(i), i.e. iff swipl's '$urgent_exception'(j, i, U) keeps `j` (U = 1)
        for i in 1:n, j in 1:n
            i == j && continue
            want = urgent[(j, i)] == 1 ? 2 : 1
            ours = _eraise(ld, i, j)
            ours == want ||
                push!(
                    bad,
                    "raise $(_EBALLS[j][1]) over $(_EBALLS[i][1]): swipl $want, kernel $ours"
                )
        end
        foreach(b -> println(stderr, "  DIVERGES: ", b), bad)
        @test isempty(bad)
        @test length(urgent) == n * (n - 1)
    end
elseif _ESWIPL_REQUIRED
    error(
        "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the exception-class differential would be skipped"
    )
else
    @info "EXCEPTION-CLASS DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
    @testset "exception-class differential skipped only where it is not required" begin
        @test !_ESWIPL_REQUIRED
    end
end
