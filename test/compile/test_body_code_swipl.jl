# ORIGINAL: live differential of the body compiler (V2) against swipl; upstream has no counterpart (it tests SWI against itself).
# test/compile/test_body_code_swipl.jl — pl-comp.c's body compiler (V2: `compileClause`'s rule
# path, `compileBody` for `,`, `compileSubClause` for plain goals, the body side of
# `compileArgument`, `lco` and `reverse_code`), compared with swipl 10.1.16 WHOLE CLAUSE BY WHOLE
# CLAUSE: every instruction, every operand by its KIND (`'$vmi_property'(Name, argv(Types))` on
# swipl's side, `codeTable(op).argtype` on the kernel's), and the label an `L_NOLCO` jumps to.
# TERM-GENERIC: runtests.jl runs it on every implementation.
#   * operands: a slot (`var`, `fvar`) as its number; a jump as its label; a procedure by name and
#     arity, a functor by name and arity, every literal by value (code_testlib.jl). The literal- and
#     procedure-table INDICES are the kernel's own and never compared (V1 L2, V1 procedures);
#   * swipl's side: `clause_vm/2` and `vmi_labels/2` (library(vm)) — not `vm_list`'s text, whose
#     labelled lines a line parser drops, and that is where the LCO jump lands;
#   * the corpus: pinned clauses — six with swipl's code written here (probed in 10.1.16), so the CI
#     jobs without swipl pin them too, the rest compared live; nreverse and qsort as swipl CONSULTS
#     them from bench/programs, each clause tied to the kernel's by `=@=`; random rule clauses of
#     plain goals; coverage checks that the sample exercises every case;
#   * what V2 refuses (`NotPortedError`), what swipl refuses (`type_error(callable, Body)`, the WHOLE
#     body, probed), and the kernel-only cases (`$expr/n`, a value SWI has no type for);
#   * clause/2 and retract/1 answer for the body `true` — facts only; retractall/1 takes rules too.
include(joinpath(@__DIR__, "..", "db", "index_testlib.jl"))
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "code_testlib.jl"))
using Random

const _B = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
"The database the clauses of this file are compiled in (its global data)."
const _BGD = LK.PL_global_data{_B}()
_bs(n) = lk_sym(_B, Symbol(n))
_be(f, xs::AbstractVector) = mk_expr(_B, _B[_bs(f); xs])
_bf(f, xs::_B...) = _be(f, collect(_B, xs))
_bg(v) = lk_gnd(_B, v)
_bv(k::Integer) = lk_var(_B, UInt64(k))
_bcons(h::_B, t::_B) = _bf("[|]", h, t)
_blist(xs::_B...) = foldr(_bcons, xs; init=mk_nil(_B))
"A right-nested conjunction `(a, (b, c))` of the goals."
_bconj(gs::_B...) = foldr((a, b) -> _bf(",", a, b), gs)

# ── the kernel side ──────────────────────────────────────────────────────────────────────────────
"Every symbol's name in the terms seen, by `sym_key`: how a procedure operand is written by name."
const _BNAMES = Dict{UInt64, String}()
function _bnames!(t)
    if kind(t) === SYM
        _BNAMES[sym_key(t)] = String(lk_name(t))
    elseif kind(t) === EXPR
        foreach(i -> _bnames!(child(t, i)), 1:nchildren(t))
    end
    return t
end

"The functor `(name, arity)` of a head or goal (an atom or a symbol-headed compound)."
_bfunctor(t::_B) = kind(t) === SYM ? (t, 0) : (child(t, 1), nchildren(t) - 1)

"`head :- body` (`body` `nothing` for a fact) compiled as a clause of its predicate in `_BGD`."
function _bclause(head::_B, body::Union{Nothing, _B}; gd=_BGD)::LK.Clause{_B}
    _bnames!(head)
    body === nothing || _bnames!(body)
    user = LK.MODULE_user(gd)
    name, ar = _bfunctor(head)
    proc = LK.lookupProcedure(sym_key(name), ar, user)
    return LK.compileClause(gd, head, body, proc, user)
end

"An operand word `w` of kind `k` of instruction `op`, as both sides write it."
function _bc_op(op, k::UInt8, w::UInt64, lits, procs, jump)::String
    if k == LK.CA1_VAR || k == LK.CA1_FVAR
        return string(LK.VARNUM(w))
    elseif k == LK.CA1_INTEGER
        return op == LK.H_VOID_N ? string(Int(w)) : _hlit(lits[w])     # a count, or a literal
    elseif k in (LK.CA1_DATA, LK.CA1_FLOAT, LK.CA1_MPZ, LK.CA1_MPQ, LK.CA1_STRING)
        return _hlit(lits[w])
    elseif k == LK.CA1_FUNC
        i = LK.functor_literal(w)
        return _hF(i == 0 ? "\$expr" : String(lk_name(lits[i])), LK.functor_arity(w))
    elseif k == LK.CA1_LPROC
        d = procs[w].definition
        return "P:" * _hcps(_BNAMES[d.functor_name]) * "/$(d.arity)"
    elseif k == LK.CA1_JUMP
        return jump(w)
    end
    error("_bc_op: no rendering for operand kind $k of $(LK.codeTable(op).name)")
end

"""
The kernel's code of clause `cl`: one string per instruction, its operands by KIND (`_bc_op`), and
`L<n>:` before an instruction a jump lands on (numbered in order of first jump, as vmi_labels/2).
A jump that does not land on an instruction, or code that ends inside one, fails.
"""
function _bc_kernel(cl::LK.Clause{_B})::Vector{String}
    codes = cl.codes
    starts = Int[]
    pc = 1
    while pc <= length(codes)
        push!(starts, pc)
        pc += 1 + LK.codeTable(codes[pc]).arguments
    end
    pc == length(codes) + 1 || error("_bc_kernel: the code ends inside an instruction")
    labels = Dict{Int, String}()
    rendered = String[]
    for s in starts
        op = codes[s]
        info = LK.codeTable(op)
        after = s + 1 + info.arguments
        jump(w) =
            let t = after + Int(w)
                t in starts || t == length(codes) + 1 ||
                    error("_bc_kernel: a jump to $t lands inside an instruction")
                get!(() -> "L$(length(labels) + 1)", labels, t)
            end
        ops = [
            _bc_op(op, info.argtype[i], codes[s + i], cl.literals, cl.procedures, jump) for
            i in 1:(info.arguments)
        ]
        name = lowercase(String(info.name))
        push!(rendered, isempty(ops) ? name : "$name($(join(ops, ",")))")
    end
    out = String[]
    for (s, r) in zip(starts, rendered)
        haskey(labels, s) && push!(out, labels[s] * ":")
        push!(out, r)
    end
    return out
end

# ── the swipl side ───────────────────────────────────────────────────────────────────────────────
# A clause's code from `clause_vm/2`, labelled by `vmi_labels/2`, each instruction written as
# `_bc_kernel` writes the kernel's: operands by the kinds `'$vmi_property'(Name, argv(Types))` gives.
# allow-docstring-interp: a raw"""…""" string never interpolates; `$vmi_property` is Prolog's name
const _BC_SWIPL = raw"""
:- use_module(library(vm)).
bc_show(Ref) :-
    clause_vm(Ref, VM), vmi_labels(VM, L),
    forall(member(E, L), ( bc_elem(E, Out), writeln(Out) )).
bc_elem(label(L), Out) :- !, format(atom(Out), "~w:", [L]).
bc_elem(vmi(I, _), Out) :-
    I =.. [N|As],
    (   As == [] -> Out = N
    ;   '$vmi_property'(N, argv(Ts)),
        maplist(bc_op(N), Ts, As, Ss), atomic_list_concat(Ss, ',', J),
        format(atom(Out), "~w(~w)", [N, J])
    ).
bc_op(_, var, X, S) :- !, format(string(S), "~w", [X]).
bc_op(_, fvar, X, S) :- !, format(string(S), "~w", [X]).
bc_op(_, jump, X, S) :- !, format(string(S), "~w", [X]).
bc_op(h_void_n, integer, X, S) :- !, format(string(S), "~w", [X]).
bc_op(_, lproc, F/A, S) :- !, atom_codes(F, C), format(string(S), "P:~w/~d", [C, A]).
bc_op(N, _, X, S) :- hc_op(N, X, S).
bc_case_show(Cl) :- assertz(Cl, Ref), bc_show(Ref).
% the I-th clause of a CONSULTED program, tied to the kernel's clause by =@= first
bc_prog_show(Cl, I) :-
    ( Cl = (H :- _) -> true ; H = Cl ),
    functor(H, N, A), functor(G, N, A), nth_clause(G, I, Ref), clause(FH, FB, Ref),
    ( FB == true -> FC = FH ; FC = (FH :- FB) ),
    ( FC =@= Cl -> writeln('@@tie ok') ; writeln('@@tie DIFFERS') ),
    bc_show(Ref).
"""

"swipl's code for each case: `cases` are goals over `_BC_SWIPL` (one block each), `prelude` loads first."
function _bc_swipl(cases::Vector{String}; prelude::String="")::Vector{Vector{String}}
    mktempdir() do d
        f = joinpath(d, "bc.pl")
        write(
            f,
            ":- initialization(main, main).\n" * _HSWIPL_OPS * _BC_SWIPL *
            "main :- $(isempty(prelude) ? "true" : prelude),\n" *
            "    forall(bc_goal(G), ( catch(G, E, (print_message(error, E), fail)) -> writeln('@@end') ; writeln('@@failed'), writeln('@@end') )).\n" *
            join(["bc_goal($c).\n" for c in cases])
        )
        ef = joinpath(d, "bc.err")
        proc = run(
            pipeline(ignorestatus(`swipl -q $f`); stdout=joinpath(d, "bc.out"), stderr=ef)
        )
        if !success(proc)
            println(stderr, "  swipl exited $(proc.exitcode); its stderr ends:")
            foreach(l -> println(stderr, "    ", l), last(readlines(ef), 20))
        end
        res = Vector{String}[]
        cur = String[]
        for l in eachline(joinpath(d, "bc.out"))
            if l == "@@end"
                push!(res, cur)
                cur = String[]
            elseif !isempty(l)
                push!(cur, _hswipl_floats(l))
            end
        end
        return res
    end
end

"A clause as Prolog text: shared variables `V<key>`, a variable met once `_`."
function _bc_text(head::_B, body::Union{Nothing, _B})::String
    cl = body === nothing ? head : _bf(":-", head, body)
    return ix_text(cl, ix_var_counts(cl))
end

const _BC_SWIPL_BIN = Sys.which("swipl")
const _BC_SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

# ── pinned clauses ───────────────────────────────────────────────────────────────────────────────
"A procedure operand as both sides write it."
_bP(n, a) = "P:" * _hcps(n) * "/$a"
const _bX, _bL1, _bL2, _bL3 = _bv(1), _bv(2), _bv(3), _bv(4)

# (head, body, swipl 10.1.16's code — probed, `clause_vm/2` + `vmi_labels/2`)
const _BC_PINNED_CODE = [
    (   # concatenate/3, clause 1: LCO with i_tcall, b_var1 already in place (no l_var for it)
        _bf("concatenate", _bcons(_bX, _bL1), _bL2, _bcons(_bX, _bL3)),
        _bf("concatenate", _bL1, _bL2, _bL3),
        [
            "h_list_ff(3,4)", "h_void", "h_list", "h_var(3)", "h_firstvar(5)", "h_pop",
            "i_enter", "l_nolco(L1)", "l_var(0,4)", "l_var(2,5)", "i_tcall", "L1:",
            "b_var(4)",
            "b_var1", "b_var(5)", "i_depart($(_bP("concatenate", 3)))", "i_exit"
        ]
    ),
    (   # top :- nreverse — an empty L-block and i_lcall
        _bs("top"), _bs("nreverse"),
        [
            "i_enter", "l_nolco(L1)", "i_lcall($(_bP("nreverse", 0)))", "L1:",
            "i_depart($(_bP("nreverse", 0)))", "i_exit"
        ]
    ),
    (   # p :- q(a, [], 7) — l_atom, l_nil, l_smallint
        _bs("p"), _bf("q", _bs("a"), mk_nil(_B), _bg(7)),
        [
            "i_enter", "l_nolco(L1)", "l_atom(0,a:[97])", "l_nil(1)", "l_smallint(2,i:7)",
            "i_lcall($(_bP("q", 3)))", "L1:", "b_atom(a:[97])", "b_nil", "b_smallint(i:7)",
            "i_depart($(_bP("q", 3)))", "i_exit"
        ]
    ),
    (   # p2(X, Y) :- q(Y, X) — no LCO: Y's slot would be overwritten by X first
        _bf("p2", _bv(1), _bv(2)), _bf("q", _bv(2), _bv(1)),
        ["i_enter", "b_var1", "b_var0", "i_depart($(_bP("q", 2)))", "i_exit"]
    ),
    (   # p3 :- q(f(X, _)), r(X) — b_argfirstvar, b_void then b_pop (no merge in a body)
        _bs("p3"), _bconj(_bf("q", _bf("f", _bv(1), _bv(9))), _bf("r", _bv(1))),
        [
            "i_enter", "b_functor(F:[102]/2)", "b_argfirstvar(0)", "b_void", "b_pop",
            "i_call($(_bP("q", 1)))", "l_nolco(L1)", "i_lcall($(_bP("r", 1)))", "L1:",
            "b_var0",
            "i_depart($(_bP("r", 1)))", "i_exit"
        ]
    ),
    (   # p4 :- true — a FACT
        _bs("p4"), _bs("true"), ["i_exitfact"]
    )
]

# more pinned clauses, compared live (the plan's list, V2 § 4.2)
const _BC_PINNED_LIVE = [
    # nreverse/2 clause 1: LCO abandoned at b_list
    (_bf("nreverse", _bcons(_bX, _bL1), _bL2),
        _bconj(_bf("nreverse", _bL1, _bL3), _bf("concatenate", _bL3, _blist(_bX), _bL2))),
    (_bf("pself", _bv(1)), _bf("pself", _bv(1))),                         # i_tcall, empty block
    (_bs("pv"), _bf("q", _bv(1))),                                          # l_void
    (_bs("pf"), _bf("q", _bg(1.5))),                                        # no LCO: b_float
    (_bs("ps"), _bf("q", _bg("s"))),                                        # no LCO: b_string
    (_bs("pz"), _bf("q", _bg(big(2)^56))),                                  # no LCO: b_mpz
    (_bs("pq"), _bf("q", _bg(1 // big(3)))),                                # no LCO: b_mpq
    (_bs("pt"), _bf("q", _bg(2147483648))),                                 # b_smallint by storage
    (_bs("px"), _bconj(_bf("q", _bv(1)), _bf("r", _bv(1)))),                # b_firstvar(0), b_var0
    (_bf("pw", _bv(1), _bv(2), _bv(3), _bv(4)), _bf("q", _bv(4))),          # b_var(3)
    (_bs("pn"), _bf(",", _bf(",", _bs("a"), _bs("b")), _bs("c"))),          # (a, b), c
    (_bs("pl"), _bconj(_bf("q", _bcons(_bv(1), _bv(2))), _bf("r", _bv(1), _bv(2)))),   # b_list
    (_bs("pd"), _bf("q", _bf(";", _bs("a"), _bs("b")), _bf("call", _bv(1)))),  # control as DATA
    (_bf("pa", _bv(1), _bs("k")), _bf("q", _bs("k"), _bv(1))),              # head atom, l_atom
    (_bs("pnil"), _bf("q", _bs("[]"), mk_nil(_B))),                         # '[]' vs []
    (_bs("prf"), _bf("q", _bf("f", _bs("a"), _bf("g", _bs("b"))))),         # b_rfunctor
    (_bs("prl"), _bf("q", _blist(_bs("a"), _bs("b"))))                      # b_rlist
]

# ── nreverse and qsort, as bench/programs has them ───────────────────────────────────────────────
const _BC_PROGRAMS = joinpath(@__DIR__, "..", "..", "bench", "programs")
"A list of the integers `xs`."
_bints(xs) = _blist((_bg(x) for x in xs)...)
"nreverse.pl's clauses as terms, in file order: (head, body or nothing, index in its predicate)."
function _bc_nreverse()
    X, L0, L, L1, L2, L3 = (_bv(k) for k in 1:6)
    return [
        (_bs("top"), _bs("nreverse"), 1),
        (_bs("nreverse"), _bf("nreverse", _bints(1:30), _bv(7)), 1),
        (_bf("nreverse", _bcons(X, L0), L),
            _bconj(_bf("nreverse", L0, L1), _bf("concatenate", L1, _blist(X), L)), 1),
        (_bf("nreverse", mk_nil(_B), mk_nil(_B)), nothing, 2),
        (
            _bf("concatenate", _bcons(X, L1), L2, _bcons(X, L3)),
            _bf("concatenate", L1, L2, L3),
            1
        ),
        (_bf("concatenate", mk_nil(_B), L, L), nothing, 2)
    ]
end
const _BC_QSORT_NUMS = [27, 74, 17, 33, 94, 18, 46, 83, 65, 2, 32, 53, 28, 85, 99, 47, 28,
    82, 6,
    11, 55, 29, 39, 81, 90, 37, 10, 0, 66, 51, 7, 21, 85, 27, 31, 63, 75, 4, 95, 99, 11, 28,
    61,
    74, 18, 92, 40, 53, 59, 8]
"qsort.pl's clauses as terms, in file order — partition/4 clause 1 is `!`'s (V6), apart."
function _bc_qsort()
    X, L, R, R0, L1, L2, R1, Y = (_bv(k) for k in 1:8)
    return [
        (_bs("top"), _bs("qsort"), 1),
        (_bs("qsort"), _bf("qsort", _bints(_BC_QSORT_NUMS), _bv(9), mk_nil(_B)), 1),
        (_bf("qsort", _bcons(X, L), R, R0),
            _bconj(_bf("partition", L, X, L1, L2), _bf("qsort", L2, R1, R0),
                _bf("qsort", L1, R, _bcons(X, R1))), 1),
        (_bf("qsort", mk_nil(_B), R, R), nothing, 2),
        (_bf("partition", _bcons(X, L), Y, L1, _bcons(X, L2)),
            _bf("partition", L, Y, L1, L2), 2),
        (_bf("partition", mk_nil(_B), _bv(10), mk_nil(_B), mk_nil(_B)), nothing, 3)
    ]
end
"qsort's partition/4 clause 1, `X =< Y, !, partition(L, Y, L1, L2)`: `!` is V6's."
function _bc_qsort_cut()
    X, L, Y, L1, L2 = (_bv(k) for k in 1:5)
    return (_bf("partition", _bcons(X, L), Y, _bcons(X, L1), L2),
        _bconj(_bf("=<", X, Y), _bs("!"), _bf("partition", L, Y, L1, L2)))
end

# ── random rule clauses ──────────────────────────────────────────────────────────────────────────
mutable struct _BcGen
    rng::Xoshiro
    next::UInt64        # the last variable key handed out
end
_bcfresh!(g::_BcGen)::_B = (g.next += 1; _bv(g.next))

const _BC_DATA_ATOMS = ["a", "b", "[]", ";", "!", "true", "call", "f", "q"]

"A constant: atoms (control names as DATA), `[]`, every number kind, a string."
function _bcconst(g::_BcGen)::_B
    r = rand(g.rng, 1:9)
    r <= 3 && return _bs(rand(g.rng, _BC_DATA_ATOMS))
    r == 4 && return mk_nil(_B)
    r == 5 && return _bg(rand(g.rng, -3:40))
    r == 6 && return _bg(rand(g.rng, (big(2)^56, -big(2)^60, 2147483648)))
    r == 7 && return _bg(rand(g.rng, (1.5, -0.0, 2.25)))
    r == 8 && return _bg(rand(g.rng, (1 // big(3), -7 // big(2))))
    return _bg(rand(g.rng, ("s", "")))
end

"An argument: mostly a variable from `pool` (or a fresh one), constants, compounds, list cells, control compounds and call/1 as DATA."
function _bcarg(g::_BcGen, pool::Vector{_B}, depth::Int)::_B
    r = rand(g.rng)
    r < 0.45 && return rand(g.rng, pool)
    if r < 0.55
        v = _bcfresh!(g)
        push!(pool, v)
        return v
    end
    (r < 0.75 || depth >= 3) && return _bcconst(g)
    if r < 0.85
        return _bcons(_bcarg(g, pool, depth + 1), _bcarg(g, pool, depth + 1))
    elseif r < 0.95
        f = rand(g.rng, ("f", "g", ";", ",", "call"))
        ar = f in (";", ",") ? 2 : rand(g.rng, 1:3)
        return _be(f, [_bcarg(g, pool, depth + 1) for _ in 1:ar])
    end
    return _bf("call", _bcarg(g, pool, depth + 1))
end

"""
A random rule clause `bh<k>(…) :- G1, …, Gn` of plain goals `bg<j>` (never a control, inline or
reserved name), nested `,` either way; the last goal sometimes the clause's own predicate (i_tcall)
or the head's variables permuted (an argument that LCO would overwrite).
"""
function _bcclause(g::_BcGen, k::Int)::Tuple{_B, _B}
    pool = _B[_bcfresh!(g) for _ in 1:3]             # typed: a leaf type otherwise (AltTerm)
    har = rand(g.rng, 0:4)
    hname = "bh$k"
    head = har == 0 ? _bs(hname) : _be(hname, [_bcarg(g, pool, 1) for _ in 1:har])
    hvars = filter(
        a -> kind(a) === VAR, har == 0 ? _B[] : [child(head, i) for i in 2:(har + 1)]
    )
    ngoals = rand(g.rng, 1:4)
    goals = _B[]
    for j in 1:ngoals
        r = rand(g.rng)
        if j == ngoals && r < 0.2
            push!(goals, har == 0 ? head : _be(hname, [_bcarg(g, pool, 1) for _ in 1:har]))
        elseif j == ngoals && r < 0.4 && length(hvars) >= 2
            push!(goals, _be("bg9", shuffle(g.rng, hvars)))
        else
            ar = rand(g.rng, 0:4)
            name = "bg$(rand(g.rng, 0:5))"
            push!(
                goals, ar == 0 ? _bs(name) : _be(name, [_bcarg(g, pool, 1) for _ in 1:ar])
            )
        end
    end
    body = if length(goals) >= 3 && rand(g.rng, Bool)
        _bf(",", _bconj(goals[1:2]...), _bconj(goals[3:end]...))     # a left-nested conjunction
    else
        _bconj(goals...)
    end
    return (head, body)
end

# ── the tests ────────────────────────────────────────────────────────────────────────────────────
"The instructions each clause's code uses, by name (labels left out)."
_bc_names(code::Vector{String}) =
    Set(first(split(c, '(')) for c in code if !endswith(c, ":"))

@testset "body code vs swipl" begin
    @testset "pinned clauses: swipl 10.1.16's code, written here" begin
        for (h, b, want) in _BC_PINNED_CODE
            got = _bc_kernel(_bclause(h, b))
            got == want || println(stderr, "  ", _bc_text(h, b), "\n    ours ", got)
            @test got == want
        end
        cl = _bclause(_BC_PINNED_CODE[end][1], _BC_PINNED_CODE[end][2])
        @test cl.flags & LK.UNIT_CLAUSE != 0                    # `p :- true` is a fact
        r = _bclause(_BC_PINNED_CODE[1][1], _BC_PINNED_CODE[1][2])
        @test r.flags & LK.UNIT_CLAUSE == 0 && r.variables == r.prolog_vars == 6
        # each call operand is the database's own procedure
        user = LK.MODULE_user(_BGD)
        @test all(r.procedures) do p
            d = p.definition
            p === LK.lookupProcedure(d.functor_name, d.arity, user)
        end
    end

    g = _BcGen(Xoshiro(20261005), UInt64(1_000))
    random = [_bcclause(g, k) for k in 1:400]
    live = [[(h, b) for (h, b, _) in _BC_PINNED_CODE]; _BC_PINNED_LIVE; random]
    ours = [_bc_kernel(_bclause(h, b)) for (h, b) in live]
    rnd = (length(live) - length(random) + 1):length(live)

    @testset "the sample exercises every case" begin
        used = union((_bc_names(ours[k]) for k in eachindex(live))...)
        want = [
            "b_atom", "b_smallint", "b_nil", "b_float", "b_mpz", "b_mpq", "b_string",
            "b_argvar", "b_var0", "b_var1", "b_var2", "b_var", "b_argfirstvar",
            "b_firstvar",
            "b_void", "b_functor", "b_rfunctor", "b_list", "b_rlist", "b_pop", "i_enter",
            "i_call", "i_depart", "i_exit", "l_nolco", "l_var", "l_void", "l_atom", "l_nil",
            "l_smallint", "i_lcall", "i_tcall"
        ]
        missing_ = setdiff(want, used)
        isempty(missing_) || println(stderr, "  not exercised: ", missing_)
        @test isempty(missing_)
        rcode = [ours[k] for k in rnd]
        @test any(c -> "i_tcall" in c, rcode) &&
            any(c -> any(startswith("i_lcall"), c), rcode)
        # an L-block that is empty: l_nolco directly followed by the call
        @test any(rcode) do c
            any(
                i ->
                    startswith(c[i], "l_nolco") &&
                    (c[i + 1] == "i_tcall" || startswith(c[i + 1], "i_lcall")),
                1:(length(c) - 1))
        end
        # LCO abandoned: a last call compiled without an l_nolco block
        @test any(c -> !any(startswith("l_nolco"), c), rcode)
    end

    if _BC_SWIPL_BIN !== nothing
        @testset "identical to swipl" begin
            cases = ["bc_case_show(($(_bc_text(h, b))))" for (h, b) in live]
            theirs = _bc_swipl(cases)
            @test length(theirs) == length(live)
            bad = 0
            for k in eachindex(live)
                k <= length(theirs) || break
                if ours[k] != theirs[k]
                    bad += 1
                    bad <= 5 && println(stderr, "  ", _bc_text(live[k]...), "\n    ours  ",
                        ours[k], "\n    swipl ", theirs[k])
                end
            end
            @test bad == 0
        end

        @testset "nreverse and qsort, as swipl consults them" begin
            for (file, clauses) in
                (("nreverse.pl", _bc_nreverse()), ("qsort.pl", _bc_qsort()))
                cases = ["bc_prog_show(($(_bc_text(h, b))), $i)" for (h, b, i) in clauses]
                theirs = _bc_swipl(
                    cases; prelude="consult('$(joinpath(_BC_PROGRAMS, file))')"
                )
                @test length(theirs) == length(clauses)
                for (k, (h, b, _)) in enumerate(clauses)
                    k <= length(theirs) || break
                    t = theirs[k]
                    @test !isempty(t) && t[1] == "@@tie ok"     # the clause the file has
                    want = t[2:end]
                    got = _bc_kernel(_bclause(h, b))
                    got == want ||
                        println(stderr, "  $file: ", _bc_text(h, b), "\n    ours  ", got,
                            "\n    swipl ", want)
                    @test got == want
                end
            end
            # qsort's partition/4 clause 1 has `!`: compiling it is V6's
            @test_throws LK.NotPortedError _bclause(_bc_qsort_cut()...)
        end
    elseif _BC_SWIPL_REQUIRED
        error(
            "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the body-code differential would be skipped"
        )
    else
        @info "BODY CODE vs swipl NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
        @testset "swipl comparison skipped only where it is not required" begin
            @test !_BC_SWIPL_REQUIRED
        end
    end
end

@testset "what V2 refuses, and swipl's type_error(callable, Body)" begin
    p = _bs("pr")
    for body in (
        _bf(";", _bs("a"), _bs("b")), _bf("->", _bs("a"), _bs("b")), _bf("\\+", _bs("a")),
        _bf(":", _bs("m"), _bs("g")), _bf("@", _bs("g"), _bs("m")), _bf("\$", _bs("g")),
        _bconj(_bf("q", _bv(1)), _bv(1)),                       # a variable goal (meta-call)
        _bf("=", _bv(1), _bs("a")), _bf("==", _bv(1), _bs("a")), _bf("integer", _bv(1)),
        _bf("arg", _bg(1), _bv(1), _bv(2)), _bf("is", _bv(1), _bf("+", _bv(2), _bg(1))),
        _bconj(_bs("q"), _bs("true")), _bs("fail"), _bs("!"),
        _bf("call", _bv(1)), _bf("call", _bv(1), _bs("a"))
    )
        @test_throws LK.NotPortedError _bclause(p, body)
    end
    # type_error(callable, Body): the WHOLE body, as swipl 10.1.16 reports it (probed)
    for body in (
        _bconj(_bs("q"), _bv(1)),                               # p :- q, _
        _bconj(_bs("q"), _bg(1)),                               # p :- q, 1
        _bconj(_bs("q"), _bconj(_bs("r"), _bg("s"))),           # p :- q, r, "s"
        mk_nil(_B),                                             # p :- []
        _bconj(_bs("q"), mk_expr(_B, _B[_bv(1), _bs("a")]))     # p :- q, (X a): `$expr/2`
    )
        err = try
            _bclause(p, body)
            nothing
        catch e
            e
        end
        @test err isa LK.CallableTypeError{_B} && err.culprit === body
    end
    # representation_error(max_procedure_arity): a goal of 1025 arguments (MAXARITY)
    @test_throws ErrorException _bclause(p, _be("q", [_bg(1) for _ in 1:(LK.MAXARITY + 1)]))
    # a rule of a multifile predicate needs I_CONTEXT (modules): refused; its facts are not
    gd = LK.PL_global_data{_B}()
    user = LK.MODULE_user(gd)
    mf = LK.lookupProcedure(sym_key(_bs("mf")), 0, user)
    mf.definition.flags |= LK.P_MULTIFILE
    @test_throws LK.NotPortedError LK.compileClause(gd, _bs("mf"), _bs("q"), mf, user)
    @test LK.compileClause(gd, _bs("mf"), nothing, mf, user).flags & LK.UNIT_CLAUSE != 0
end

@testset "kernel-only cases (no SWI counterpart)" begin
    # `$expr/n` as DATA in a body: b_functor($expr/2), every child an argument
    c = _bc_kernel(_bclause(_bs("pe"), _bf("q", mk_expr(_B, _B[_bv(1), _bs("a")]), _bv(1))))
    @test c[2] == "b_functor($(_hF("\$expr", 2)))" && c[3] == "b_argfirstvar(0)" &&
        c[4] == "b_atom(a:[97])" && c[5] == "b_pop"
    # a value SWI has no type for: an opaque B_ATOM literal, moved by L_ATOM with the same index
    O = lk_term_type(Union{Int64, Bool})
    gd = LK.PL_global_data{O}()
    user = LK.MODULE_user(gd)
    po = LK.lookupProcedure(sym_key(lk_sym(O, :po)), 0, user)
    v = lk_gnd(O, true)
    cl = LK.compileClause(gd, lk_sym(O, :po), mk_expr(O, O[lk_sym(O, :q), v]), po, user)
    i = findfirst(==(LK.L_ATOM), cl.codes)
    j = findfirst(==(LK.B_ATOM), cl.codes)
    @test i !== nothing && j !== nothing && cl.codes[i + 2] == cl.codes[j + 1]
    @test cl.literals[cl.codes[j + 1]] === v
end

@testset "clause/2 and retract/1 answer for the body `true`: facts only" begin
    db = IxDB{_B}()
    pr = ix_pred(_B, :cr, 1; dynamic=true, db=db)
    ix_assertz!(pr, _bf("cr", _bg(1)))
    user = LK.MODULE_user(db.gd)
    rule = LK.compileClause(db.gd, _bf("cr", _bv(1)), _bf("q", _bv(1)), pr.proc, user)
    LK.assertDefinition!(db.gd, pr.def, rule, LK.CL_END)
    @test length(ix_clause(pr, _bf("cr", _bv(5)))) == 1         # the fact, not the rule
    @test length(ix_retract!(pr, _bf("cr", _bv(5)))) == 1       # retracts the fact only
    @test isempty(ix_retract!(pr, _bf("cr", _bv(5))))           # the rule is not `cr(_) :- true`
    ix_retractall!(pr, _bf("cr", _bv(5)))                        # retractall takes rules too
    @test LK.hasClausesDefinition(db.gd, pr.def) === nothing
end
