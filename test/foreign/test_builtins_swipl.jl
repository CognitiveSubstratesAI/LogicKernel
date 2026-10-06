# ORIGINAL: V5a2's gate — the built-ins through the foreign call path, against a LIVE swipl; upstream has no such test.
# test/foreign/test_builtins_swipl.jl — the built-in interface (decision 5; port_inventory row V5,
# V5a2): the first built-ins registered as upstream registers them and called through the VM's
# foreign instructions.
#
#   * REGISTRATION: each entry of the ported tables is a procedure of the `system` module, with
#     upstream's flags and supervisor — `I_FCALLDETVA f` for a `PRED_DEF` built-in,
#     `I_FCALLDET1 f I_FEXITDET` for the FRG one;
#   * a DIFFERENTIAL of random goals of the first users (`=`, `\=`, `unify_with_occurs_check/2`,
#     `==`, `compare/3`, `?=`, `unifiable/3`, `=@=`), each the query's own predicate, in every
#     `occurs_check` mode: the outcome — `true` with the bindings, `false`, or the error's formal and
#     the predicate in its context — identical to swipl's. swipl QUALIFIES a built-in's context
#     (`system:compare/3`) and the kernel does not: the user's open question Q-A, so the context's
#     predicate is compared without its module, and the qualification is counted;
#   * the same goals from a CLAUSE BODY, for the ISO built-ins (a body reaches a non-ISO one only
#     through module resolution, V5c): a non-last call (`I_CALL`) and a last call (`I_DEPART`);
#   * POSITIONS: `prolog_current_frame/1` and `prolog_current_choice/1` as queries, pinned to
#     libswipl's (probed 2026-10-05, scratchpad v5a2/qposd.c: frame at the handle + 31, choice + 21);
#   * a built-in's foreign frame leaves the stacks as they were, over 10^4 queries.
#
# swipl present ⇒ the differentials run. Absent: an ERROR when LOGICKERNEL_REQUIRE_SWIPL=1, otherwise
# a LOUD note plus an assertion that it was not required — never a silent pass.
using Test, LogicKernel, Random
using LogicKernel:
    PL_global_data, PL_local_data, OCCURS_CHECK_FALSE, OCCURS_CHECK_TRUE,
    OCCURS_CHECK_ERROR

include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _BT = lk_term_type(Union{Int64, Float64, String})
const LKB = LogicKernel
_bs(x::Symbol) = lk_sym(_BT, x)
_bg(x) = lk_gnd(_BT, x)
_bc(f::Symbol, xs::_BT...) = mk_expr(_BT, _BT[_bs(f), xs...])
_bv(k::Int) = mk_var(_BT, UInt64(k))

# The first users, `(name, arity, iso)`, as upstream's tables register them.
const _B_FIRST = (
    (:(=), 2, true), (Symbol("\\="), 2, true), (:unify_with_occurs_check, 2, true),
    (:(==), 2, true), (:compare, 3, true), (Symbol("?="), 2, false), (:unifiable, 3, false),
    (Symbol("=@="), 2, false)
)

"The `system` procedure `name/arity` of `gd`."
_bproc(gd, name::Symbol, arity::Int) =
    LKB.isCurrentProcedure(sym_key(_bs(name)), arity, LKB.MODULE_system(gd))

# ── the canonical text both sides print (write_canonical/1) ──────────────────────────────────────
function _bsrc(t::_BT)::String
    k = kind(t)
    k === VAR && return "V$(var_key(t))"
    k === SYM && return lk_atom_text(t)
    if k === GND
        v = lk_value(t)
        v isa String && return "\"$v\""
        return string(v)
    end
    return _bsrc(child(t, 1)) * "(" *
           join((_bsrc(child(t, i)) for i in 2:nchildren(t)), ",") * ")"
end

"`write_canonical/1` of `t`: repeated variables `A, B, …` by first occurrence, singletons `_`."
function _bcanonical(t::_BT)::String
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
    function wc(u)::String
        kind(u) === VAR && return get(names, var_key(u), "_")
        kind(u) === SYM && return _batom(u)
        kind(u) === EXPR || return _bsrc(u)
        if nchildren(u) == 3 && kind(child(u, 1)) === SYM &&
            lk_name(child(u, 1)) === Symbol("[|]")
            items = String[]                    # a list cell, in list syntax
            while kind(u) === EXPR && nchildren(u) == 3 && kind(child(u, 1)) === SYM &&
                  lk_name(child(u, 1)) === Symbol("[|]")
                push!(items, wc(child(u, 2)))
                u = child(u, 3)
            end
            tail = kind(u) === SYM && lk_atom_text(u) == "[]" ? "" : "|" * wc(u)
            return "[" * join(items, ",") * tail * "]"
        end
        return wc(child(u, 1)) * "(" *
               join((wc(child(u, i)) for i in 2:nchildren(u)), ",") * ")"
    end
    return wc(t)
end

"An atom as `write_canonical/1` writes it: symbol-char atoms and `[]` bare, others as `lk_atom_text`."
function _batom(a::_BT)::String
    t = lk_atom_text(a)
    n = String(lk_name(a))
    !isempty(n) && all(in("+-*/\\^<>=~:.?@#&\$"), n) && return n
    return t
end

# ── random goals ─────────────────────────────────────────────────────────────────────────────────
"A random argument over the variables V1…V3: atomic values of each kind, and small compounds."
function _barg(rng, d::Int)::_BT
    r = rand(rng)
    r < 0.30 && return _bv(rand(rng, 1:3))
    if r < 0.60 || d == 0
        return rand(
            rng, (_bs(:a), _bs(:b), _bg(1), _bg(2), _bg(1.0), _bg("s"), mk_nil(_BT))
        )
    end
    f = rand(rng, ((:f, 1), (:g, 2)))
    return _bc(f[1], (_barg(rng, d - 1) for _ in 1:f[2])...)
end

"A random GROUND argument: as `_barg`, without variables."
function _bground(rng, d::Int)::_BT
    if rand(rng) < 0.5 || d == 0
        return rand(
            rng, (_bs(:a), _bs(:b), _bg(1), _bg(2), _bg(1.0), _bg("s"), mk_nil(_BT))
        )
    end
    f = rand(rng, ((:f, 1), (:g, 2)))
    return _bc(f[1], (_bground(rng, d - 1) for _ in 1:f[2])...)
end

"""
`n` random goals `(name, args)` of the first users; `compare/3`'s order from its whole domain, its
compared terms ground ("variables are ordered by address — not reliable", pl-prims.c).
"""
function _bgoals(rng, n::Int)
    out = Tuple{Symbol, Vector{_BT}}[]
    orders = (
        _bv(3),
        _bs(:<),
        _bs(:(=)),
        _bs(:>),
        _bs(:foo),
        _bg(1),
        _bc(:f, _bs(:x)),
        mk_nil(_BT)
    )
    for _ in 1:n
        name, _, _ = rand(rng, _B_FIRST)
        args = if name === :compare             # ground: swipl orders variables by ADDRESS
            x = _bground(rng, 2)
            _BT[rand(rng, orders), x, rand(rng) < 0.2 ? x : _bground(rng, 2)]
        elseif name === :unifiable
            _BT[_barg(rng, 2), _barg(rng, 2), _bv(4)]
        else
            _BT[_barg(rng, 2), _barg(rng, 2)]
        end
        push!(out, (name, args))
    end
    return out
end

const _BMODES = ((OCCURS_CHECK_FALSE, "false"), (OCCURS_CHECK_TRUE, "true"),
    (OCCURS_CHECK_ERROR, "error"))

# ── the kernel side ──────────────────────────────────────────────────────────────────────────────
"""
The outcome of calling `proc` on `args` as a query: `true(Args)` (the arguments after the call,
canonical), `false`, `cyclic` (a rational tree, which has no interface term), or `error(Formal,PI)` — the
context's predicate, without a module.
"""
function _bcall(gd, ld, proc, args::Vector{_BT})::String
    fid = LKB.PL_open_foreign_frame(ld)
    a = LKB.PL_new_term_refs(ld, length(args))
    for (k, t) in enumerate(args)
        ld.slots[a + k] = t
    end
    qid = LKB.PL_open_query(
        gd, ld, nothing, LKB.PL_Q_CATCH_EXCEPTION | LKB.PL_Q_EXT_STATUS, proc, a
    )
    rc = LKB.PL_next_solution(gd, ld, qid)
    out = if rc == LKB.PL_S_EXCEPTION
        ball = LKB.resolve_term(ld, ld.slots[LKB.PL_exception(ld, qid) + 1])
        formal = child(ball, 2)
        ctx = child(ball, 3)
        pi = kind(ctx) === EXPR ? child(ctx, 2) : _bs(:none)
        "error(" * _bcanonical(_bc(:x, formal, pi))[3:(end - 1)] * ")"
    elseif rc == LKB.PL_S_FALSE
        "false"
    else
        try                                     # a rational tree has no interface term: `cyclic`
            res = _BT[LKB.resolve_term(ld, ld.slots[a + k]) for k in eachindex(args)]
            "true(" * _bcanonical(_bc(:x, res...))[3:(end - 1)] * ")"
        catch e
            e isa ArgumentError || rethrow()
            "cyclic"
        end
    end
    LKB.PL_close_query(ld, qid)
    LKB.PL_close_foreign_frame(ld, fid)
    return out
end

# ── the swipl side ───────────────────────────────────────────────────────────────────────────────
"swipl's outcomes of the goals in `mode`, as `_bcall` prints them; and how many contexts it qualified."
function _bswipl(goals, mode::String)::Tuple{Vector{String}, Int}
    prog = IOBuffer()
    println(prog, ":- style_check(-singleton).")
    println(prog, ":- set_prolog_flag(double_quotes, string).")
    for (i, (name, args)) in enumerate(goals)
        println(
            prog,
            "g($i) :- X = [$(join((_bsrc(a) for a in args), ","))], ",
            "G =.. [$(lk_atom_text(_bs(name)))|X], call_goal(G, X)."
        )
    end
    # allow-docstring-interp: not a docstring — swipl's driver program interpolates the mode and the count
    print(
        prog,
        """
        call_goal(G, X) :-
            set_prolog_flag(occurs_check, $mode),
            catch(( call(G) -> R = t(X) ; R = false ), error(F, C), R = e(F, C)),
            set_prolog_flag(occurs_check, false),
            out(R).
        out(false) :- write(false).
        out(t(X)) :- cyclic_term(X), !, write(cyclic).
        out(t(X)) :- T =.. [x|X], with_output_to(string(S), write_canonical(T)),
            sub_string(S, 2, _, 1, In), format("true(~w)", [In]).
        out(e(F, C)) :-
            ( nonvar(C), C = context(_:P, _) -> Q = 1 ; nonvar(C), C = context(P, _) -> Q = 0
            ; P = none, Q = 0 ),
            T = x(F, P), with_output_to(string(S), write_canonical(T)),
            sub_string(S, 2, _, 1, In), format("error(~w)", [In]),
            ( Q == 1 -> write(' qualified') ; true ).
        run :- forall(between(1, $(length(goals)), I), ( format("~d ", [I]), g(I), nl )).
        :- initialization((run, halt)).
        """
    )
    text = mktempdir() do d
        f = joinpath(d, "builtins.pl")
        write(f, String(take!(prog)))
        read(`swipl -q $f`, String)
    end
    res = fill("", length(goals))
    qualified = 0
    for l in eachline(IOBuffer(text))
        i, r = split(l, ' '; limit=2)
        if endswith(r, " qualified")
            r = r[1:(end - length(" qualified"))]
            qualified += 1
        end
        res[parse(Int, i)] = r
    end
    any(isempty, res) &&
        error("swipl answered $(count(!isempty, res)) of $(length(goals)) goals")
    return res, qualified
end

const _BSWIPL = Sys.which("swipl")
const _BSWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

@testset "registered as upstream registers them" begin
    gd = PL_global_data{_BT}()
    @test isempty(LKB.MODULE_user(gd).procedures)            # built-ins live in `system`
    for (name, arity, iso) in _B_FIRST
        p = _bproc(gd, name, arity)
        @test p !== nothing
        d = p.definition
        need = LKB.P_FOREIGN | LKB.HIDE_CHILDS | LKB.P_LOCKED | LKB.P_VARARG
        @test (d.flags & need) == need && ((d.flags & LKB.P_ISO) != 0) == iso
        @test d.codes == LKB.code[LKB.I_FCALLDETVA, LKB.code(d.impl_foreign_function)]
        @test LKB._FOREIGN_VA[d.impl_foreign_function].predicate_name == string(name)
    end
    pf = _bproc(gd, :prolog_current_frame, 1).definition       # the FRG convention
    @test pf.codes ==
        LKB.code[LKB.I_FCALLDET1, LKB.code(pf.impl_foreign_function), LKB.I_FEXITDET]
    @test (pf.flags & LKB.P_VARARG) == 0 && (pf.flags & LKB.P_FOREIGN) != 0
    pc = _bproc(gd, :prolog_current_choice, 1).definition
    @test pc.codes == LKB.code[LKB.I_FCALLDETVA, LKB.code(pc.impl_foreign_function)]
end

@testset "positions: the position built-ins as queries, pinned to libswipl's" begin
    gd = PL_global_data{_BT}()
    ld = PL_local_data{_BT}()
    for (name, pin) in ((:prolog_current_frame, 31), (:prolog_current_choice, 21))
        fid = LKB.PL_open_foreign_frame(ld)
        a = LKB.PL_new_term_refs(ld, 1)
        qid = LKB.PL_open_query(
            gd, ld, nothing, LKB.PL_Q_NORMAL | LKB.PL_Q_EXT_STATUS, _bproc(gd, name, 1), a
        )
        rc = LKB.PL_next_solution(gd, ld, qid)
        v = LKB.deRef(ld, ld.slots[a + 1])
        @test rc == LKB.PL_S_LAST                               # libswipl: rc=2
        @test kind(v) === GND && lk_value(v) - (a + 1) == pin   # V − qpos (qposd.c)
        LKB.PL_close_query(ld, qid)
        LKB.PL_close_foreign_frame(ld, fid)
    end
end

# No first user passes an UNBOUND culprit to a type or domain error (`compare/3` tests `canBind`
# first), so upstream's rule — an unbound culprit is `instantiation_error` instead (pl-error.c:176-177,
# 265-266), except a type error expecting `variable` — is tested on `PL_error` itself.
@testset "PL_error: an unbound culprit is an instantiation error, as upstream's rule" begin
    function formal_of(f)
        ld = PL_local_data{_BT}()
        t = LKB.PL_new_term_ref(ld)                         # holds a fresh, unbound variable
        @test f(ld, t) == false
        ball = LKB.resolve_term(ld, ld.slots[ld.exception_term + 1])
        return _bcanonical(child(ball, 2))
    end
    @test formal_of((ld, t) -> LKB.PL_error(ld, LKB.ERR_DOMAIN, _bs(:order), t)) ==
        "instantiation_error"
    @test formal_of((ld, t) -> LKB.PL_error(ld, LKB.ERR_TYPE, _bs(:atom), t)) ==
        "instantiation_error"
    @test formal_of((ld, t) -> LKB.PL_type_error(ld, "atom", t)) == "instantiation_error"
    @test formal_of((ld, t) -> LKB.PL_type_error(ld, "variable", t)) ==
        "type_error(variable,_)"
    @test formal_of((ld, t) -> LKB.PL_error(ld, LKB.ERR_TYPE, _bs(:variable), t)) ==
        "type_error(variable,_)"
end

@testset "a built-in's foreign frame leaves the stacks as they were" begin
    gd = PL_global_data{_BT}()
    ld = PL_local_data{_BT}()
    base = (ld.lTop, ld.nframes, ld.nchoices, ld.nfliframes, ld.nqueries, length(ld.trail))
    p = _bproc(gd, :compare, 3)
    for _ in 1:10_000
        _bcall(gd, ld, p, _BT[_bv(1), _bs(:a), _bs(:b)])
        _bcall(gd, ld, p, _BT[_bs(:foo), _bs(:a), _bs(:b)])    # …and when it raises
    end
    @test (
        ld.lTop, ld.nframes, ld.nchoices, ld.nfliframes, ld.nqueries, length(ld.trail)
    ) == base
    @test ld.exception_term == 0
end

if _BSWIPL !== nothing
    @testset "the first users through the query API == live swipl, every occurs_check mode" begin
        goals = _bgoals(Xoshiro(20261006), 600)
        gd = PL_global_data{_BT}()
        ld = PL_local_data{_BT}()
        bad = String[]
        tally = Dict{String, Int}()
        qualified = 0
        for (mode, mname) in _BMODES
            theirs, q = _bswipl(goals, mname)
            qualified += q
            ld.prolog_flag_occurs_check = mode
            for (i, (name, args)) in enumerate(goals)
                ours = _bcall(gd, ld, _bproc(gd, name, length(args)), args)
                k = first(split(ours, '('))
                tally[k] = get(tally, k, 0) + 1
                ours == theirs[i] || push!(
                    bad,
                    "[$mname] $(_bsrc(mk_expr(_BT, _BT[_bs(name); args]))): swipl $(theirs[i]), kernel $ours"
                )
            end
            ld.prolog_flag_occurs_check = OCCURS_CHECK_FALSE
        end
        foreach(b -> println(stderr, "  DIVERGES: ", b), first(bad, 20))
        @test isempty(bad)
        @info "the first users == swipl on $(length(goals)) goals × 3 modes: $(sort(collect(tally))); swipl qualified $qualified contexts (Q-A)"
        @test get(tally, "true", 0) >= 300 && get(tally, "false", 0) >= 300 &&
            get(tally, "error", 0) >= 50
        @test qualified == get(tally, "error", 0)                # every built-in context, today
    end
    @testset "the ISO first users from a clause body (I_CALL, I_DEPART) == the query's outcome" begin
        rng = Xoshiro(20261007)
        db = PL_global_data{_BT}()
        ld = PL_local_data{_BT}()
        user = LKB.MODULE_user(db)
        z = LKB.lookupProcedure(_bs(:z), 0, user)
        LKB.assertDefinition!(
            db, z.definition, LKB.compileClause(db, _bs(:z), nothing, z, user), LKB.CL_END
        )
        bad = String[]
        n = 0
        for (name, arity, iso) in _B_FIRST
            iso || continue
            (name === :(=) || name === :(==)) && continue   # compiled INLINE upstream: V9
            vs = _BT[_bv(10 + k) for k in 1:arity]
            goal = mk_expr(_BT, _BT[_bs(name); vs])
            for (pn, body) in (
                (Symbol("bl_", name), goal),
                (Symbol("bn_", name), _bc(Symbol(","), goal, _bs(:z)))
            )
                p = LKB.lookupProcedure(_bs(pn), arity, user)
                cl = LKB.compileClause(db, mk_expr(_BT, _BT[_bs(pn); vs]), body, p, user)
                LKB.assertDefinition!(db, p.definition, cl, LKB.CL_END)
            end
            for _ in 1:40
                args = if name === :compare
                    _BT[
                        rand(rng, (_bv(3), _bs(:<), _bs(:>), _bs(:foo))),
                        _bground(rng, 2),
                        _bground(rng, 2)
                    ]
                else
                    _BT[_barg(rng, 2), _barg(rng, 2)]
                end
                direct = _bcall(db, ld, _bproc(db, name, arity), args)
                for pn in (Symbol("bl_", name), Symbol("bn_", name))
                    via = _bcall(db, ld, LKB.lookupProcedure(_bs(pn), arity, user), args)
                    # a body call's error names the BUILT-IN in its context, as a direct call does
                    via == direct || push!(
                        bad,
                        "$pn on $(_bcanonical(_bc(:x, args...))): direct $direct, via body $via"
                    )
                    n += 1
                end
            end
        end
        foreach(b -> println(stderr, "  DIVERGES: ", b), first(bad, 20))
        @test isempty(bad)
        @test n == 3 * 40 * 2                                   # \=, unify_with_occurs_check, compare
    end
elseif _BSWIPL_REQUIRED
    error(
        "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the built-ins differential would be skipped"
    )
else
    @info "BUILT-INS DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
    @testset "built-ins differential skipped only where it is not required" begin
        @test !_BSWIPL_REQUIRED
    end
end
