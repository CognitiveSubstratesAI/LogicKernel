# ORIGINAL: Q2's `$expr/n` functor (DIVERGES) — SWI has no compound whose head is not an atom, so there is no upstream test and no swipl differential.
# test/core_lang/test_expr_functor.jl — compounds whose head is not a symbol (MeTTa's variable and
# compound heads, a grounded head, and `()` with no children) have the functor `$expr/n`, `n` their
# number of children, whose arguments are ALL the children, head included (Q2, user 2026-10-03;
# docs/architecture.md § Q2). What it decides, each pinned here:
#   * the STANDARD ORDER: compounds by arity, then name, then arguments — `$expr/n` has arity n, and
#     it sorts before every symbol-headed compound of the same arity (its name is reserved);
#   * the HEAD CODE: `H_FUNCTOR $expr/n`, an operand of its own for each n — the packed operand
#     names NO literal (index 0), where a symbol-headed compound's names its head symbol (V1 L2);
#   * the INDEX: a `$expr/n` argument unifies with any compound of n children, child by child (a
#     symbol head included), so it is a WILDCARD, keyed as a variable is — and, as a variable clause
#     does in swipl, it keeps the index from going deep where it stands among same-functor clauses
#     (where its arguments would not line up with theirs);
#   * UNIFICATION is unchanged: child by child, `(X a) = f(a)` binds `X = f` — and the VM must match
#     the same way in BOTH directions, pinned below as expected failures until it exists (user,
#     2026-10-04);
#   * `$expr/n` names no literal and every symbol head names its own (V1 L2 — Q2's marking bit is
#     retired, user 2026-10-04), so `argKey` and `indexOfWord` agree on every argument.
include(joinpath(@__DIR__, "..", "db", "index_testlib.jl"))
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
using Random

const _Q = lk_term_type(Union{Int64, Float64, String})
_qs(n) = lk_sym(_Q, Symbol(n))
_qg(v) = lk_gnd(_Q, v)
_qv(k::Int) = lk_var(_Q, UInt64(k))
_qe(xs::_Q...) = mk_expr(_Q, _Q[xs...])
_qf(f, xs::_Q...) = _qe(_qs(f), xs...)
_qcmp(a, b) = compareStandard(a, b)

# The VM's answers for `goal` on predicate `pr` — `nothing` while there is no VM. V4a wires this to
# the query API (`PL_open_query`/`PL_next_solution`, decided) and sets `_QVM_WIRED`; until then a
# `PL_next_solution` in the kernel fails "the VM matches $expr/n both ways".
const _QVM_WIRED = false
_qvm_call(pr, goal)::Union{Nothing, Vector{_Q}} = nothing

"`head` compiled as a clause of a fresh predicate."
function _qclause(head::_Q)::LK.Clause{_Q}
    def = LK.lookupProcedure(_Q, sym_key(child(head, 1)), nchildren(head) - 1, UInt64(0))
    return LK.compileClause(def, head)
end

"The head code of `head` (a clause of a fresh predicate): `(instruction name, operands...)`."
function _qcode(head::_Q)::Vector{Tuple{Symbol, Vararg{UInt64}}}
    cl = _qclause(head)
    codes = cl.codes
    out = Tuple{Symbol, Vararg{UInt64}}[]
    pc = LK.Code(cl, 1)
    while pc.pc <= length(codes)
        op = LK.decode(pc)
        info = LK.codeTable(op)
        push!(out, (info.name, (UInt64(codes[pc.pc + i]) for i in 1:info.arguments)...))
        pc = LK.stepPC(pc)
    end
    return out
end

@testset "\$expr/n" begin
    X, Y = _qv(1), _qv(2)
    a, b = _qs(:a), _qs(:b)

    @testset "standard order: arity, then name, then arguments" begin
        # by ARITY first: `(X a)` is `$expr/2`, after every compound of arity 1
        @test _qcmp(_qf(:f, a), _qe(X, a)) == -1                         # f(a) @< (X a)
        @test _qcmp(_qe(X, a, b), _qf(:f, a, b)) == 1                    # (X a b) @> f(a,b)
        @test _qcmp(_qe(_qg(1), a), _qf(:f, a)) == 1                     # a grounded head too
        @test _qcmp(_qe(_qf(:g, b), a), _qf(:f, a)) == 1                 # and a compound head
        # the same arity: `$expr` before every symbol name — text atoms and the reserved `[]`
        @test _qcmp(_qe(X, a), _qf(:f, a, b)) == -1                      # (X a) @< f(a,b)
        @test _qcmp(_qe(X, a), _qf(Symbol(""), a, b)) == -1              # (X a) @< ''(a,b)
        @test _qcmp(_qe(X, a), _qe(mk_nil(_Q), a, b)) == -1              # (X a) @< [](a,b)
        @test _qcmp(_qe(), _qf(:f)) == -1                                # () @< f()
        @test _qcmp(_qs(:zzz), _qe()) == -1                              # every atom @< ()
        # two `$expr/n`: their children left to right, the head first
        @test _qcmp(_qe(X, a), _qe(_qf(:g, b), a)) == -1                 # var @< compound
        @test _qcmp(_qe(_qg(1), b), _qe(_qg("s"), a)) == -1              # number @< string
        @test _qcmp(_qe(_qf(:g, a), b), _qe(_qf(:g, b), a)) == -1        # g(a) @< g(b)
        @test _qcmp(_qe(X, a), _qe(X, b)) == -1
        # `==/2`: never across a `$expr` and a symbol head, even where they would unify
        @test _qcmp(_qe(X, a), _qf(:f, a)) != 0
        @test compareStandard(_qe(X, a), _qf(:f, a), true) == LK.CMP_NOTEQ
        @test compareStandard(_qe(X, a), _qe(X, a), true) == 0
        # one sorted sequence, against the order by number of children it replaces
        xs = _Q[_qe(X, a, b), _qf(:f, a, b), _qe(X, a), _qf(:f, a), _qf(:g), _qe(), a]
        want = _Q[a, _qe(), _qf(:g), _qf(:f, a), _qe(X, a), _qf(:f, a, b), _qe(X, a, b)]
        @test lk_eq(sort(xs; lt=(p, q) -> _qcmp(p, q) < 0), want)
    end

    @testset "standard order: a total order over mixed heads" begin
        rng = Xoshiro(20261003)
        heads() = (X, Y, a, b, _qs(:f), mk_nil(_Q), _qg(1), _qg(2.5), _qf(:g, a), _qe(X, a))
        function rterm(d)::_Q
            r = rand(rng)
            (d >= 2 || r < 0.35) && return rand(rng, (X, Y, a, b, _qg(1), mk_nil(_Q)))
            n = rand(rng, 0:3)
            n == 0 && return rand(rng) < 0.5 ? _qe() : _qf(:f)
            return _qe(rand(rng, heads()), (rterm(d + 1) for _ in 2:n)...)
        end
        ts = [rterm(0) for _ in 1:36]
        c = [_qcmp(p, q) for p in ts, q in ts]
        @test all(c[i, j] == -c[j, i] for i in eachindex(ts), j in eachindex(ts))
        @test all(
            !(c[i, j] <= 0 && c[j, k] <= 0) || c[i, k] <= 0
            for i in eachindex(ts), j in eachindex(ts), k in eachindex(ts)
        )
        # the generator reached both sides: `$expr` compounds and symbol-headed ones
        @test any(
            t -> kind(t) === EXPR && nchildren(t) >= 1 && kind(child(t, 1)) !== SYM, ts
        )
        @test any(
            t -> kind(t) === EXPR && nchildren(t) >= 2 && kind(child(t, 1)) === SYM, ts
        )
    end

    @testset "head code: H_FUNCTOR \$expr/n, an operand per n" begin
        p(x) = _qf(:p, x)
        fop(code) = first(i for i in code if i[1] in (:H_FUNCTOR, :H_RFUNCTOR))[2]  # the argument's
        e2 = fop(_qcode(p(_qe(X, a))))                   # p((X a))
        e2b = fop(_qcode(p(_qe(_qf(:g, b), a))))         # p(((g b) a)): the same functor
        e3 = fop(_qcode(p(_qe(X, a, b))))                # p((X a b))
        e0 = fop(_qcode(p(_qe())))                       # p(())
        f1 = fop(_qcode(p(_qf(:f, a))))                  # p(f(a)): f/1
        q2 = fop(_qcode(p(_qf(Symbol("\$expr"), X, a)))) # p('$expr'(X, a)): the TEXT atom's
        # `$expr/n` names no literal; its arity is its number of children
        @test LK.functor_literal.((e0, e2, e3)) == (0, 0, 0)
        @test LK.functor_arity.((e0, e2, e3)) == (0, 2, 3)
        @test e2 == e2b
        @test length(Set([e0, e2, e3, f1, q2])) == 5
        # a symbol head names its literal — the TEXT atom '$expr' included, which is not `$expr`
        for (h, op, name, n) in ((p(_qf(:f, a)), f1, :f, 1),
            (p(_qf(Symbol("\$expr"), X, a)), q2, Symbol("\$expr"), 2))
            i = LK.functor_literal(op)
            @test i != 0 && LK.functor_arity(op) == n
            @test lk_eq(_qclause(h).literals[i], _qs(name))
        end
        # the arguments are ALL the children, head included: `(X a)` has two
        @test [i[1] for i in _qcode(p(_qe(X, a)))] ==
            [:H_FUNCTOR, :H_VOID, :H_ATOM, :H_POP, :I_EXITFACT]
    end

    @testset "index: a \$expr/n argument is a WILDCARD" begin
        # p(k1) … p(k40), and p((X a)) first. A call p(k7) is narrowed by the index to k7's bucket
        # (the answer is deterministic, as no clause follows it there) — so the index is in use.
        pr = ix_pred(_Q, :p, 1)
        ix_assertz!(pr, _qf(:p, _qe(X, a)))
        for i in 1:40
            ix_assertz!(pr, _qf(:p, _qs("k$i")))
        end
        @test lk_eq(first.(ix_call(pr, _qf(:p, _qs(:k7)))), _Q[_qf(:p, _qs(:k7))])
        @test last.(ix_call(pr, _qf(:p, _qs(:k7)))) == [true]
        # p(f(a)) unifies with p((X a)), X = f: the index must not drop it
        for g in (_qf(:p, _qf(:f, a)), _qf(:p, _qe(Y, a)), _qf(:p, _qe(_qf(:g, b), a)))
            got, want = first.(ix_call(pr, g)), first.(ix_call_unindexed(pr, g))
            @test !isempty(want)
            @test lk_eq(got, want)
        end
        @test lk_eq(first.(ix_call(pr, _qf(:p, _qf(:f, a)))), _Q[_qf(:p, _qf(:f, a))])
    end

    @testset "index: among same-functor clauses, a \$expr/n clause keeps every answer" begin
        # r(f(x, b1)) … r(f(x, b40)) share the functor f/2 and differ in f's SECOND argument: the
        # index goes deep there, so r(f(x, b33)) is deterministic.
        x = _qs(:x)
        rp = ix_pred(_Q, :r, 1)
        for i in 1:40
            ix_assertz!(rp, _qf(:r, _qf(:f, x, _qs("b$i"))))
        end
        @test last.(ix_call(rp, _qf(:r, _qf(:f, x, _qs(:b33))))) == [true]
        # q: the same clauses and q((X x b5)) among them, which unifies with q(f(x, b5)) child by
        # child. Its own arguments are (X, x, b5) — f's second argument lines up with its `x` — so
        # it must stay a wildcard, as `q(_)` does in swipl (10.1.16, probed: no deep index then).
        qp = ix_pred(_Q, :q, 1)
        for i in 1:40
            ix_assertz!(qp, _qf(:q, _qf(:f, x, _qs("b$i"))))
            i == 20 && ix_assertz!(qp, _qf(:q, _qe(X, x, _qs(:b5))))
        end
        for i in (5, 6, 33)
            g = _qf(:q, _qf(:f, x, _qs("b$i")))
            got, want = first.(ix_call(qp, g)), first.(ix_call_unindexed(qp, g))
            @test lk_eq(got, want)
        end
        @test length(ix_call(qp, _qf(:q, _qf(:f, x, _qs(:b5))))) == 2   # f(x,b5) and (X x b5)
    end

    @testset "unification stays child by child" begin
        ld = LK.PL_local_data{_Q}()
        m = LK.Mark(ld)
        @test LK.pl_unify!(ld, _qe(X, a), _qf(:f, a))                       # (X a) = f(a)
        @test lk_eq(LK.resolve_term(ld, X), _qs(:f))
        @test lk_eq(LK.resolve_term(ld, _qe(X, a)), _qf(:f, a))             # ⇒ then ==
        LK.Undo!(ld, m)
        @test !LK.pl_unify!(ld, _qe(X, a), _qf(:f, a, b))                   # 2 children, 3
        LK.Undo!(ld, m)
        @test LK.pl_unify!(ld, _qe(X, a, b), _qe(_qf(:g, b), Y, b))         # two `$expr/3`
        @test lk_eq(LK.resolve_term(ld, Y), a)
        LK.Undo!(ld, m)
    end

    @testset "variant: \$expr/n against \$expr/n only" begin
        @test LK.is_variant_ptr(_qe(X, a), _qe(Y, a))
        @test !LK.is_variant_ptr(_qe(X, a), _qf(:f, a))
    end

    @testset "\$expr/n names no literal; argKey agrees with indexOfWord" begin
        # V1 L2 retired Q2's marking bit (user, 2026-10-04): what marks `$expr/n` now is literal 0
        # in its packed `H_FUNCTOR` operand, which no symbol-headed compound has. Both sides
        # non-empty: symbol heads, `[]` as a head, and `$expr/n` of several arities.
        sym_heads = (_qf(:f, a), _qf(:g, X, b), _qe(mk_nil(_Q), a), _qf(:z))
        expr_heads = (_qe(X, a), _qe(), _qe(_qg(1), a, b), _qe(_qf(:g, b), a))
        for t in sym_heads
            cl = _qclause(_qf(:p, t))
            op = cl.codes[2]
            @test LK.functor_literal(op) != 0
            @test lk_eq(cl.literals[LK.functor_literal(op)], child(t, 1))
            @test LK.argKey(LK.Code(cl, 1), 0) == LK.indexOfWord(t) != 0
        end
        for t in expr_heads
            cl = _qclause(_qf(:p, t))
            @test LK.decode(LK.Code(cl, 1)) == LK.H_FUNCTOR
            @test LK.functor_literal(cl.codes[2]) == 0
            @test LK.argKey(LK.Code(cl, 1), 0) == LK.indexOfWord(t) == 0   # a wildcard
        end
    end

    # ── what the VM must do: BOTH directions (user, 2026-10-04) ──────────────────────────────────
    # DIVERGES from SWI (written so, not as a `# DIVERGES:` port marker: this file is ORIGINAL and has
    # no `# PORT:` line for one to sit under). In SWI, compounds of different functors never unify,
    # and indexing and H_FUNCTOR rely on it. Here `(X a)` (`$expr/2`) unifies with `f(a)` (`f/1`) child by child, so the VM must
    # match in BOTH directions:
    #   1. a head holding `$expr/n` (`H_FUNCTOR $expr/n`) against ANY compound of n children —
    #      not a functor-equality check;
    #   2. a head `f(…)` (`H_FUNCTOR f/k`) against a `$expr/(k+1)` argument — child by child,
    #      not a failure on the functor.
    # Pinned as EXPECTED FAILURES until the VM exists (V4a's gate turns both into `@test`). One side
    # alone fails `ok1 == ok2`, and a VM that arrives without `_qvm_call` wired to it fails the
    # last test.
    @testset "the VM matches \$expr/n both ways (expected failures until V4)" begin
        p1 = ix_pred(_Q, :vm1, 1)                         # 1: the head holds `$expr/2`
        ix_assertz!(p1, _qf(:vm1, _qe(X, a)))
        g1, want1 = _qf(:vm1, _qf(:f, a)), _Q[_qf(:vm1, _qf(:f, a))]
        p2 = ix_pred(_Q, :vm2, 1)                         # 2: the argument is `$expr/2`
        ix_assertz!(p2, _qf(:vm2, _qf(:f, a)))
        g2, want2 = _qf(:vm2, _qe(Y, a)), _Q[_qf(:vm2, _qf(:f, a))]
        # the oracle: the term-level path (decompileHead!, the kernel's unifier) does both today
        @test lk_eq(first.(ix_call(p1, g1)), want1)
        @test lk_eq(first.(ix_call(p2, g2)), want2)
        vm1, vm2 = _qvm_call(p1, g1), _qvm_call(p2, g2)
        ok1 = vm1 !== nothing && lk_eq(vm1, want1)
        ok2 = vm2 !== nothing && lk_eq(vm2, want2)
        @test_broken ok1                                  # direction 1 — DIVERGES from SWI
        @test_broken ok2                                  # direction 2 — DIVERGES from SWI
        @test ok1 == ok2                                  # never ONE direction only
        @test _QVM_WIRED || !isdefined(LK, :PL_next_solution)
    end
end
