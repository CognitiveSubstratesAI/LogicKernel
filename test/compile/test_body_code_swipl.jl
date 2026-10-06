# ORIGINAL: live differential of the body compiler (V2) against swipl; upstream has no counterpart (it tests SWI against itself).
# test/compile/test_body_code_swipl.jl — pl-comp.c's body compiler (V2: `compileClause`'s rule
# path, `compileBody` for `,`, `compileSubClause` for plain goals and `!`, the body side of
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
#     plain goals and `!`; coverage checks that the sample exercises every case;
#   * what V2 refuses (`NotPortedError`), what swipl refuses (`type_error(callable, Body)`, the WHOLE
#     body, probed), and the kernel-only cases (`$expr/n`, a value SWI has no type for);
#   * clause/2 and retract/1 answer for the body `true` — facts only; retractall/1 takes rules too;
#   * `COMMIT_CLAUSE`: set exactly when the body starts with `!` (c:2165).
include(joinpath(@__DIR__, "..", "db", "index_testlib.jl"))
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "code_testlib.jl"))
using Random

const _B = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
"The database the clauses of this file are compiled in (its global data)."
const _BGD = LK.PL_global_data{_B}()
const _BLD = LK.PL_local_data{_B}()          # the compiler reads its flags
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
function _bclause(head::_B, body::Union{Nothing, _B}; gd=_BGD, ld=_BLD)::LK.Clause{_B}
    _bnames!(head)
    body === nothing || _bnames!(body)
    user = LK.MODULE_user(gd)
    name, ar = _bfunctor(head)
    proc = LK.lookupProcedure(name, ar, user)
    return LK.compileClause(gd, ld, head, body, proc, user)
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
    (_bs("prl"), _bf("q", _blist(_bs("a"), _bs("b")))),                     # b_rlist
    (_bs("pc1"), _bconj(_bs("!"), _bf("q", _bv(1)))),                       # !, first: COMMIT_CLAUSE
    (_bs("pc2"), _bconj(_bf("q", _bv(1)), _bs("!"))),                       # ! last: no I_DEPART
    (_bs("pc3"), _bconj(_bs("q"), _bs("!"), _bs("r"))),                     # ! mid-body
    (_bs("pc4"), _bs("!"))                                                  # p :- !
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
"qsort.pl's clauses as terms, in file order — all six, partition/4 clause 1's `!` included."
function _bc_qsort()
    X, L, R, R0, L1, L2, R1, Y = (_bv(k) for k in 1:8)
    return [
        (_bs("top"), _bs("qsort"), 1),
        (_bs("qsort"), _bf("qsort", _bints(_BC_QSORT_NUMS), _bv(9), mk_nil(_B)), 1),
        (_bf("qsort", _bcons(X, L), R, R0),
            _bconj(_bf("partition", L, X, L1, L2), _bf("qsort", L2, R1, R0),
                _bf("qsort", L1, R, _bcons(X, R1))), 1),
        (_bf("qsort", mk_nil(_B), R, R), nothing, 2),
        (_bc_qsort_cut()..., 1),
        (_bf("partition", _bcons(X, L), Y, L1, _bcons(X, L2)),
            _bf("partition", L, Y, L1, L2), 2),
        (_bf("partition", mk_nil(_B), _bv(10), mk_nil(_B), mk_nil(_B)), nothing, 3)
    ]
end
_blist_(xs::_B...) = foldr(_bcons, xs; init=mk_nil(_B))
"poly_10.pl's clauses as terms, in file order (bench/programs/poly_10.pl), each with its clause index."
function _bc_poly_clauses()
    (Var, Terms1, Terms2, Terms, Var1, Var2, Poly, C, C1, C2, X, E, E1, E2, N, M, Part,
        Result, P,
        Q, Term, PartA, PartB, NewTerm, NewTerms) = (_bv(k) for k in 1:25)
    term(a, b) = _bf("term", a, b)
    poly(a, b) = _bf("poly", a, b)
    one = _bg(1)
    cut = _bs("!")
    return [
        (_bs("top"), _bs("poly_10"), 1),
        (
            _bs("poly_10"),
            _bconj(_bf("test_poly", P), _bf("poly_exp", _bg(10), P, _bv(99))),
            1
        ),
        (
            _bf("test_poly", P),
            _bconj(
                _bf(
                    "poly_add",
                    poly(_bs(:x), _blist_(term(_bg(0), one), term(one, one))),
                    poly(_bs(:y), _blist_(term(one, one))),
                    Q
                ),
                _bf("poly_add", poly(_bs(:z), _blist_(term(one, one))), Q, P)
            ),
            1
        ),
        (_bf("less_than", _bs(:x), _bs(:y)), nothing, 1),
        (_bf("less_than", _bs(:y), _bs(:z)), nothing, 2),
        (_bf("less_than", _bs(:x), _bs(:z)), nothing, 3),
        (
            _bf("poly_add", poly(Var, Terms1), poly(Var, Terms2), poly(Var, Terms)),
            _bconj(cut, _bf("term_add", Terms1, Terms2, Terms)),
            1
        ),
        (
            _bf("poly_add", poly(Var1, Terms1), poly(Var2, Terms2), poly(Var1, Terms)),
            _bconj(
                _bf("less_than", Var1, Var2),
                cut,
                _bf("add_to_order_zero_term", Terms1, poly(Var2, Terms2), Terms)
            ),
            2
        ),
        (
            _bf("poly_add", Poly, poly(Var, Terms2), poly(Var, Terms)),
            _bconj(cut, _bf("add_to_order_zero_term", Terms2, Poly, Terms)),
            3
        ),
        (
            _bf("poly_add", poly(Var, Terms1), C, poly(Var, Terms)),
            _bconj(cut, _bf("add_to_order_zero_term", Terms1, C, Terms)),
            4
        ),
        (_bf("poly_add", C1, C2, C), _bf("is", C, _bf("+", C1, C2)), 5),
        (_bf("term_add", mk_nil(_B), X, X), cut, 1),
        (_bf("term_add", X, mk_nil(_B), X), cut, 2),
        (
            _bf(
                "term_add",
                _bcons(term(E, C1), Terms1),
                _bcons(term(E, C2), Terms2),
                _bcons(term(E, C), Terms)
            ),
            _bconj(cut, _bf("poly_add", C1, C2, C), _bf("term_add", Terms1, Terms2, Terms)),
            3
        ),
        (
            _bf(
                "term_add",
                _bcons(term(E1, C1), Terms1),
                _bcons(term(E2, C2), Terms2),
                _bcons(term(E1, C1), Terms)
            ),
            _bconj(
                _bf("<", E1, E2),
                cut,
                _bf("term_add", Terms1, _bcons(term(E2, C2), Terms2), Terms)
            ),
            4
        ),
        (
            _bf(
                "term_add",
                Terms1,
                _bcons(term(E2, C2), Terms2),
                _bcons(term(E2, C2), Terms)
            ),
            _bf("term_add", Terms1, Terms2, Terms),
            5
        ),
        (
            _bf(
                "add_to_order_zero_term",
                _bcons(term(_bg(0), C1), Terms),
                C2,
                _bcons(term(_bg(0), C), Terms)
            ),
            _bconj(cut, _bf("poly_add", C1, C2, C)),
            1
        ),
        (
            _bf("add_to_order_zero_term", Terms, C, _bcons(term(_bg(0), C), Terms)),
            nothing,
            2
        ),
        (_bf("poly_exp", _bg(0), _bv(98), one), cut, 1),
        (
            _bf("poly_exp", N, Poly, Result),
            _bconj(
                _bf("is", M, _bf(">>", N, one)),
                _bf("is", N, _bf("<<", M, one)),
                cut,
                _bf("poly_exp", M, Poly, Part),
                _bf("poly_mul", Part, Part, Result)
            ),
            2
        ),
        # compiled as the file has it, `M is N-1`; tied as swipl's clause/2 DECOMPILES its A_ADD_FC,
        # `M is N + -1` (probed)
        (_bf("poly_exp", N, Poly, Result),
            _bconj(
                _bf("is", M, _bf("-", N, one)),
                _bf("poly_exp", M, Poly, Part),
                _bf("poly_mul", Poly, Part, Result)
            ), 3,
            _bconj(
                _bf("is", M, _bf("+", N, _bg(-1))),
                _bf("poly_exp", M, Poly, Part),
                _bf("poly_mul", Poly, Part, Result)
            )),
        (
            _bf("poly_mul", poly(Var, Terms1), poly(Var, Terms2), poly(Var, Terms)),
            _bconj(cut, _bf("term_mul", Terms1, Terms2, Terms)),
            1
        ),
        (
            _bf("poly_mul", poly(Var1, Terms1), poly(Var2, Terms2), poly(Var1, Terms)),
            _bconj(
                _bf("less_than", Var1, Var2),
                cut,
                _bf("mul_through", Terms1, poly(Var2, Terms2), Terms)
            ),
            2
        ),
        (
            _bf("poly_mul", P, poly(Var, Terms2), poly(Var, Terms)),
            _bconj(cut, _bf("mul_through", Terms2, P, Terms)),
            3
        ),
        (
            _bf("poly_mul", poly(Var, Terms1), C, poly(Var, Terms)),
            _bconj(cut, _bf("mul_through", Terms1, C, Terms)),
            4
        ),
        (_bf("poly_mul", C1, C2, C), _bf("is", C, _bf("*", C1, C2)), 5),
        (_bf("term_mul", mk_nil(_B), _bv(97), mk_nil(_B)), cut, 1),
        (_bf("term_mul", _bv(96), mk_nil(_B), mk_nil(_B)), cut, 2),
        (
            _bf("term_mul", _bcons(Term, Terms1), Terms2, Terms),
            _bconj(
                _bf("single_term_mul", Terms2, Term, PartA),
                _bf("term_mul", Terms1, Terms2, PartB),
                _bf("term_add", PartA, PartB, Terms)
            ),
            3
        ),
        (_bf("single_term_mul", mk_nil(_B), _bv(95), mk_nil(_B)), cut, 1),
        (
            _bf(
                "single_term_mul",
                _bcons(term(E1, C1), Terms1),
                term(E2, C2),
                _bcons(term(E, C), Terms)
            ),
            _bconj(
                _bf("is", E, _bf("+", E1, E2)),
                _bf("poly_mul", C1, C2, C),
                _bf("single_term_mul", Terms1, term(E2, C2), Terms)
            ),
            2
        ),
        (_bf("mul_through", mk_nil(_B), _bv(94), mk_nil(_B)), cut, 1),
        (
            _bf(
                "mul_through",
                _bcons(term(E, Term), Terms),
                Poly,
                _bcons(term(E, NewTerm), NewTerms)
            ),
            _bconj(
                _bf("poly_mul", Term, Poly, NewTerm),
                _bf("mul_through", Terms, Poly, NewTerms)
            ),
            2
        )
    ]
end

"derive.pl's clauses as terms, in file order (bench/programs/derive.pl), each with its clause index."
function _bc_derive()
    U, V, X, DU, DV, N, N1 = (_bv(k) for k in 1:7)
    x = _bs("x")
    pw(a, b) = _bf("^", a, b)
    d(a, b, c) = _bf("d", a, b, c)
    nest(f, t, n) = n == 0 ? t : nest(f, f(t), n - 1)
    cut = _bs("!")
    return [
        (_bs("top"), _bconj(_bs("ops8"), _bs("log10"), _bs("divide10")), 1),
        (_bs("ops8"),
            d(
                _bf("*", _bf("+", x, _bg(1)),
                    _bf(
                        "*",
                        _bf("+", pw(x, _bg(2)), _bg(2)),
                        _bf("+", pw(x, _bg(3)), _bg(3))
                    )),
                x, _bv(20)), 1),
        (_bs("log10"), d(nest(t -> _bf("log", t), x, 10), x, _bv(20)), 1),
        (_bs("divide10"), d(nest(t -> _bf("/", t, x), x, 9), x, _bv(20)), 1),
        (d(_bf("+", U, V), X, _bf("+", DU, DV)), _bconj(cut, d(U, X, DU), d(V, X, DV)), 1),
        (d(_bf("-", U, V), X, _bf("-", DU, DV)), _bconj(cut, d(U, X, DU), d(V, X, DV)), 2),
        (d(_bf("*", U, V), X, _bf("+", _bf("*", DU, V), _bf("*", U, DV))),
            _bconj(cut, d(U, X, DU), d(V, X, DV)), 3),
        (
            d(
                _bf("/", U, V),
                X,
                _bf("/", _bf("-", _bf("*", DU, V), _bf("*", U, DV)), pw(V, _bg(2)))
            ),
            _bconj(cut, d(U, X, DU), d(V, X, DV)), 4),
        (d(pw(U, N), X, _bf("*", _bf("*", DU, N), pw(U, N1))),
            _bconj(cut, _bf("integer", N), _bf("is", N1, _bf("-", N, _bg(1))), d(U, X, DU)),
            5),
        (d(_bf("-", U), X, _bf("-", DU)), _bconj(cut, d(U, X, DU)), 6),
        (d(_bf("exp", U), X, _bf("*", _bf("exp", U), DU)), _bconj(cut, d(U, X, DU)), 7),
        (d(_bf("log", U), X, _bf("/", DU, U)), _bconj(cut, d(U, X, DU)), 8),
        (d(X, X, _bg(1)), cut, 9),
        (d(_bv(21), _bv(22), _bg(0)), nothing, 10)
    ]
end

"qsort's partition/4 clause 1, `X =< Y, !, partition(L, Y, L1, L2)` — its `!` compiles to I_CUT."
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
        elseif r < 0.5                                     # a cut (I_CUT), anywhere in the body
            push!(goals, _bs("!"))
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
            p === LK.lookupProcedure(d.name, d.arity, user)
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
            "l_smallint", "i_lcall", "i_tcall", "i_cut"
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
                (("nreverse.pl", _bc_nreverse()), ("qsort.pl", _bc_qsort()),
                ("derive.pl", _bc_derive()), ("poly_10.pl", _bc_poly_clauses()))
                # a clause's tie text: its decompiled form where it differs (a 4th element)
                cases = [
                    "bc_prog_show(($(_bc_text(c[1], length(c) == 4 ? c[4] : c[2]))), $(c[3]))"
                    for c in clauses
                ]
                theirs = _bc_swipl(
                    cases; prelude="consult('$(joinpath(_BC_PROGRAMS, file))')"
                )
                @test length(theirs) == length(clauses)
                for (k, (h, b)) in enumerate(clauses)
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

# ── the type tests and var/nonvar (V6b): upstream's decision, cell by cell ────────────────────
# compileBodyVar1/NonVar1 and compileTypeTest (c:4539-4673): inline (`i_<test>`) on a variable
# already seen — a head argument, a head-subterm variable, an earlier body occurrence — and a CALL
# of the predicate for every other shape (a first occurrence, a void, any non-variable), since
# `always` falls back unless `optimise` (c:4522-4536). The shapes are the research probe's
# (scratchpad v6c/p3_clauses.pl), plus a float and a string; each clause's code == swipl's, live.
const _BC_TYPE_TESTS = (
    "var", "nonvar", "integer", "rational", "float", "number", "atomic", "atom", "string",
    "compound", "callable"
)
const _BC_TT_INLINE = ("argvar", "headvar", "notlast")      # the cells compiled inline
function _bc_type_test_cells()
    cells = Tuple{String, String, _B, _B}[]                 # (test, shape, head, body)
    A, Y = _bv(1), _bv(2)
    for t in _BC_TYPE_TESTS
        h(shape, args::_B...) =
            isempty(args) ? _bs("p_$(t)_$shape") : _bf("p_$(t)_$shape", args...)
        g(x) = _bf(t, x)
        q(x) = _bf("q", x)
        push!(cells, (t, "argvar", h("argvar", A), g(A)))
        push!(cells, (t, "headvar", h("headvar", _bf("f", A)), g(A)))
        push!(cells, (t, "notlast", h("notlast", A), _bconj(g(A), q(A))))
        push!(cells, (t, "firstvar", h("firstvar"), _bconj(g(A), q(A))))
        push!(cells, (t, "singleton", h("singleton"), g(_bv(3))))
        push!(cells, (t, "int", h("int"), _bconj(g(_bg(3)), q(_bg(1)))))
        push!(cells, (t, "atom", h("atom"), _bconj(g(_bs("a")), q(_bg(1)))))
        push!(cells, (t, "compound", h("compound", Y), _bconj(g(_bf("f", Y)), q(Y))))
        push!(cells, (t, "nil", h("nil"), _bconj(g(mk_nil(_B)), q(_bg(1)))))
        push!(cells, (t, "float", h("float"), _bconj(g(_bg(1.5)), q(_bg(1)))))
        push!(cells, (t, "string", h("string"), _bconj(g(_bg("s")), q(_bg(1)))))
    end
    return cells
end

@testset "the type tests and var/nonvar compile as upstream decides, cell by cell (V6b)" begin
    cells = _bc_type_test_cells()
    ours = [_bc_kernel(_bclause(h, b)) for (_, _, h, b) in cells]
    # the class of each cell: inline exactly where upstream compiles inline, a call elsewhere
    for (k, (t, shape, _, _)) in enumerate(cells)
        inline = any(startswith("i_$(t)("), ours[k])
        called = any(c -> occursin("P:[$(join(Int.(codeunits(t)), ","))]/1", c), ours[k])
        if shape in _BC_TT_INLINE
            @test inline && !called
        else
            @test called && !inline
        end
    end
    @test length(cells) == length(_BC_TYPE_TESTS) * 11
    # a goal of the same NAME but arity 2 is a user predicate: a call, never a type test
    two = [(_bf("p2_$t", _bv(1)), _bf(t, _bv(1), _bs("a"))) for t in _BC_TYPE_TESTS]
    ours2 = [_bc_kernel(_bclause(h, b)) for (h, b) in two]
    for (k, t) in enumerate(_BC_TYPE_TESTS)
        @test any(c -> occursin("P:[$(join(Int.(codeunits(t)), ","))]/2", c), ours2[k])
        @test !any(startswith("i_$(t)("), ours2[k])
    end
    if _BC_SWIPL_BIN !== nothing
        theirs2 = _bc_swipl(["bc_case_show(($(_bc_text(h, b))))" for (h, b) in two])
        @test theirs2 == ours2
        theirs = _bc_swipl(["bc_case_show(($(_bc_text(h, b))))" for (_, _, h, b) in cells])
        @test length(theirs) == length(cells)
        bad = 0
        for k in eachindex(cells)
            k <= length(theirs) || break
            if ours[k] != theirs[k]
                bad += 1
                bad <= 5 && println(stderr, "  ", _bc_text(cells[k][3], cells[k][4]),
                    "\n    ours  ", ours[k], "\n    swipl ", theirs[k])
            end
        end
        @test bad == 0
    end
    # under `optimise` upstream compiles the fall-back cells to I_TRUE/I_FAIL (+ C_VAR): V9's, refused
    ld = LK.PL_local_data{_B}()
    ld.prolog_flag_optimise = true
    @test_throws LK.NotPortedError _bclause(_bs("po_int"), _bf("integer", _bg(3)); ld=ld)
    @test_throws LK.NotPortedError _bclause(
        _bs("po_first"), _bconj(_bf("atom", _bv(1)), _bf("q", _bv(1))); ld=ld
    )
    @test_throws LK.NotPortedError _bclause(_bs("po_var"), _bf("var", _bv(1)); ld=ld)
    @test !isempty(
        _bc_kernel(_bclause(_bf("po_inl", _bv(1)), _bf("integer", _bv(1)); ld=ld))
    )
end

# ── is/2 and the comparisons (V6c2): upstream's decision, cell by cell ──────────────────────────
# compileSubClause's ARITH_F branch (c:3474-3482): `is/2` tries compileSimpleAddition (c:3641-3688),
# whose one emission, `A_ADD_FC`, is V8's — refused there; every other shape, and every comparison,
# compiles as a CALL. The verdict is tied to swipl: compiled ⇒ the code is swipl's; refused ⇒
# swipl's code has `a_add_fc` (research probes v6a/p5, p11).
const _BC_ARITH_CELLS = [
    # (shape, head, body, refused?)
    (
        "result in the head",
        _bf("ia1", _bv(1), _bv(2)),
        _bf("is", _bv(2), _bf("-", _bv(1), _bg(1))),
        false
    ),
    ("NewVar is Var - 1", _bf("ia2", _bv(1)),
        _bconj(_bf("is", _bv(2), _bf("-", _bv(1), _bg(1))), _bf("q", _bv(2))), true),
    ("NewVar is Var + 1", _bf("ia3", _bv(1)),
        _bconj(_bf("is", _bv(2), _bf("+", _bv(1), _bg(1))), _bf("q", _bv(2))), true),
    ("NewVar is 1 + Var (swapped)", _bf("ia4", _bv(1)),
        _bconj(_bf("is", _bv(2), _bf("+", _bg(1), _bv(1))), _bf("q", _bv(2))), true),
    ("NewVar is 1 - Var (no swap for -)", _bf("ia5", _bv(1)),
        _bconj(_bf("is", _bv(2), _bf("-", _bg(1), _bv(1))), _bf("q", _bv(2))), false),
    ("not a portable constant", _bf("ia6", _bv(1)),
        _bconj(_bf("is", _bv(2), _bf("-", _bv(1), _bg(2147483648))), _bf("q", _bv(2))),
        false),
    ("the variable a first occurrence", _bs("ia7"),
        _bconj(_bf("is", _bv(2), _bf("+", _bv(1), _bg(1))), _bf("q", _bv(2), _bv(1))), false
    ),
    ("a float constant", _bf("ia8", _bv(1)),
        _bconj(_bf("is", _bv(2), _bf("+", _bv(1), _bg(1.0))), _bf("q", _bv(2))), false),
    ("another function", _bf("ia9", _bv(1)),
        _bconj(_bf("is", _bv(2), _bf("*", _bv(1), _bg(2))), _bf("q", _bv(2))), false),
    (
        "NewVar a void",
        _bf("ia10", _bv(1)),
        _bf("is", _bv(2), _bf("+", _bv(1), _bg(1))),
        false
    ),
    ("chained", _bf("ia11", _bv(1)),
        _bconj(_bf("is", _bv(2), _bf("+", _bv(1), _bg(1))),
            _bf("is", _bv(3), _bf("+", _bv(2), _bg(1))),
            _bf("q", _bv(3))), true),
    ("a comparison", _bf("ia12", _bv(1), _bv(2)), _bf("<", _bv(1), _bv(2)), false),
    ("=:=", _bf("ia13", _bv(1)), _bf("=:=", _bv(1), _bg(3)), false)
]

@testset "is/2 and the comparisons compile as upstream decides (V6c2)" begin
    ours = Union{Nothing, Vector{String}}[]
    for (shape, h, b, refused) in _BC_ARITH_CELLS
        got = try
            _bc_kernel(_bclause(h, b))
        catch e
            e isa LK.NotPortedError || rethrow()
            nothing
        end
        push!(ours, got)
        @test got !== nothing                                       # V8: A_ADD_FC compiles
        @test (got !== nothing && any(startswith("a_add_fc"), got)) == refused
    end
    # under `optimise` upstream compiles arithmetic inline (compileArith, memo Q-AR3): refused
    ld = LK.PL_local_data{_B}()
    ld.prolog_flag_optimise = true
    @test_throws LK.NotPortedError _bclause(
        _bf("po_ar", _bv(1)), _bf("<", _bv(1), _bg(3)); ld=ld
    )
    if _BC_SWIPL_BIN !== nothing
        theirs = _bc_swipl([
            "bc_case_show(($(_bc_text(h, b))))" for (_, h, b, _) in _BC_ARITH_CELLS
        ])
        @test length(theirs) == length(_BC_ARITH_CELLS)
        for (k, (shape, h, b, refused)) in enumerate(_BC_ARITH_CELLS)
            k <= length(theirs) || break
            @test any(startswith("a_add_fc"), theirs[k]) == refused   # the A_ADD_FC cells
            ours[k] == theirs[k] || println(stderr, "  ", shape, "\n    ours  ", ours[k],
                "\n    swipl ", theirs[k])
            @test ours[k] == theirs[k]
        end
    end
end

# ── the other goals compiled inline (V6b2): upstream's decision, cell by cell ────────────────────
# compileSubClause's O_COMPILE_IS chain (c:3488-3517) for `=/2`, `==/2`, `\\==/2`, `arg/3`,
# `\$call_continuation/1`, `\$shift/1` and `\$shift_for_copy/1`: each cell is (shape, head, body, the
# instruction upstream emits — or "" for a call). The kernel REFUSES exactly the inline cells (their
# instructions are V9's) and compiles every other cell. The verdict is tied to swipl: an inline cell's
# code has its instruction, and a call cell's code is identical to the kernel's.
_bcq(xs...) = _bf("q", xs...)
const _BC_IS_CELLS = [
    # =/2 (compileBodyUnify)
    ("= a void side", _bs("ub1"), _bconj(_bf("=", _bv(1), _bs("a")), _bs("q")), "i_true"),
    ("= X = X", _bs("ub2"), _bconj(_bcq(_bv(1)), _bf("=", _bv(1), _bv(1))), "i_true"),
    ("= two first variables", _bs("ub3"),
        _bconj(_bf("=", _bv(1), _bv(2)), _bcq(_bv(1), _bv(2))), "b_unify_ff"),
    ("= first = seen", _bs("ub4"),
        _bconj(_bcq(_bv(2)), _bf("=", _bv(1), _bv(2)), _bcq(_bv(1))), "b_unify_fv"),
    ("= seen = first", _bs("ub5"),
        _bconj(_bcq(_bv(1)), _bf("=", _bv(1), _bv(2)), _bcq(_bv(2))), "b_unify_vf"),
    ("= two seen variables", _bs("ub6"),
        _bconj(_bcq(_bv(1), _bv(2)), _bf("=", _bv(1), _bv(2))), "b_unify_vv"),
    (
        "= first = atom",
        _bs("ub7"),
        _bconj(_bf("=", _bv(1), _bs("a")), _bcq(_bv(1))),
        "b_unify_fc"
    ),
    (
        "= seen = atom",
        _bs("ub8"),
        _bconj(_bcq(_bv(1)), _bf("=", _bv(1), _bs("a"))),
        "b_unify_vc"
    ),
    ("= first = compound", _bs("ub9"),
        _bconj(_bf("=", _bv(1), _bf("f", _bv(2))), _bcq(_bv(1), _bv(2))), "b_unify_firstvar"
    ),
    ("= seen = compound", _bs("ub10"),
        _bconj(_bcq(_bv(1)), _bf("=", _bv(1), _bf("f", _bs("a")))), "b_unify_var"),
    ("= compound = seen", _bs("ub11"),
        _bconj(_bcq(_bv(1)), _bf("=", _bf("f", _bs("a")), _bv(1))), "b_unify_var"),
    (
        "= atom = seen",
        _bs("ub12"),
        _bconj(_bcq(_bv(1)), _bf("=", _bs("a"), _bv(1))),
        "b_unify_vc"
    ),
    ("= seen = 16777216", _bs("ub13"),
        _bconj(_bcq(_bv(1)), _bf("=", _bv(1), _bg(16777216))), "b_unify_var"),
    (
        "= term = term",
        _bf("ub14", _bv(1)),
        _bf("=", _bf("f", _bv(1)), _bf("f", _bs("a"))),
        ""
    ),
    ("= atom = atom", _bs("ub15"), _bf("=", _bs("a"), _bs("b")), ""),
    # ==/2 (compileBodyEQ)
    ("== a void side", _bs("eb1"), _bconj(_bf("==", _bv(1), _bs("a")), _bs("q")), ""),
    ("== two seen variables", _bs("eb2"),
        _bconj(_bcq(_bv(1), _bv(2)), _bf("==", _bv(1), _bv(2))), "b_eq_vv"),
    ("== seen == first", _bs("eb3"),
        _bconj(_bcq(_bv(1)), _bf("==", _bv(1), _bv(2)), _bcq(_bv(2))), "b_eq_vv"),
    ("== var == atom", _bf("eb4", _bv(1)), _bf("==", _bv(1), _bs("a")), "b_eq_vc"),
    ("== atom == var", _bf("eb5", _bv(1)), _bf("==", _bs("a"), _bv(1)), "b_eq_vc"),
    ("== var == []", _bf("eb6", _bv(1)), _bf("==", _bv(1), mk_nil(_B)), "b_eq_vc"),
    ("== var == 2^24-1", _bf("eb7", _bv(1)), _bf("==", _bv(1), _bg(16777215)), "b_eq_vc"),
    ("== var == 2^24", _bf("eb8", _bv(1)), _bf("==", _bv(1), _bg(16777216)), ""),
    ("== var == -2^24", _bf("eb9", _bv(1)), _bf("==", _bv(1), _bg(-16777216)), "b_eq_vc"),
    ("== var == -2^24-1", _bf("eb10", _bv(1)), _bf("==", _bv(1), _bg(-16777217)), ""),
    ("== var == 1.5", _bf("eb11", _bv(1)), _bf("==", _bv(1), _bg(1.5)), ""),
    ("== var == string", _bf("eb12", _bv(1)), _bf("==", _bv(1), _bg("s")), ""),
    ("== var == compound", _bf("eb13", _bv(1)), _bf("==", _bv(1), _bf("f", _bs("a"))), ""),
    ("== var == 2^60", _bf("eb14", _bv(1)), _bf("==", _bv(1), _bg(2^60)), ""),
    ("== atom == atom", _bs("eb15"), _bf("==", _bs("a"), _bs("b")), ""),
    # \==/2 (compileBodyNEQ)
    ("\\== a void side", _bs("nb1"), _bconj(_bf("\\==", _bv(1), _bs("a")), _bs("q")), ""),
    (
        "\\== two variables",
        _bf("nb2", _bv(1), _bv(2)),
        _bf("\\==", _bv(1), _bv(2)),
        "b_neq_vv"
    ),
    ("\\== var \\== atom", _bf("nb3", _bv(1)), _bf("\\==", _bv(1), _bs("a")), "b_neq_vc"),
    (
        "\\== var \\== compound",
        _bf("nb4", _bv(1)),
        _bf("\\==", _bv(1), _bf("f", _bs("a"))),
        ""
    ),
    ("\\== int \\== var", _bf("nb5", _bv(1)), _bf("\\==", _bg(3), _bv(1)), "b_neq_vc"),
    ("\\== var \\== 1.5", _bf("nb6", _bv(1)), _bf("\\==", _bv(1), _bg(1.5)), ""),
    # arg/3 (compileBodyArg3)
    ("arg Int, seen, first", _bf("ab1", _bv(1)),
        _bconj(_bf("arg", _bg(1), _bv(1), _bv(2)), _bcq(_bv(2))), "b_arg_cf"),
    ("arg seen, seen, first", _bf("ab2", _bv(3), _bv(1)),
        _bconj(_bf("arg", _bv(3), _bv(1), _bv(2)), _bcq(_bv(2))), "b_arg_vf"),
    (
        "arg the result seen",
        _bf("ab3", _bv(1), _bv(2)),
        _bf("arg", _bg(1), _bv(1), _bv(2)),
        ""
    ),
    ("arg the term first", _bs("ab4"),
        _bconj(_bf("arg", _bg(1), _bv(1), _bv(2)), _bcq(_bv(1), _bv(2))), ""),
    ("arg the index first", _bf("ab5", _bv(1)),
        _bconj(_bf("arg", _bv(3), _bv(1), _bv(2)), _bcq(_bv(3), _bv(2))), ""),
    ("arg the index an atom", _bf("ab6", _bv(1)),
        _bconj(_bf("arg", _bs("a"), _bv(1), _bv(2)), _bcq(_bv(2))), ""),
    ("arg the index past the tagged range", _bf("ab7", _bv(1)),
        _bconj(_bf("arg", _bg(2^57), _bv(1), _bv(2)), _bcq(_bv(2))), ""),
    ("arg the index -1", _bf("ab8", _bv(1)),
        _bconj(_bf("arg", _bg(-1), _bv(1), _bv(2)), _bcq(_bv(2))), "b_arg_cf"),
    ("arg the result void", _bf("ab9", _bv(1)), _bf("arg", _bg(1), _bv(1), _bv(2)), ""),
    ("arg the term a compound", _bs("ab10"),
        _bconj(_bf("arg", _bg(1), _bf("f", _bs("a")), _bv(2)), _bcq(_bv(2))), ""),
    # \$call_continuation/1, \$shift/1, \$shift_for_copy/1
    ("\$call_continuation seen", _bf("cc1", _bv(1)), _bf("\$call_continuation", _bv(1)),
        "i_callcont"),
    ("\$call_continuation an atom", _bs("cc2"), _bf("\$call_continuation", _bs("a")), ""),
    ("\$call_continuation first", _bs("cc3"),
        _bconj(_bf("\$call_continuation", _bv(1)), _bcq(_bv(1))), ""),
    ("\$shift seen", _bf("sh1", _bv(1)), _bf("\$shift", _bv(1)), "i_shift"),
    ("\$shift an atom", _bs("sh2"), _bf("\$shift", _bs("a")), ""),
    (
        "\$shift_for_copy seen",
        _bf("sh3", _bv(1)),
        _bf("\$shift_for_copy", _bv(1)),
        "i_shiftcp"
    ),
    ("\$shift_for_copy first", _bs("sh4"),
        _bconj(_bf("\$shift_for_copy", _bv(1)), _bcq(_bv(1))), "")
]

@testset "=, ==, \\==, arg/3, \$call_continuation, \$shift compile as upstream decides (V6b2)" begin
    ours = Union{Nothing, Vector{String}}[]
    refusals = String[]
    for (shape, h, b, instr) in _BC_IS_CELLS
        got = try
            _bc_kernel(_bclause(h, b))
        catch e
            e isa LK.NotPortedError || rethrow()
            push!(refusals, e.what)
            nothing
        end
        push!(ours, got)
        (got === nothing) == !isempty(instr) ||
            println(stderr, "  ", shape, ": ", got === nothing ? "refused" : "compiled")
        @test (got === nothing) == !isempty(instr)             # refused exactly where inline
    end
    # every emission of every compiler is reached: each instruction names a refusal
    for i in
        ("I_TRUE for =/2", "I_TRUE for X = X", "B_UNIFY_FF", "B_UNIFY_FV", "B_UNIFY_VF",
        "B_UNIFY_VV", "B_UNIFY_FC", "B_UNIFY_VC", "B_UNIFY_FIRSTVAR", "B_UNIFY_VAR ",
        "B_EQ_VV",
        "B_EQ_VC", "B_NEQ_VV", "B_NEQ_VC", "B_ARG_CF", "B_ARG_VF", "I_CALLCONT", "I_SHIFT ",
        "I_SHIFTCP")
        @test any(r -> occursin(i, r), refusals)
    end
    # a goal of the same NAME but another arity is a user predicate: a call, never compiled inline
    for (h, b, n, a) in (
        (_bs("ar1"), _bf("=", _bs("a")), "=", 1),
        (_bf("ar2", _bv(1)), _bf("=", _bv(1), _bs("a"), _bs("b")), "=", 3),
        (_bf("ar3", _bv(1)), _bf("==", _bv(1)), "==", 1),
        (_bf("ar4", _bv(1)), _bf("arg", _bg(1), _bv(1)), "arg", 2),
        (_bf("ar5", _bv(1)), _bf("\$shift", _bv(1), _bs("a")), "\$shift", 2)
    )
        got = _bc_kernel(_bclause(h, b))
        @test any(c -> occursin("P:[$(join(Int.(codeunits(n)), ","))]/$a", c), got)
    end
    # under `optimise` upstream compiles ==/\\== on a void, or on a first occurrence, to
    # I_TRUE/I_FAIL: V9's, refused
    ld = LK.PL_local_data{_B}()
    ld.prolog_flag_optimise = true
    for (h, b) in (
        (_bs("po_eq1"), _bf("==", _bv(1), _bs("a"))),
        (_bs("po_neq1"), _bf("\\==", _bv(1), _bs("a"))),
        (_bs("po_eq2"), _bconj(_bcq(_bv(1)), _bf("==", _bv(1), _bv(2)), _bcq(_bv(2)))),
        (_bs("po_neq2"), _bconj(_bcq(_bv(1)), _bf("\\==", _bv(1), _bv(2)), _bcq(_bv(2))))
    )
        @test_throws LK.NotPortedError _bclause(h, b; ld=ld)
    end
    @test !isempty(
        _bc_kernel(_bclause(_bs("po_eq3"), _bf("==", _bs("a"), _bs("b")); ld=ld))
    )
    # without `portable_vmi` every tagged integer is a portable constant
    ld2 = LK.PL_local_data{_B}()
    ld2.prolog_flag_portable_vmi = false
    @test_throws LK.NotPortedError _bclause(
        _bf("pv1", _bv(1)), _bf("==", _bv(1), _bg(16777216)); ld=ld2
    )
    # a unification moved into the head (`optimise_unify`, swipl's default; NOT PORTED, V9): the
    # kernel refuses it, and swipl compiles it as HEAD code — no b_unify_*, no call (probed)
    moved = [
        (_bf("um1", _bv(1)), _bconj(_bf("=", _bv(1), _bf("f", _bs("a"))), _bcq(_bv(1)))),
        (_bf("um2", _bv(1)), _bconj(_bf("=", _bv(1), _bs("a")), _bcq(_bv(1))))
    ]
    for (h, b) in moved
        @test_throws LK.NotPortedError _bclause(h, b)
    end
    if _BC_SWIPL_BIN !== nothing
        theirs_m = _bc_swipl(["bc_case_show(($(_bc_text(h, b))))" for (h, b) in moved])
        @test length(theirs_m) == length(moved)
        for t in theirs_m
            @test !any(startswith("b_unify"), t) && any(startswith("h_"), t)
            @test !any(c -> occursin("P:[61]/2", c), t)                  # no call of =/2
        end
    end
    if _BC_SWIPL_BIN !== nothing
        theirs = _bc_swipl([
            "bc_case_show(($(_bc_text(h, b))))" for (_, h, b, _) in _BC_IS_CELLS
        ])
        @test length(theirs) == length(_BC_IS_CELLS)
        for (k, (shape, h, b, instr)) in enumerate(_BC_IS_CELLS)
            k <= length(theirs) || break
            if isempty(instr)                                       # a call: swipl's own code
                ours[k] == theirs[k] ||
                    println(stderr, "  ", shape, "\n    ours  ", ours[k],
                        "\n    swipl ", theirs[k])
                @test ours[k] == theirs[k]
            else                                                    # inline: swipl emits it
                any(startswith(instr), theirs[k]) ||
                    println(stderr, "  ", shape, ": swipl ", theirs[k])
                @test any(startswith(instr), theirs[k])
            end
        end
    end
end

@testset "COMMIT_CLAUSE: set exactly when the body starts with `!` (c:2165)" begin
    commit(h, b) = _bclause(h, b).flags & LK.COMMIT_CLAUSE != 0
    @test commit(_bs("pc1"), _bconj(_bs("!"), _bf("q", _bv(1))))
    @test commit(_bs("pc4"), _bs("!"))
    @test !commit(_bs("pc2"), _bconj(_bf("q", _bv(1)), _bs("!")))
    @test !commit(_bs("pc3"), _bconj(_bs("q"), _bs("!"), _bs("r")))
    @test !commit(_bc_qsort_cut()...)                       # X =< Y comes first
    @test !commit(_bs("pc5"), _bf("q", _bs("!")))           # `!` as DATA is no cut
end

@testset "what is still refused (V2's interim; V6b, V6b2: the inline compilers decide), and swipl's type_error(callable, Body)" begin
    p = _bs("pr")
    for body in (
        _bf(";", _bs("a"), _bs("b")), _bf("->", _bs("a"), _bs("b")), _bf("\\+", _bs("a")),
        _bf(":", _bs("m"), _bs("g")), _bf("@", _bs("g"), _bs("m")), _bf("\$", _bs("g")),
        _bconj(_bf("q", _bv(1)), _bv(1)),                       # a variable goal (meta-call)
        _bf("=", _bv(1), _bs("a")),                            # a void side: I_TRUE (V9)
        _bconj(_bs("q"), _bs("true")), _bs("fail"),
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
    mf = LK.lookupProcedure(_bs("mf"), 0, user)
    mf.definition.flags |= LK.P_MULTIFILE
    @test_throws LK.NotPortedError LK.compileClause(gd, _BLD, _bs("mf"), _bs("q"), mf, user)
    @test LK.compileClause(gd, _BLD, _bs("mf"), nothing, mf, user).flags & LK.UNIT_CLAUSE !=
        0
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
    po = LK.lookupProcedure(lk_sym(O, :po), 0, user)
    v = lk_gnd(O, true)
    cl = LK.compileClause(
        gd, LK.PL_local_data{O}(), lk_sym(O, :po), mk_expr(O, O[lk_sym(O, :q), v]), po, user
    )
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
    rule = LK.compileClause(
        db.gd, db.ld, _bf("cr", _bv(1)), _bf("q", _bv(1)), pr.proc, user
    )
    LK.assertDefinition!(db.gd, pr.def, rule, LK.CL_END)
    @test length(ix_clause(pr, _bf("cr", _bv(5)))) == 1         # the fact, not the rule
    @test length(ix_retract!(pr, _bf("cr", _bv(5)))) == 1       # retracts the fact only
    @test isempty(ix_retract!(pr, _bf("cr", _bv(5))))           # the rule is not `cr(_) :- true`
    ix_retractall!(pr, _bf("cr", _bv(5)))                        # retractall takes rules too
    @test LK.hasClausesDefinition(db.gd, pr.def) === nothing
end
