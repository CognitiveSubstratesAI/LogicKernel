# ORIGINAL: live differential of the clause compiler's variable analysis against swipl; upstream has no counterpart (it tests SWI against itself).
# test/compile/test_analyse_variables_swipl.jl — pl-comp.c's variable analysis of a clause with a
# BODY (src/pl-comp.jl `analyse_variables!`, `analyseVariables2!`): which variables are voids — a
# variable met once in each branch of a `;` is met once — the frame slot of every other, and the
# frame size, compared with swipl 10.1.16 on random rule clauses and on pinned ones.
#
# Each side reports, per clause:
#   * the HEAD CODE, up to `i_enter`, written as test_head_code_swipl.jl writes it (code_testlib.jl):
#     a head variable used again in the body is not a void, and its slot is the whole clause's;
#   * the SLOT OF EVERY BODY VARIABLE OCCURRENCE, left to right: `v` for a void, else its frame slot.
#     The kernel's come from its analysis (`ci.vardefs`); swipl's from the body code `clause_vm/2`
#     returns — `b_void`, `b_firstvar`/`b_argfirstvar`/`b_var`/`b_argvar(N)`, `b_var0`/`1`/`2`.
#     swipl compiles a plain goal's arguments and the control constructs used here left to right,
#     and merges no body instruction (pl-comp.c `initVMIMerge`), so its occurrences are the term's,
#     in order. A last call whose arguments can move (pl-comp.c `lco`) is compiled twice: its `L_*`
#     moves (`l_nolco` … `i_lcall`, skipped here), then the plain `B_*` code, which has every
#     occurrence once (probed). An instruction this file does not classify is written `?…` and fails
#     the comparison;
#   * for a FRAMED clause, `Head :- shift(k), Body, zz`, the FRAME SIZE. swipl's is the arity of the
#     `$cont$` frame `shift(k)` captures, minus 3 (pl-cont.c `put_environment`: context, clause and
#     PC, then `clause->variables` slots). Its PROLOG variables are those minus the choice variables
#     `allocChoiceVar` (c:1710) added for each `->`, `*->` and `\+` — each a distinct variable operand
#     of the c_* instructions, numbered from the Prolog variables up, which is checked. The kernel's
#     is `analyse_variables!`'s `nv` (`prolog_vars`; `variables` gains the choice variables when V9
#     compiles control constructs — V2's plain goals allocate none). `shift(k)` comes first, so the frame is captured before any body goal runs
#     (none is defined).
# A BARE clause, `Head :- Body`, has no frame to capture, but its body's top term is the random one
# — a plain goal too, whose direct arguments are numbered above the arity (`analyse_variables`
# passes `argn = arity`), which a framed clause, whose top term is always `,`, cannot show. Goals are
# user predicates and variables only: `=`/2, `==`/2, type tests and arithmetic compile inline
# (O_COMPILE_IS) and are not drawn — so no unification moves into the head either (`head_unify`,
# not ported: V9).
using Random
include(joinpath(@__DIR__, "..", "db", "index_testlib.jl"))

include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "code_testlib.jl"))
const _V = lk_term_type(Union{Int64, Float64})
"The database the clauses of this file are analysed in (its global data)."
const _VGD = LK.PL_global_data{_V}()
_vs(n) = lk_sym(_V, Symbol(n))
_ve(f, xs::AbstractVector) = mk_expr(_V, _V[_vs(f); xs])
_vv(k::Integer) = mk_var(_V, UInt64(k))

# ── the kernel side ──────────────────────────────────────────────────────────────────────────────
"Every variable occurrence of `t`, left to right: `v` for a void, else its frame slot in `ci`."
function _va_occ!(out::Vector{String}, ci, t)::Vector{String}
    if kind(t) === VAR
        vd = get(ci.vardefs, var_key(t), nothing)
        push!(out, vd === nothing ? "v" : string(vd.offset))
    elseif kind(t) === EXPR
        foreach(i -> _va_occ!(out, ci, child(t, i)), 1:nchildren(t))
    end
    return out
end

"A compilation of a clause with head `head`, of its predicate in this file's database."
function _va_ci(head::_V)
    user = LK.MODULE_user(_VGD)
    name, ar = kind(head) === SYM ? (head, 0) : (child(head, 1), nchildren(head) - 1)
    return LK.compileInfo{_V}(ar, user, LK.lookupProcedure(sym_key(name), ar, user))
end

"The kernel's head code, body slots and frame size for the clause `head :- body`."
function _va_kernel(head::_V, body::_V)::Tuple{Vector{String}, Vector{String}, Int}
    ci = _va_ci(head)
    nv = LK._compile_clause_head!(_VGD, ci, head, body)
    return (_hcode_of(ci.codes, ci.literals), _va_occ!(String[], ci, body), nv)
end

"The clause `head :- shift(k), body, zz` — the frame-capturing first goal and the argumentless last."
_va_body(b::_V)::_V = _ve(",", [_ve("shift", [_vs("k")]), _ve(",", [b, _vs("zz")])])

# ── random rule clauses ──────────────────────────────────────────────────────────────────────────
mutable struct _VaGen
    rng::Xoshiro
    next::UInt64        # the last variable key handed out
end
_vafresh!(g::_VaGen)::_V = (g.next += 1; _vv(g.next))

"A goal argument: mostly a pooled variable; a fresh one, atoms, small integers, compounds, list cells, and control functors as DATA (their arguments are not control)."
function _vaarg(g::_VaGen, pool::Vector{_V}, depth::Int)::_V
    r = rand(g.rng)
    r < 0.40 && return rand(g.rng, pool)
    r < 0.55 && return _vafresh!(g)
    r < 0.65 && return rand(g.rng) < 0.3 ? mk_nil(_V) : _vs(rand(g.rng, ("a", "b")))
    r < 0.70 && return lk_gnd(_V, rand(g.rng, 0:3))
    if depth < 2
        sub() = _vaarg(g, pool, depth + 1)
        r < 0.85 && return _ve(rand(g.rng, ("f", "g")), [sub() for _ in 1:rand(g.rng, 1:3)])
        r < 0.92 && return _ve("[|]", [sub(), sub()])
        rand(g.rng) < 0.25 && return _ve("\\+", [sub()])
        return _ve(rand(g.rng, (";", ",", "->")), [sub(), sub()])
    end
    return _vs("z")
end

"A body: plain goals (arity 0–3) and variables under `,`, `;`, `->`, `*->` (with and without an else) and `\\+`."
function _vagoal(g::_VaGen, pool::Vector{_V}, depth::Int)::_V
    r = rand(g.rng)
    if depth >= 3 || r < 0.36
        if rand(g.rng) < 0.06                                     # a variable goal, call/1 —
            v = rand(g.rng, pool)                                 # never a void, which swipl
            return _ve(",", [v, _ve("gv", [v])])                  # refuses (c:3472, V2)
        end
        n = rand(g.rng, 0:3)
        n == 0 && return _vs("g0")
        return _ve("g$n", [_vaarg(g, pool, 0) for _ in 1:n])
    end
    sub() = _vagoal(g, pool, depth + 1)
    r < 0.48 && return _ve(",", [sub(), sub()])
    r < 0.62 && return _ve(";", [sub(), sub()])
    r < 0.72 && return _ve(";", [_ve("->", [sub(), sub()]), sub()])
    r < 0.78 && return _ve("->", [sub(), sub()])
    r < 0.84 && return _ve(";", [_ve("*->", [sub(), sub()]), sub()])
    r < 0.88 && return _ve("*->", [sub(), sub()])
    return _ve("\\+", [sub()])
end

"Random clause `k`: a head of arity 0–4 over a pool of 4 variables shared with the body, `framed` or bare."
function _vaclause(g::_VaGen, k::Int, framed::Bool)::Tuple{_V, _V, Bool}
    pool = _V[_vafresh!(g) for _ in 1:4]
    n = rand(g.rng, 0:4)
    head = n == 0 ? _vs("va$k") : _ve("va$k", [_vaarg(g, pool, 1) for _ in 1:n])
    b = _vagoal(g, pool, 0)
    return (head, framed ? _va_body(b) : b, framed)
end

# ── the swipl side ───────────────────────────────────────────────────────────────────────────────
# Each `va_case(Clause, Framed)` is asserted, its code read back as terms by `clause_vm/2`, the head
# part written by `hc_render` (code_testlib.jl) and the body part classified by `va_instr`; then a
# framed clause's head is called under `reset/3`, and the frame `shift(k)` captures gives its size.
const _VA_SWIPL = raw"""
:- use_module(library(vm)).
va_show(Cl, Framed) :-
    assertz(Cl, Ref), clause_vm(Ref, VM),
    va_split(VM, Head, Body),
    forall(member(I, Head), ( hc_render(I, Out), writeln(Out) )),
    va_body(Body, S, C, V),
    va_list('@@slots', S), sort(C, Cs), va_list('@@choice', Cs),
    sort(V, Vs), va_list('@@cvar', Vs),
    (   Framed == true
    ->  Cl = (H :- _), functor(H, N, A), functor(G, N, A),
        reset(G, k, Cont), Cont = call_continuation([F|_]), functor(F, _, FA), FS is FA - 3,
        format("@@frame ~d~n", [FS])
    ;   writeln('@@frame none')
    ).
va_list(Tag, L) :- atomic_list_concat(L, ',', A), format("~w ~w~n", [Tag, A]).
va_split([vmi(i_enter,_)|T], [i_enter], T) :- !.
va_split([vmi(I,_)|T], [I|H], B) :- va_split(T, H, B).
va_body([], [], [], []).
va_body([vmi(I,_)|T], S, C, V) :-
    va_instr(I, S0, C0, V0), va_body(T, S1, C1, V1),
    append(S0, S1, S), append(C0, C1, C), append(V0, V1, V).
va_instr(b_void, [v], [], []) :- !.
va_instr(b_var0, [0], [], []) :- !.
va_instr(b_var1, [1], [], []) :- !.
va_instr(b_var2, [2], [], []) :- !.
va_instr(I, [N], [], []) :-
    I =.. [Op, N], memberchk(Op, [b_firstvar, b_argfirstvar, b_var, b_argvar]), !.
va_instr(c_var(N), [], [], [N]) :- !.
va_instr(c_var_n(N, K), [], [], Vs) :- !, M is N + K - 1, numlist(N, M, Vs).
va_instr(I, [], [N], []) :-
    I =.. [Op, N|_],
    memberchk(Op, [c_not, c_ifthenelse, c_ifthen, c_softif, c_softifthen, c_cut, c_softcut]), !.
va_instr(I, [], [], []) :-                      % a last call's L_* moves: its B_* code follows
    functor(I, Op, _), sub_atom(Op, 0, _, _, l_), !.
va_instr(I, [], [], []) :-
    functor(I, Op, _),
    memberchk(Op, [c_or, c_jmp, c_fail, c_scut, c_end, i_call, i_depart, i_lcall, i_call1,
                   i_usercall0, i_exit, b_atom, b_smallint, b_nil, b_functor, b_rfunctor,
                   b_list, b_rlist, b_pop]), !.
va_instr(I, [Q], [], []) :- format(atom(Q), "?~q", [I]).
main :-
    forall(va_case(Cl, Framed),
           (   va_show(Cl, Framed) -> writeln('@@end')
           ;   writeln('@@failed'), writeln('@@end')
           )).
"""

"What swipl reports for one clause: head code, body slots, choice and `c_var` slots, frame size (-2: not framed)."
struct _VaSwipl
    head::Vector{String}
    slots::Vector{String}
    choice::Vector{Int}
    cvar::Vector{Int}
    frame::Int
end

_va_ints(s::AbstractString)::Vector{Int} = isempty(s) ? Int[] : parse.(Int, split(s, ","))

"swipl's report for each `(text, framed)`, in order (fewer when one failed)."
function _va_swipl(cases::Vector{Tuple{String, Bool}})::Vector{_VaSwipl}
    mktempdir() do d
        f = joinpath(d, "va.pl")
        write(
            f,
            ":- initialization(main, main).\n" * _HSWIPL_OPS * _VA_SWIPL *
            join(["va_case($t, $fr).\n" for (t, fr) in cases])
        )
        ef = joinpath(d, "va.err")
        proc = run(
            pipeline(ignorestatus(`swipl -q $f`); stdout=joinpath(d, "va.out"), stderr=ef)
        )
        if !success(proc)
            println(stderr, "  swipl exited $(proc.exitcode); its stderr ends:")
            foreach(l -> println(stderr, "    ", l), last(readlines(ef), 20))
        end
        out = split(read(joinpath(d, "va.out"), String), '\n')
        res = _VaSwipl[]
        head, slots, choice, cvar, frame = String[], String[], Int[], Int[], -1
        for l in out
            if l == "@@end"
                frame != -1 && push!(res, _VaSwipl(head, slots, choice, cvar, frame))
                head, slots, choice, cvar, frame = String[], String[], Int[], Int[], -1
            elseif startswith(l, "@@slots")
                r = strip(l[8:end])
                slots = isempty(r) ? String[] : String.(split(r, ","))
            elseif startswith(l, "@@choice")
                choice = _va_ints(strip(l[9:end]))
            elseif startswith(l, "@@cvar")
                cvar = _va_ints(strip(l[7:end]))
            elseif l == "@@frame none"
                frame = -2
            elseif startswith(l, "@@frame")
                frame = parse(Int, strip(l[8:end]))
            elseif l == "@@failed"
                frame = -1
            elseif !isempty(l)
                push!(head, _hswipl_floats(l))
            end
        end
        return res
    end
end

"A clause as Prolog text: shared variables `V<key>`, a variable met once `_`."
function _va_text(head::_V, body::_V)::String
    cl = _ve(":-", [head, body])
    return ix_text(cl, ix_var_counts(cl))
end

"Whether the kernel and swipl agree on clause `k`: head code and slots, and a framed one's size."
_va_agrees(o, t::_VaSwipl, framed::Bool)::Bool =
    o[1] == t.head && o[2] == t.slots &&
    (!framed || o[3] == t.frame - length(t.choice))

const _VA_SWIPL_BIN = Sys.which("swipl")
const _VA_SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

@testset "variable analysis of clauses with a body vs swipl" begin
    X, Y, Q, W = _vv(1), _vv(2), _vv(3), _vv(4)
    A, B, C, D, E, P = _vv(5), _vv(6), _vv(7), _vv(8), _vv(9), _vv(10)
    q(xs...) = _ve("q", collect(_V, xs))
    r(xs...) = _ve("r", collect(_V, xs))
    s(xs...) = _ve("s", collect(_V, xs))
    fx = "h_functor($(_hF("f", 1)))"
    # (head, body, framed, head code, body slots, frame size), each probed in swipl 10.1.16
    # (2026-10-04); a framed clause's body is `shift(k), Body, zz`, its slots the Body's
    pinned = [
        # p1(X) :- q(X): an argument used in the body is in its argument slot, no head code
        (_ve("p1", [X]), q(X), true, ["i_enter"], ["0"], 1),
        # p2(f(X)) :- q(X): a head singleton used in the body is not a void
        (
            _ve("p2", [_ve("f", [X])]),
            q(X),
            true,
            [fx, "h_firstvar(1)", "h_pop", "i_enter"],
            ["1"],
            2
        ),
        # p3 :- (q(Y) ; r(Y)): once in each branch is once — a void (times = max, not sum)
        (_vs("p3"), _ve(";", [q(Y), r(Y)]), true, ["i_enter"], ["v", "v"], 0),
        # p4 :- (q(Y) ; r(Y)), s(Y): ... and used after the branches re-unite, it is not
        (
            _vs("p4"), _ve(",", [_ve(";", [q(Y), r(Y)]), s(Y)]), true, ["i_enter"],
            ["0", "0", "0"], 1
        ),
        # p5 :- (\+ q(Y) ; r(Y)): a variable of a `\+` goal is not a branch variable — not a void
        (_vs("p5"), _ve(";", [_ve("\\+", [q(Y)]), r(Y)]), true, ["i_enter"], ["0", "0"], 1),
        # p6 :- (q(Y) -> r(Y) ; s): `->` is control, so `;` sees Y in its left branch twice
        (
            _vs("p6"), _ve(";", [_ve("->", [q(Y), r(Y)]), _vs("s")]), true, ["i_enter"],
            ["0", "0"], 1
        ),
        # p7(A,B,C,D) :- q(D,C,B,A,E,E): body variables above the arguments
        (
            _ve("p7", [A, B, C, D]), q(D, C, B, A, E, E), true, ["i_enter"],
            ["3", "2", "1", "0", "4", "4"], 5
        ),
        # p8 :- \+ q(Y), r(Y): a `\+` changes no count
        (_vs("p8"), _ve(",", [_ve("\\+", [q(Y)]), r(Y)]), true, ["i_enter"], ["0", "0"], 1),
        # p9 :- q((W;W)): a `;` in a goal's ARGUMENT is data, not a branch
        (_vs("p9"), q(_ve(";", [W, W])), true, ["i_enter"], ["0", "0"], 1),
        # p10 :- (q(X) *-> r(X) ; s(Y,Y)): `*->` is control too
        (
            _vs("p10"), _ve(";", [_ve("*->", [q(X), r(X)]), s(Y, Y)]), true, ["i_enter"],
            ["0", "0", "1", "1"], 2
        ),
        # p11(P) :- (q(P) -> \+ r(Q) ; s(Q)): a `\+` INSIDE a branch takes its variables out of it
        (
            _ve("p11", [P]), _ve(";", [_ve("->", [q(P), _ve("\\+", [r(Q)])]), s(Q)]), true,
            ["i_enter"], ["0", "1", "1"], 2
        ),
        # p12 :- ((q(Y) ; r(Y)) ; s(Y)): nested branches, once in each — a void
        (
            _vs("p12"), _ve(";", [_ve(";", [q(Y), r(Y)]), s(Y)]), true, ["i_enter"],
            ["v", "v", "v"], 0
        ),
        # p13(f(X)) :- (q(X) ; r): a head variable met in one branch is not a void
        (
            _ve("p13", [_ve("f", [X])]), _ve(";", [q(X), _vs("r")]), true,
            [fx, "h_firstvar(1)", "h_pop", "i_enter"], ["1"], 2
        ),
        # BARE — b1(X) :- q(Y, X, Y): a body goal's direct argument is numbered ABOVE the arity
        (_ve("b1", [X]), q(Y, X, Y), false, ["i_enter"], ["1", "0", "1"], 2),
        # b2(X) :- (q(Y) ; r(X, Y)): a last call in a branch (L_* moves, then B_* code)
        (_ve("b2", [X]), _ve(";", [q(Y), r(X, Y)]), false, ["i_enter"], ["v", "0", "v"], 1),
        # b4(X, Y) :- q(Y, X, g(_, X))
        (
            _ve("b4", [X, Y]), q(Y, X, _ve("g", [W, X])), false, ["i_enter"],
            ["1", "0", "v", "0"], 2
        ),
        # b5 :- \+ q(Y, Y)
        (_vs("b5"), _ve("\\+", [q(Y, Y)]), false, ["i_enter"], ["0", "0"], 1),
        # b6(X) :- X: a variable goal
        (_ve("b6", [X]), X, false, ["i_enter"], ["0"], 1)
    ]
    clauses = [(h, fr ? _va_body(b) : b, fr) for (h, b, fr, _, _, _) in pinned]
    for (k, (_, b, _, wh, ws, wn)) in enumerate(pinned)
        @test _va_kernel(clauses[k][1], clauses[k][2]) == (wh, ws, wn)
    end
    np = length(clauses)
    g = _VaGen(Xoshiro(20261004), UInt64(1_000))
    for k in 1:600
        push!(clauses, _vaclause(g, k, k <= 400))
    end
    ours = [_va_kernel(h, b) for (h, b, _) in clauses]
    rnd = (np + 1):length(clauses)
    # the sample exercises the cases: a body-only void, a variable met twice in the clause that is
    # still a void (the branches), heads with code, slots past the second argument, and bare
    # clauses whose top goal has a direct variable argument first met there
    @test any(k -> "v" in ours[k][2], rnd)
    branch_voids = count(rnd) do k
        h, b, _ = clauses[k]
        cnt = ix_var_counts(_ve(":-", [h, b]))
        ci = _va_ci(h)
        LK._compile_clause_head!(_VGD, ci, h, b)
        any(((key, n),) -> n > 1 && !haskey(ci.vardefs, key), cnt)
    end
    @test branch_voids > 0
    @test any(k -> length(ours[k][1]) > 1, rnd)
    @test any(k -> any(x -> x != "v" && parse(Int, x) >= 3, ours[k][2]), rnd)
    bare_top = count(rnd) do k
        h, b, fr = clauses[k]
        ar = kind(h) === SYM ? 0 : nchildren(h) - 1
        hv = keys(ix_var_counts(h))                       # every head variable
        !fr && kind(b) === EXPR && !LK._is_control(b, _VGD.functors_control) &&
            any(
                i ->
                    kind(child(b, i)) === VAR && i - 2 < ar &&
                    !(var_key(child(b, i)) in hv),
                2:nchildren(b))
    end
    @test bare_top > 0
    if _VA_SWIPL_BIN !== nothing
        @testset "identical to swipl" begin
            cases = [(_va_text(h, b), fr) for (h, b, fr) in clauses]
            theirs = _va_swipl(cases)
            @test length(theirs) == length(clauses)
            framed = [k for k in eachindex(theirs) if clauses[k][3]]
            # the oracle's own derivation: the choice variables are numbered from the Prolog
            # variables up, and a balancing `c_var` names a Prolog variable
            pv(t) = t.frame - length(t.choice)
            @test all(
                k -> theirs[k].choice == collect(pv(theirs[k]):(theirs[k].frame - 1)),
                framed
            )
            @test all(k -> all(<(pv(theirs[k])), theirs[k].cvar), framed)
            @test any(k -> !isempty(theirs[k].choice), framed) &&
                any(t -> !isempty(t.cvar), theirs)
            @test all(k -> (theirs[k].frame == -2) == !clauses[k][3], eachindex(theirs))
            bad = [
                k for k in eachindex(clauses) if
                k > length(theirs) || !_va_agrees(ours[k], theirs[k], clauses[k][3])
            ]
            for k in bad[1:min(end, 5)]
                println(stderr, "  ", cases[k][1], "\n    ours  ", ours[k], "\n    swipl ",
                    k <= length(theirs) ? theirs[k] : "<missing>")
            end
            @test isempty(bad)
            @test isempty(intersect(bad, 1:np))     # the pinned clauses, live
        end
    elseif _VA_SWIPL_REQUIRED
        error(
            "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the variable-analysis differential would be skipped"
        )
    else
        @info "VARIABLE ANALYSIS vs swipl NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
        @testset "swipl comparison skipped only where it is not required" begin
            @test !_VA_SWIPL_REQUIRED
        end
    end
end
