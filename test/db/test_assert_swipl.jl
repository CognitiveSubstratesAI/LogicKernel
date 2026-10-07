# ORIGINAL: assert/1, assertz/1 and asserta/1 called from Prolog clauses through the VM, against swipl 10.1.16 (V9c); upstream tests them inside swipl (tests/db/test_db.pl, whose units test/db/test_db.jl ports).
# test/db/test_assert_swipl.jl — V9c's gate (port_inventory row V9; user, 2026-10-06, Q8 (a)):
#   * a PROGRAM whose clauses call assert/1, assertz/1 and asserta/1, compiled into the kernel and
#     consulted by swipl; its goals run IN ORDER through the VM (the query API), each outcome — `ok`,
#     or the error term in `write_canonical/1` — identical to swipl's, the context's `system:`
#     stripped until V5c qualifies it (as decided since Q-A);
#   * then the predicates the goals changed: dynamic or not, and each clause's code by instruction
#     NAME (test/compile/test_body_code_swipl.jl compares operands): the FIRST assertz into a fresh
#     predicate compiles as static code, its `X = f(Y)` moved into the head, the second does not, nor
#     does a predicate declared dynamic (`:- dynamic`; the kernel's by `setDynamicDefinition!`, as
#     there is no dynamic/1); asserta's clause comes first;
#   * the same, pinned (swipl 10.1.16's, probed), for the jobs without swipl;
#   * assert/1 through the query API, as assertz/1; from a clause it is not found until V5c (it is
#     not ISO: `user` reaches it through `autoImport`) — the interim, pinned against swipl's `ok`
#     so that it FAILS once V5c lands;
#   * what the kernel refuses (`NotPortedError`): a module-qualified clause (V5c), an SSU clause, a
#     variable goal (V9).
using Test, LogicKernel
# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const LK = LogicKernel

const _A = lk_term_type(Union{Int64, Float64, String})
_as(x) = lk_sym(_A, Symbol(x))
_ag(v) = lk_gnd(_A, v)
_av(k::Integer) = lk_var(_A, UInt64(k))
_af(f, xs::_A...) = mk_expr(_A, _A[_as(f), xs...])
_aconj(gs::_A...) = foldr((a, b) -> _af(",", a, b), gs)
_arule(h::_A, b::_A) = _af(":-", h, b)
_afunctor(t::_A) = kind(t) === SYM ? (t, 0) : (child(t, 1), nchildren(t) - 1)

# ── Prolog text ─────────────────────────────────────────────────────────────────────────────────
"An atom as `write_canonical/1` writes it: a name made only of symbol characters bare (`/`)."
function _aatom_text(t::_A)::String
    n = String(lk_name(t))
    !is_nil(t) && !isempty(n) && all(in("#\$&*+-./:<=>?@^~\\"), n) && return n
    return lk_atom_text(t)
end

"`t` as `write_canonical/1` writes it, each variable by `var(t)`."
function _awrite(t::_A, var)::String
    k = kind(t)
    k === VAR && return var(t)
    k === SYM && return _aatom_text(t)
    if k === GND
        v = lk_value(t)
        v isa String && return "\"$v\""
        return string(v)
    end
    if is_pair(t)
        elems = String[]
        while is_pair(t)
            push!(elems, _awrite(child(t, 2), var))
            t = child(t, 3)
        end
        return "[" * join(elems, ",") * (is_nil(t) ? "" : "|" * _awrite(t, var)) * "]"
    end
    return _awrite(child(t, 1), var) * "(" *
           join((_awrite(child(t, i), var) for i in 2:nchildren(t)), ",") * ")"
end

"Prolog source of `t`; variable `k` is `V<k>`."
_asrc(t::_A)::String = _awrite(t, v -> "V$(var_key(v))")

"`write_canonical/1` of `t`: repeated variables `A, B, …` by first occurrence, singletons `_`."
function _acanonical(t::_A)::String
    counts = Dict{UInt64, Int}()
    order = UInt64[]
    function count!(u)
        if kind(u) === VAR
            c = get(counts, var_key(u), 0)
            c == 0 && push!(order, var_key(u))
            counts[var_key(u)] = c + 1
        elseif kind(u) === EXPR
            foreach(i -> count!(child(u, i)), 1:nchildren(u))
        end
    end
    count!(t)
    names = Dict{UInt64, String}()
    for k in order
        counts[k] > 1 && (names[k] = string('A' + length(names)))
    end
    return _awrite(t, u -> get(names, var_key(u), "_"))
end

# swipl's context `system:assertz/1`, written as the kernel writes it until V5c qualifies contexts
_aunqualify(s::AbstractString) = replace(s, r":\(system,(/\([^()]*,\d+\))\)" => s"\1")

# ── the program ─────────────────────────────────────────────────────────────────────────────────
const _AX, _AY = _av(1), _av(2)
"A compound `f(_, …, _)` of `n` distinct variables (`functor(F, f, n)`)."
_avoids(n::Int) = mk_expr(_A, _A[_as("f"); [_av(100 + i) for i in 1:n]])

"`p(X) :- X = f(Y), q(Y)`: compiled as static code, `X = f(Y)` moves into the head (V9b)."
_amoves(p) = _arule(_af(p, _AX), _aconj(_af("=", _AX, _af("f", _AY)), _af("q", _AY)))

# (head, body): the clauses both systems load; each goal is a clause of this list, run in order
const _A_PROGRAM = Tuple{_A, Union{Nothing, _A}}[
    (_af("st", _ag(1)), nothing),                           # a static predicate with a clause
    (_as("t_und"), _as("und0")),                            # und0/0: a procedure, no clauses
    # the first assertz into a fresh predicate: compiled as static code, X = f(Y) moved
    (_as("a1"), _af("assertz", _amoves("am"))),
    (_as("a2"), _af("assertz", _amoves("am"))),             # the second: am/1 is dynamic now
    (_as("a3"), _af("assertz", _amoves("ad"))),             # ad/1 is declared dynamic
    (_as("a4"), _af("asserta", _af("am", _as("first")))),
    (_as("a5"), _af("assertz", _af("am", _as("last")))),
    (_as("a6"), _af("assertz", _as("und0"))),               # no clauses: it becomes dynamic
    (_as("a7"), _af("assertz", LK.mk_nil(_A))),             # `[]` is a callable atom
    (_as("a8"), _af("assertz", _af("rational", _ag(1)))),   # not ISO: a predicate of `user`
    (_as("e1"), _af("assertz", _arule(_af("st", _AX), _af("=", _AX, _ag(2))))),
    (_as("e2"), _af("asserta", _af("st", _ag(0)))),
    (_as("e4"), _af("assertz", _av(3))),
    (_as("e5"), _af("assertz", _ag(1))),
    (_as("e6"), _af("assertz", _arule(_as("foo"), _ag(1)))),
    (_as("e7"), _af("assertz", _arule(_as("foo"), _av(4)))),
    (_as("e8"), _af("assertz", _arule(_as("foo"), _aconj(_as("a"), _ag(1))))),
    (_as("e9"), _af("assertz", _arule(_as("foo"), LK.mk_nil(_A)))),
    (_as("e10"), _af("assertz", _ag("s"))),
    (_as("e11"), _af("assertz", _ag(1.5))),
    (_as("e12"), _af("assertz", _af("atom", _as("x")))),    # an ISO built-in
    (_as("e14"), _af("asserta", _af("atom", _as("x")))),
    (_as("e15"), _af("assertz", _af("assertz", _as("x")))),
    # test_db.pl's cyclic and arity units, from a clause
    (_as("c1"), _aconj(_af("=", _AX, _af("f", _AX)), _af("assertz", _AX))),
    (_as("c2"), _aconj(_af("=", _AX, _af("f", _AX, _ag(1))), _af("assertz", _AX))),
    (
        _as("c3"),
        _aconj(
            _af("=", _AX, _af("f", _AX)), _af("assertz", _arule(_af("f", _as("a")), _AX)))
    ),
    (_as("m1"), _af("assertz", _avoids(2 * LK.MAXARITY))),
    (_as("m2"), _af("assertz", _arule(_as("p"), _avoids(2 * LK.MAXARITY))))
]
const _A_GOALS = [h for (h, b) in _A_PROGRAM if b !== nothing && h !== _as("t_und")]
# the predicates the goals change, as `name/arity`
const _A_PREDS = [("am", 1), ("ad", 1), ("st", 1), ("und0", 0), ("rational", 1)]

# swipl 10.1.16's outcomes (probed 2026-10-07): what the jobs without swipl compare with
const _A_PINNED_OUTCOMES = [
    "ok", "ok", "ok", "ok", "ok", "ok", "ok", "ok",
    "err error(permission_error(modify,static_procedure,/(st,1)),context(/(assertz,1),_))",
    "err error(permission_error(modify,static_procedure,/(st,1)),context(/(asserta,1),_))",
    "err error(instantiation_error,context(/(assertz,1),_))",
    "err error(type_error(callable,1),context(/(assertz,1),_))",
    "err error(type_error(callable,1),context(/(assertz,1),_))",
    "err error(instantiation_error,context(/(assertz,1),_))",
    "err error(type_error(callable,','(a,1)),context(/(assertz,1),_))",
    "err error(type_error(callable,[]),context(/(assertz,1),_))",
    "err error(type_error(callable,\"s\"),context(/(assertz,1),_))",
    "err error(type_error(callable,1.5),context(/(assertz,1),_))",
    "err error(permission_error(modify,static_procedure,/(atom,1)),context(/(assertz,1),_))",
    "err error(permission_error(modify,static_procedure,/(atom,1)),context(/(asserta,1),_))",
    "err error(permission_error(modify,static_procedure,/(assertz,1)),context(/(assertz,1),_))",
    "err error(representation_error(cyclic_term),context(/(assertz,1),_))",
    "err error(representation_error(cyclic_term),context(/(assertz,1),_))",
    "err error(representation_error(cyclic_term),context(/(assertz,1),_))",
    "err error(representation_error(max_procedure_arity),context(/(assertz,1),'limit is 1024, request = 2048'))",
    "err error(representation_error(max_procedure_arity),context(/(assertz,1),_))"
]

# ── the kernel side ─────────────────────────────────────────────────────────────────────────────
struct _ADB
    gd::LK.PL_global_data{_A}
    ld::LK.PL_local_data{_A}
    user::LK.module_t{_A}
end
function _ADB()
    gd = LK.PL_global_data{_A}()
    return _ADB(gd, LK.PL_local_data{_A}(), LK.MODULE_user(gd))
end
_aproc(db::_ADB, t::_A) = LK.lookupProcedure(_afunctor(t)..., db.user)

"The program compiled into a fresh database, `ad/1` declared dynamic."
function _aload(program)::_ADB
    db = _ADB()
    LK.setDynamicDefinition!(LK.lookupProcedure(_as("ad"), 1, db.user).definition, true)
    for (h, b) in program
        pr = _aproc(db, h)
        cl = LK.compileClause(db.gd, db.ld, h, b, pr, db.user)
        LK.assertDefinition!(db.gd, pr.definition, cl::LK.Clause{_A}, LK.CL_END)
    end
    return db
end

"The outcome of the goal `goal` (an atom) through the query API: `ok`, `failed` or `err E`."
function _arun(db::_ADB, goal::_A)::String
    gd, ld = db.gd, db.ld
    fid = LK.PL_open_foreign_frame(ld)
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, _aproc(db, goal), 0
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    out = if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
        "ok"
    elseif rc == LK.PL_S_EXCEPTION
        "err " * _acanonical(LK.resolve_term(ld, ld.slots[LK.PL_exception(ld, qid) + 1]))
    else
        "failed"
    end
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return out
end

"The instruction names of clause `cl`'s code, as swipl's `clause_vm/2` names them."
function _anames(cl::LK.Clause{_A})::String
    out = String[]
    pc = 1
    while pc <= length(cl.codes)
        info = LK.codeTable(cl.codes[pc])
        push!(out, lowercase(String(info.name)))
        pc += 1 + info.arguments
    end
    return join(out, " ")
end

"Predicate `name/arity` of the `user` module: `dynamic` or `static`, then each clause's code."
function _astate(db::_ADB, name::String, arity::Int)::String
    proc = LK.isCurrentProcedure(sym_key(_as(name)), arity, db.user)
    proc === nothing && return "none"
    def = proc.definition
    out = (def.flags & LK.P_DYNAMIC) != 0 ? "dynamic" : "static"
    c = def.impl_clauses.first_clause
    while c !== nothing
        out *= " | " * _anames(c.clause::LK.Clause{_A})
        c = c.next
    end
    return out
end

# ── the swipl side ──────────────────────────────────────────────────────────────────────────────
const _A_SWIPL_DRIVER = raw"""
:- use_module(library(vm)).
r(G) :- catch(( G -> R = ok ; R = failed ), error(E, C), R = err(error(E, C))),
        ( R = err(Ex) -> write('err '), write_canonical(Ex) ; write(R) ), nl.
show(P) :-
    ( \+ current_predicate(_, user:P) -> write(none)
    ; ( predicate_property(user:P, dynamic) -> write(dynamic) ; write(static) ),
      forall(nth_clause(user:P, _, Ref),
             ( clause_vm(Ref, VM), vmi_labels(VM, L), write(' |'),
               forall(member(vmi(I, _), L), ( functor(I, N, _), write(' '), write(N) )) ))
    ), nl.
"""

const _A_SWIPL = Sys.which("swipl")
const _A_SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

"swipl's outcomes of the goals, then the predicates' states, one line each."
function _aswipl()::Vector{String}
    prog = IOBuffer()
    println(prog, ":- set_prolog_flag(double_quotes, string).")
    println(prog, ":- style_check(-singleton).")
    println(prog, ":- dynamic ad/1.")
    for (h, b) in _A_PROGRAM
        println(prog, b === nothing ? _asrc(h) : _asrc(h) * " :- " * _asrc(b), ".")
    end
    print(prog, _A_SWIPL_DRIVER)
    shows = [
        a > 0 ? "show($n($(join(fill("_", a), ","))))" : "show($n)" for (n, a) in _A_PREDS
    ]
    println(
        prog, "main :- ", join(vcat(["r($(_asrc(g)))" for g in _A_GOALS], shows), ", "), "."
    )
    println(prog, ":- initialization((main, halt)).")
    out = IOBuffer()
    err = IOBuffer()
    proc = mktempdir() do d
        f = joinpath(d, "asserts.pl")
        write(f, String(take!(prog)))
        run(pipeline(ignorestatus(`swipl -q $f`); stdout=out, stderr=err))
    end
    success(proc) || error("swipl failed (exit $(proc.exitcode)): $(String(take!(err)))")
    return [_aunqualify(l) for l in eachline(IOBuffer(take!(out)))]
end

@testset "assert/1, assertz/1, asserta/1 from clauses through the VM (V9c)" begin
    db = _aload(_A_PROGRAM)
    ours = [_arun(db, g) for g in _A_GOALS]
    @test db.ld.exception_term == 0                         # every error was caught at its query
    states = [_astate(db, n, a) for (n, a) in _A_PREDS]
    @testset "pinned: swipl 10.1.16's outcomes" begin
        @test length(ours) == length(_A_PINNED_OUTCOMES)
        bad = [(i, ours[i]) for i in eachindex(ours) if ours[i] != _A_PINNED_OUTCOMES[i]]
        isempty(bad) || foreach(b -> println(stderr, "  differs: ", b), bad)
        @test isempty(bad)
    end
    @testset "pinned: the first assertz moves, the second and a declared dynamic do not" begin
        am, ad, st, und0, rat = states
        cls = split(am, " | ")
        @test cls[1] == "dynamic" && length(cls) == 5       # first, a1's, a2's, last
        @test startswith(cls[2], "h_atom")                  # asserta's: first
        @test startswith(cls[3], "h_functor") && !occursin("b_unify", cls[3])     # moved
        @test startswith(cls[4], "i_enter b_unify")         # not moved
        @test startswith(cls[5], "h_atom")                  # the last assertz's: last
        @test startswith(ad, "dynamic | i_enter b_unify")   # declared dynamic: not moved
        @test st == "static | h_smallint i_exitfact"        # the errors left it as it was
        @test und0 == "dynamic | i_exitfact"
        @test rat == "dynamic | h_smallint i_exitfact"
    end
    if _A_SWIPL !== nothing
        @testset "identical to swipl: every outcome, then each predicate's code" begin
            theirs = _aswipl()
            @test length(theirs) == length(ours) + length(states)
            mine = vcat(ours, states)
            bad = [
                (i, mine[i], theirs[i]) for i in eachindex(mine) if
                i > length(theirs) || mine[i] != theirs[i]
            ]
            isempty(bad) || foreach(b -> println(stderr, "  differs: ", b), bad)
            @test isempty(bad)
        end
    elseif _A_SWIPL_REQUIRED
        @test _A_SWIPL !== nothing                          # LOGICKERNEL_REQUIRE_SWIPL=1
    end
end

@testset "assert/1: as assertz/1 through the query API; from a clause, not found until V5c" begin
    # its procedure in `system`, called directly: it adds at the end, as assertz/1 (pl-comp.c:9198)
    db = _aload([(_as("r"), _af("assertz", _af("as1", _ag(1))))])
    @test _arun(db, _as("r")) == "ok"
    gd, ld = db.gd, db.ld
    proc = LK.isCurrentProcedure(sym_key(_as("assert")), 1, LK.MODULE_system(gd))
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    ld.slots[a + 1] = _af("as1", _ag(2))
    qid = LK.PL_open_query(gd, ld, nothing, LK.PL_Q_EXT_STATUS, proc, a)
    @test LK.PL_next_solution(gd, ld, qid) in (LK.PL_S_TRUE, LK.PL_S_LAST)
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    @test _astate(db, "as1", 1) == "dynamic | h_smallint i_exitfact | h_smallint i_exitfact"
    # THE INTERIM, until V5c: assert/1 is not ISO, so a clause of `user` reaches it through
    # `autoImport` (V5c), not through lookupBodyProcedure's ISO branch. This testset FAILS ONCE V5c
    # LANDS — by design, as the refusals below do: the kernel's answer stops being this error, and
    # stops differing from swipl's `ok`. Then delete it, and give the program a goal calling assert/1.
    db = _aload([(_as("r"), _af("assert", _af("as1", _ag(1))))])
    ours = _arun(db, _as("r"))
    @test ours == "err error(existence_error(procedure,/(assert,1)),context(/(r,0),_))"
    @test _astate(db, "as1", 1) == "none"                 # nothing asserted
    if _A_SWIPL !== nothing
        prog =
            ":- initialization(main, main).\nr :- assert(as1(1)).\n" *
            "main :- catch((r -> write(ok) ; write(failed)), E, print(E)), nl.\n"
        theirs = mktempdir() do d
            f = joinpath(d, "interim.pl")
            write(f, prog)
            strip(read(`swipl -q $f`, String))
        end
        @test theirs == "ok" && ours != theirs              # the divergence V5c removes
    end
end

@testset "PL_error's rewrite_callable, and a head named by no atom (kernel-only)" begin
    # a callable type error strips `M:` off its culprit while `M` is an atom (pl-error.c:72): swipl
    # 10.1.16 reports `assertz((foo :- m:1))` and `(foo :- a:b:1)` as type_error(callable, 1), and
    # `(foo :- a:(b, 1))` as type_error(callable, (b,1)) (probed 2026-10-07; the kernel refuses a
    # `:` goal until V5c, so the culprits are given to PL_error directly). At an `M` that is no atom
    # the culprit becomes `M`, the type `atom` (pl-error.c:83-86: swipl's compiler raises
    # type_error(module, M) before it, so that branch is pinned from the source).
    for (culprit, want) in (
        (_af(":", _as("m"), _ag(1)), _af("type_error", _as("callable"), _ag(1))),
        (_af(":", _as("a"), _af(":", _as("b"), _ag(1))),
            _af("type_error", _as("callable"), _ag(1))),
        (_af(":", _as("a"), _aconj(_as("b"), _ag(1))),
            _af("type_error", _as("callable"), _aconj(_as("b"), _ag(1)))),
        (_af(":", _ag(1), _as("x")), _af("type_error", _as("atom"), _ag(1))),
        (_ag(1), _af("type_error", _as("callable"), _ag(1)))        # nothing to strip
    )
        ld = LK.PL_local_data{_A}()
        t = LK.PL_new_term_refs(ld, 1)
        ld.slots[t + 1] = culprit
        @test !LK.PL_error(ld, LK.ERR_TYPE, _as("callable"), t)
        @test ld.exception_term != 0 &&
            lk_eq(child(ld.slots[ld.exception_term + 1], 2), want)
    end
    # a compound named by a number (`$expr/n`, the kernel's): its name is no callable atom
    db = _aload([(_as("r"), _af("assertz", mk_expr(_A, _A[_ag(1), _as("a")])))])
    @test _arun(db, _as("r")) ==
        "err error(type_error(callable,1(a)),context(/(assertz,1),_))"
end

@testset "what the kernel refuses (NotPortedError)" begin
    # each in a database of its own: a refusal abandons the query (`_abandon_query`)
    for (goal, step) in (
        (_af("assertz", _af(":", _as("m"), _as("foo"))), "V5c"),       # Module:Clause
        (_af("assertz", _arule(_af(":", _as("m"), _as("foo")), _as("true"))), "V5c"),
        (_af("assertz", _af("=>", _as("foo"), _as("true"))), "SSU"),   # an SSU clause
        (_af("assertz", _arule(_af("g", _AX), _AX)), "V9")             # a variable goal
    )
        db = _aload([(_as("r"), goal)])
        err = try
            _arun(db, _as("r"))
            nothing
        catch e
            e
        end
        @test err isa LK.NotPortedError{_A} && err.step == step
        @test db.ld.query == 0                              # the query was abandoned, closed
    end
end
