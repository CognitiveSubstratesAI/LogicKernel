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
# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "code_testlib.jl"))
using Random

const _B = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
"The database the clauses of this file are compiled in (its global data)."
const _BGD = LK.PL_global_data{_B}()
const _BLD = LK.PL_local_data{_B}(_BGD)          # the compiler reads its flags
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
    if k == LK.CA1_VAR || k == LK.CA1_FVAR || k == LK.CA1_CHP
        return string(LK.VARNUM(w))
    elseif k == LK.CA1_INTEGER
        return if op == LK.H_VOID_N || op == LK.C_VAR_N                 # a count, or a literal
            string(Int(w))
        elseif op == LK.I_CALLN                                          # swipl writes the count as `i:N`
            "i:" * string(Int(w))
        elseif op == LK.H_SMALLINT || op == LK.B_SMALLINT || op == LK.L_SMALLINT
            _hlit(lk_gnd(_B, LK.valInt(w)))                             # the tagged word itself (L1d step 4)
        elseif op == LK.A_ADD_FC
            _hlit(lk_gnd(_B, reinterpret(Int64, w)))                    # the integer itself (L1d step 4)
        else
            _hlit(lits[w])
        end
    elseif k == LK.CA1_DATA && (op == LK.H_ATOM || op == LK.B_ATOM || op == LK.L_ATOM)
        return _hlit(lits[LK.atom_literal(w)])                          # packed (L1b C6b)
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
bc_op(_, chp, X, S) :- !, format(string(S), "~w", [X]).
bc_op(_, jump, X, S) :- !, format(string(S), "~w", [X]).
bc_op(h_void_n, integer, X, S) :- !, format(string(S), "~w", [X]).
bc_op(c_var_n, integer, X, S) :- !, format(string(S), "~w", [X]).
bc_op(_, lproc, F/A, S) :- !, atom_codes(F, C), format(string(S), "P:~w/~d", [C, A]).
bc_op(N, _, X, S) :- hc_op(N, X, S).
bc_case_show(Cl) :- assertz(Cl, Ref), bc_show(Ref).
% clause/2 of the clause as swipl decompiles it, against the kernel's decompiled clause Ours
bc_decomp(Cl, Ours) :-
    assertz(Cl, Ref), clause(H, B, Ref),
    (   (H :- B) =@= Ours -> writeln(same)
    ;   writeln(differs), write_canonical((H :- B)), nl
    ).
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

const _BC_SWIPL_BIN = (
    get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
)
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
    # under `optimise` the fall-back cells compile to I_TRUE/I_FAIL (`always`), a first
    # occurrence's followed by its C_VAR (c:4691-4697; since V9a): every cell, compared whole with
    # swipl's code under the flag
    ld = LK.PL_local_data{_B}(_BGD)
    ld.prolog_flag_optimise = true
    ours_o = [_bc_kernel(_bclause(h, b; ld=ld)) for (_, _, h, b) in cells]
    @test any(c -> any(startswith("i_true"), c), ours_o)
    @test any(c -> any(startswith("i_fail"), c), ours_o)
    @test any(c -> any(startswith("c_var"), c), ours_o)
    if _BC_SWIPL_BIN !== nothing
        theirs_o = _bc_swipl(
            ["bc_case_show(($(_bc_text(h, b))))" for (_, _, h, b) in cells];
            prelude="set_prolog_flag(optimise, true)"
        )
        @test length(theirs_o) == length(cells)
        bad = 0
        for k in eachindex(cells)
            k <= length(theirs_o) || break
            if ours_o[k] != theirs_o[k]
                bad += 1
                bad <= 5 && println(stderr, "  -O ", _bc_text(cells[k][3], cells[k][4]),
                    "\n    ours  ", ours_o[k], "\n    swipl ", theirs_o[k])
            end
        end
        @test bad == 0
    end
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
    ld = LK.PL_local_data{_B}(_BGD)
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
    # skippedVar marks a first occurrence seen: the later Y is no first occurrence (V9a; probe sk1)
    (
        "= first = void",
        _bs("ub16"),
        _bconj(_bf("=", _bv(1), _bv(9)), _bcq(_bv(1))),
        "i_true"
    ),
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

# the cells still refused: their instructions are V9's (`B_ARG_*`, `I_CALLCONT`, `I_SHIFT`,
# `I_SHIFTCP`). Since V9a every =, == and \== cell compiles, and its code is swipl's.
const _BC_IS_REFUSED = ("b_arg_cf", "b_arg_vf", "i_callcont", "i_shift", "i_shiftcp")

@testset "=, ==, \\==, arg/3, \$call_continuation, \$shift compile as upstream decides (V6b2, V9a)" begin
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
        refused = instr in _BC_IS_REFUSED
        (got === nothing) == refused ||
            println(stderr, "  ", shape, ": ", got === nothing ? "refused" : "compiled")
        @test (got === nothing) == refused                    # refused exactly where V9's
        if got !== nothing && !isempty(instr)                  # inline: the decision's instruction
            @test any(startswith(instr), got)
        end
    end
    # every emission of the compilers still refusing is reached: each names a refusal
    for i in ("B_ARG_CF", "B_ARG_VF", "I_CALLCONT", "I_SHIFT ", "I_SHIFTCP")
        @test any(r -> occursin(i, r), refusals)
    end
    # every instruction of the family is emitted by some cell (C_VAR: eb3; B_UNIFY_EXIT: ub9-ub11)
    for i in (
        "i_true", "b_unify_ff", "b_unify_fv", "b_unify_vf", "b_unify_vv", "b_unify_fc",
        "b_unify_vc", "b_unify_firstvar", "b_unify_var(", "b_unify_exit", "b_eq_vv",
        "b_eq_vc",
        "b_neq_vv", "b_neq_vc", "c_var"
    )
        @test any(c -> c !== nothing && any(startswith(i), c), ours)
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
    # under `optimise` ==/\== on a void, or on a first occurrence, compile to I_TRUE/I_FAIL after
    # the skipped variables' C_VAR (since V9a), compared whole with swipl's under the flag
    ld = LK.PL_local_data{_B}(_BGD)
    ld.prolog_flag_optimise = true
    opt = [
        (_bs("po_eq1"), _bf("==", _bv(1), _bs("a"))),
        (_bs("po_neq1"), _bf("\\==", _bv(1), _bs("a"))),
        (_bs("po_eq2"), _bconj(_bcq(_bv(1)), _bf("==", _bv(1), _bv(2)), _bcq(_bv(2)))),
        (_bs("po_neq2"), _bconj(_bcq(_bv(1)), _bf("\\==", _bv(1), _bv(2)), _bcq(_bv(2)))),
        (_bs("po_eq3"), _bf("==", _bs("a"), _bs("b")))
    ]
    ours_o = [_bc_kernel(_bclause(h, b; ld=ld)) for (h, b) in opt]
    @test any(startswith("i_fail"), ours_o[1]) && any(startswith("i_true"), ours_o[2])
    # without `portable_vmi` every tagged integer is a portable constant
    ld2 = LK.PL_local_data{_B}(_BGD)
    ld2.prolog_flag_portable_vmi = false
    @test any(
        startswith("b_eq_vc"),
        _bc_kernel(_bclause(_bf("pv1", _bv(1)), _bf("==", _bv(1), _bg(16777216)); ld=ld2))
    )
    # the unifications moved into the head: the testset after this one (V9b)
    if _BC_SWIPL_BIN !== nothing
        theirs_o = _bc_swipl(
            ["bc_case_show(($(_bc_text(h, b))))" for (h, b) in opt];
            prelude="set_prolog_flag(optimise, true)"
        )
        @test theirs_o == ours_o
        theirs = _bc_swipl([
            "bc_case_show(($(_bc_text(h, b))))" for (_, h, b, _) in _BC_IS_CELLS
        ])
        @test length(theirs) == length(_BC_IS_CELLS)
        for (k, (shape, h, b, instr)) in enumerate(_BC_IS_CELLS)
            k <= length(theirs) || break
            if ours[k] !== nothing                                  # compiled: swipl's own code
                ours[k] == theirs[k] ||
                    println(stderr, "  ", shape, "\n    ours  ", ours[k],
                        "\n    swipl ", theirs[k])
                @test ours[k] == theirs[k]
            else                                                    # refused: swipl emits it
                any(startswith(instr), theirs[k]) ||
                    println(stderr, "  ", shape, ": swipl ", theirs[k])
                @test any(startswith(instr), theirs[k])
            end
        end
    end
end

# ── the unifications moved into the head (V9b; user, 2026-10-06) ───────────────────────────────
# `optimise_unify` (swipl's default) moves a leading `ArgVar = Term` into the head; the cells are the
# research memo's probes (the workspace's docs/research/v9-inline-unification/, § D). swipl compiles
# each through `assertz` into a FRESH predicate, which compiles as static code (assert_term compiles
# before it marks the predicate dynamic, pl-comp.c:4932, 5028-5036), as the kernel's compileClause
# does on a predicate that is not dynamic.
const _BC_MOVE_CELLS = let X = _bv(1), Y = _bv(2), T = _bv(3), G = _bv(4)
    [
        ("compound", _bf("mv1", X), _bf("=", X, _bf("f", _bs("a")))),
        ("then a use", _bf("um1", X), _bconj(_bf("=", X, _bf("f", _bs("a"))), _bcq(X))),
        ("atom", _bf("um2", X), _bconj(_bf("=", X, _bs("a")), _bcq(X))),
        ("var = var: no move", _bf("mv2", X), _bconj(_bf("=", X, Y), _bcq(Y))),
        ("var = arg: no move", _bf("mv3", X), _bconj(_bf("=", Y, X), _bcq(Y))),
        ("after a goal: no move", _bf("mv4", X), _bconj(_bs("q"), _bf("=", X, _bs("a")))),
        ("a non-argument = does not stop it", _bf("mv6", X),
            _bconj(_bf("=", X, _bs("a")), _bf("=", Y, _bs("b")), _bcq(Y))),
        ("no head argument", _bs("mv7"), _bconj(_bf("=", X, _bf("f", Y)), _bcq(X, Y))),
        ("cut first: no move", _bf("mv12", X), _bconj(_bs("!"), _bf("=", X, _bs("a")))),
        ("then a cut", _bf("mv13", X), _bconj(_bf("=", X, _bs("a")), _bs("!"), _bcq(X))),
        ("reversed", _bf("mv15", X), _bconj(_bf("=", _bs("a"), X), _bcq(X))),
        ("a repeated head argument", _bf("mv16", X, X), _bf("=", X, _bs("a"))),
        (
            "the second = stays",
            _bf("mv17", X),
            _bconj(_bf("=", X, _bs("a")), _bf("=", X, _bs("b")))
        ),
        ("true is skipped", _bf("mv19", X), _bconj(_bs("true"), _bf("=", X, _bs("a")))),
        ("the term holds the argument", _bf("mv20", X), _bf("=", X, _bf("f", X))),
        (
            "a nested head variable: no move",
            _bf("mv22", _bf("f", X)),
            _bf("=", X, _bs("a"))
        ),
        ("a float", _bf("mv23", X), _bconj(_bf("=", X, _bg(1.5)), _bcq(X))),
        ("then ==", _bf("mv24", X), _bconj(_bf("=", X, _bs("a")), _bf("==", X, _bs("a")))),
        (
            "through another argument",
            _bf("mv25", X, Y),
            _bconj(_bf("=", Y, X), _bf("=", X, _bf("f", Y)))
        ),
        (
            "two arguments",
            _bf("mv29", X, Y),
            _bconj(_bf("=", X, _bs("a")), _bf("=", Y, _bs("b")))
        ),
        ("two, out of order", _bf("mv30", X, Y),
            _bconj(_bf("=", Y, _bs("b")), _bf("=", X, _bs("a")), _bcq(X, Y))),
        ("past the tagged range", _bf("mv35", X), _bf("=", X, _bg(3000000000))),
        ("a list", _bf("mv42", X), _bconj(_bf("=", X, _bf("[|]", _bs("a"), T)), _bcq(T))),
        ("a string", _bf("mv43", X), _bconj(_bf("=", X, _bg("str")), _bcq(X))),
        (
            "a void first",
            _bf("mv58", X),
            _bconj(_bf("=", X, _bv(9)), _bf("=", X, _bs("a")))
        ),
        ("past var = var", _bf("mv59", X),
            _bconj(_bf("=", X, Y), _bf("=", Y, _bs("b")), _bf("=", X, _bs("a")))),
        (
            "past another =",
            _bf("mv67", X),
            _bconj(_bf("=", G, _bs("true")), _bf("=", X, _bs("a")), _bcq(G))
        )
    ]
end

@testset "the unifications moved into the head compile as swipl's (V9b)" begin
    ours = [_bc_kernel(_bclause(h, b)) for (_, h, b) in _BC_MOVE_CELLS]
    named(n) = findfirst(c -> c[1] == n, _BC_MOVE_CELLS)
    @test !any(startswith("b_unify"), ours[named("compound")])        # head code only
    @test any(startswith("b_unify"), ours[named("var = var: no move")]) ||
        any(startswith("i_true"), ours[named("var = var: no move")])
    # optimise_unify false: what swipl compiles under the flag false (V9a's code)
    ldf = LK.PL_local_data{_B}(_BGD)
    ldf.prolog_flag_optimise_unify = false
    oursf = [_bc_kernel(_bclause(h, b; ld=ldf)) for (_, h, b) in _BC_MOVE_CELLS]
    @test any(startswith("b_unify"), oursf[named("compound")])
    # a dynamic predicate never moves (pl-comp.c:2019): its clause compiles as under the flag false
    gd = LK.PL_global_data{_B}()
    user = LK.MODULE_user(gd)
    dp = LK.lookupProcedure(_bs("dm1"), 1, user)
    LK.setDynamicDefinition!(dp.definition, true)
    dyn = _bc_kernel(
        LK.compileClause(gd, _BLD, _bf("dm1", _bv(1)),
            _bconj(_bf("=", _bv(1), _bf("f", _bs("a"))), _bcq(_bv(1))), dp, user)
    )
    @test any(startswith("b_unify_var"), dyn)
    # CL_HEAD_TERMS where upstream sets it: at EVERY moved unification (c:3122, since the fix of
    # swipl-devel#1540 in 27dd7c3 — before, a later use through B_EQ_VC, or no later use, left it
    # unset), and at a body use, a head H_VAR and var-var as before
    hflag(n) =
        (
            _bclause(_BC_MOVE_CELLS[named(n)][2], _BC_MOVE_CELLS[named(n)][3]).flags &
            LK.CL_HEAD_TERMS
        ) != 0
    @test hflag("then a use")                               # q(X): B_VAR0 of the moved argument
    @test hflag("a repeated head argument")                 # the second X: H_VAR
    @test hflag("the term holds the argument")              # f(X): H_VAR inside the moved term
    @test hflag("then ==")                                  # X == a: B_EQ_VC — set by the move
    @test hflag("compound")                                 # nothing uses X — set by the move
    @test !hflag("var = var: no move")                      # nothing moved, no head term
    # E1: a VARIABLE goal is a call and ENDS the run (upstream defect, fixed in 699e53c: it did
    # not). Such a clause is refused (the meta-call, V9), so this is pinned in its head code, as
    # swipl compiles it: nothing moved, the code starts with I_ENTER
    e1g = LK.PL_global_data{_B}()
    e1u = LK.MODULE_user(e1g)
    e1p = LK.lookupProcedure(_bs("c18"), 2, e1u)
    ci = LK.compileInfo{_B}(e1g, 2, e1u, e1p)
    ci.head_unify = true
    LK._compile_clause_head!(
        e1g, ci, _bf("c18", _bv(1), _bv(2)), _bconj(_bv(2), _bf("=", _bv(1), _bs("a")))
    )
    @test LK.codeTable(ci.codes[1]).name === :I_ENTER       # X = a is NOT moved past the goal G
    # …and upstream's own case (tests/core_lang/test_moved_ubody.pl `var_goal`, added with the
    # fix): var_goal(X) :- G = var(X), G, X = a — `X = a` stays behind the call of G
    vgp = LK.lookupProcedure(_bs("var_goal"), 1, e1u)
    vgci = LK.compileInfo{_B}(e1g, 1, e1u, vgp)
    vgci.head_unify = true
    LK._compile_clause_head!(
        e1g,
        vgci,
        _bf("var_goal", _bv(1)),
        _bconj(_bf("=", _bv(2), _bf("var", _bv(1))), _bv(2), _bf("=", _bv(1), _bs("a")))
    )
    @test LK.codeTable(vgci.codes[1]).name === :I_ENTER
    # …and a goal variable met for the FIRST time (the analysis' other variable branch; swipl
    # itself refuses to assert this clause — type_error(callable, _) — so only the kernel's
    # analysis is pinned)
    fgp = LK.lookupProcedure(_bs("c19"), 1, e1u)
    fgci = LK.compileInfo{_B}(e1g, 1, e1u, fgp)
    fgci.head_unify = true
    LK._compile_clause_head!(
        e1g, fgci, _bf("c19", _bv(1)), _bconj(_bv(2), _bf("=", _bv(1), _bs("a")))
    )
    @test LK.codeTable(fgci.codes[1]).name === :I_ENTER
    # `;` and `\+` end the run (c:1007-1011, 1047): pinned in the head code too, as the compiler
    # refuses those clauses until V9 — nothing moved, so the void head argument emits nothing and
    # the code starts with I_ENTER (a move would start it with H_ATOM)
    function headop(name, body)
        hp = LK.lookupProcedure(_bs(name), 1, e1u)
        hci = LK.compileInfo{_B}(e1g, 1, e1u, hp)
        hci.head_unify = true
        LK._compile_clause_head!(e1g, hci, _bf(name, _bv(1)), body)
        return LK.codeTable(hci.codes[1]).name
    end
    # the branches hold unifications that would move if the run went on into them (memo c26, c46)
    @test headop(
        "c26b", _bf(";", _bf("=", _bv(1), _bs("a")), _bf("=", _bv(1), _bs("b")))
    ) ===
        :I_ENTER
    @test headop("c46b", _bf("\\+", _bf("=", _bv(1), _bs("a")))) === :I_ENTER
    if _BC_SWIPL_BIN !== nothing
        shows = ["bc_case_show(($(_bc_text(h, b))))" for (_, h, b) in _BC_MOVE_CELLS]
        theirs = _bc_swipl(shows)
        @test length(theirs) == length(_BC_MOVE_CELLS)
        bad = 0
        for k in eachindex(_BC_MOVE_CELLS)
            k <= length(theirs) || break
            if ours[k] != theirs[k]
                bad += 1
                println(stderr, "  move cell ", _BC_MOVE_CELLS[k][1], "\n    ours  ",
                    ours[k],
                    "\n    swipl ", theirs[k])
            end
        end
        @test bad == 0
        @test _bc_swipl(shows; prelude="set_prolog_flag(optimise_unify, false)") == oursf
        @test _bc_swipl([
            "(dynamic(dm1/1), bc_case_show((dm1(X) :- X = f(a), q(X))))"
        ])[1] == dyn
        e1 = _bc_swipl(["bc_case_show((c18(X, G) :- G, X = a))"])[1]
        @test e1[1] == "i_enter"                            # swipl does not move it either (E1)
        vg = _bc_swipl(["bc_case_show((var_goal(X) :- G = var(X), G, X = a))"])[1]
        @test vg[1] == "i_enter"
        ends = _bc_swipl([
            "bc_case_show((c26b(X) :- (X = a ; X = b)))",
            "bc_case_show((c46b(X) :- \\+ X = a))"
        ])
        @test all(c -> c[1] == "i_enter", ends)             # swipl moves neither
    end
end

# ── V9d: disjunctions ───────────────────────────────────────────────────────────────────────────
# `;` and `|` compile to `C_OR <A> C_JMP <B>`, with `C_VAR`/`C_VAR_N` for the variables one branch
# leaves unset (pl-comp.c `compileBody`, `balanceVars`). Pinned cells, then random bodies of `,`
# and `;` over plain goals, cuts and the goals compiled inline — the ones that set variables.
const _BC_OR_CELLS =
    let X = _bv(1), Y = _bv(2), A = _bv(3), B = _bv(4), C = _bv(5), D = _bv(6)

        _or(a, b) = _bf(";", a, b)
        [
            ("a ; b", _bs("d1"), _or(_bs("a"), _bs("b"))),
            ("a | b", _bs("d2"), _bf("|", _bs("a"), _bs("b"))),
            ("not last", _bs("d3"), _bconj(_or(_bs("a"), _bs("b")), _bs("c"))),
            ("three branches", _bs("d4"), _or(_bs("a"), _or(_bs("b"), _bs("c")))),
            ("left-nested", _bs("d5"), _or(_or(_bs("a"), _bs("b")), _bs("c"))),
            ("a conjunction in a branch", _bs("d6"),
                _or(_bconj(_bs("a"), _bs("b")), _bconj(_bs("c"), _bs("d")))),
            ("one variable to balance", _bf("d7", X),
                _bconj(_or(_bf("q", X, Y), _bf("r", X)), _bf("s", Y))),
            ("balance in the second branch", _bf("d8", X),
                _bconj(_or(_bf("r", X), _bf("q", X, Y)), _bf("s", Y))),
            ("both branches set it", _bf("d9", X),
                _bconj(_or(_bf("q", X, Y), _bf("r", Y)), _bf("s", Y))),
            ("a run of four", _bs("d10"),
                _bconj(_or(_bf("q", A, B, C, D), _bs("true")), _bf("r", A, B, C, D))),
            ("a run of three", _bs("d11"),
                _bconj(_or(_bs("a"), _bf("q", A, B, C)), _bf("r", A, B, C))),
            ("two apart", _bs("d12"),
                _bconj(_or(_bconj(_bf("q", A), _bf("z", B), _bf("s", C)), _bf("t", B)),
                    _bf("r", A, B, C))),
            ("a cut in a branch", _bs("d13"), _or(_bconj(_bs("a"), _bs("!")), _bs("b"))),
            ("inline goals", _bf("d14", X),
                _or(_bf("=", X, _bs("a")), _or(_bf("==", X, _bs("b")), _bf("var", X)))),
            ("a first variable unified in one branch", _bs("d15"),
                _bconj(_or(_bf("=", Y, _bs("a")), _bs("true")), _bf("q", Y))),
            ("true ; fail", _bs("d16"), _or(_bs("true"), _bs("fail"))),
            ("arithmetic in a branch", _bf("d17", X, Y),
                _or(_bf("is", Y, _bf("+", X, _bg(1))), _bf("=", Y, _bg(0)))),
            ("a variable only inside", _bs("d18"),
                _or(_bconj(_bf("q", A), _bf("r", A)), _bf("s", B, B))),
            ("after a disjunction that set nothing", _bf("d19", X),
                _bconj(_or(_bs("a"), _bs("b")), _bf("q", X, Y), _bf("r", Y))),
            ("a disjunction in a disjunction's branch", _bf("d20", X),
                _bconj(
                    _or(_bconj(_or(_bf("q", A), _bf("r", B)), _bf("s", A, B)), _bf("t", C)),
                    _bf("u", A, B, C))),
            # `$/1` and `$/0` (since V9f): C_DET <A> C_DETTRUE C_JMP C_DETFALSE, and I_DET
            ("\$ a goal", _bf("d21", X), _bf("\$", _bf("q", X))),
            ("\$ sets a variable", _bf("d22", X),
                _bconj(_bf("\$", _bf("q", X, Y)), _bf("r", Y))),
            ("\$ the atom", _bs("d23"), _bconj(_bs("a"), _bs("\$"), _bs("b"))),
            ("\$ nested", _bf("d24", X), _bf("\$", _bf("\$", _bf("q", X)))),
            ("\$ with a cut", _bs("d25"), _bf("\$", _bconj(_bs("a"), _bs("!")))),
            ("\$ in a branch", _bf("d26", X),
                _bconj(_or(_bf("\$", _bf("q", X, Y)), _bf("r", X)), _bf("s", Y))),
            ("\\+ \$", _bs("d27"), _bf("\\+", _bf("\$", _bs("a")))),
            ("\$ the atom last", _bs("d28"), _bconj(_bs("a"), _bs("\$"))),
            ("\$ two goals, two variables", _bf("d29", X),
                _bconj(_bf("\$", _bconj(_bf("q", A), _bf("r", A, B))), _bf("s", B, C)))
        ]
    end

"A random body of `,` and `;` over plain goals, `!`, `true`, `fail` and inline goals on `pool`'s variables."
function _bcorbody(g::_BcGen, pool::Vector{_B}, depth::Int)::_B
    r = rand(g.rng)
    if depth < 4 && r < 0.3
        return _bf(";", _bcorbody(g, pool, depth + 1), _bcorbody(g, pool, depth + 1))
    elseif depth < 4 && r < 0.55
        return _bf(",", _bcorbody(g, pool, depth + 1), _bcorbody(g, pool, depth + 1))
    end
    v() = rand(g.rng, pool)
    r = rand(g.rng, 1:12)
    r == 1 && return _bs("!")
    r == 2 && return _bs(rand(g.rng, ("true", "fail")))
    r == 3 && return _bf("=", v(), rand(g.rng, Bool) ? v() : _bcconst(g))
    r == 4 &&
        return _bf(rand(g.rng, ("==", "\\==")), v(), rand(g.rng, Bool) ? v() : _bs("a"))
    r == 5 && return _bf(rand(g.rng, ("var", "nonvar", "atom", "integer")), v())
    r == 6 && return _bf("is", v(), _bf("+", v(), _bg(1)))
    ar = rand(g.rng, 0:3)
    name = "bg$(rand(g.rng, 0:5))"
    return ar == 0 ? _bs(name) : _be(name, [v() for _ in 1:ar])
end

"A random rule clause `bo<k>(…) :- Body`, the body a `;` at the top or below a `,`."
function _bcorclause(g::_BcGen, k::Int)::Tuple{_B, _B}
    pool = _B[_bcfresh!(g) for _ in 1:rand(g.rng, 2:6)]
    har = rand(g.rng, 0:3)
    head = har == 0 ? _bs("bo$k") : _be("bo$k", [rand(g.rng, pool) for _ in 1:har])
    body = _bf(";", _bcorbody(g, pool, 1), _bcorbody(g, pool, 1))
    r = rand(g.rng)
    if r < 0.3
        body = _bf(",", body, _bcorbody(g, pool, 2))
    elseif r < 0.5
        body = _bf(",", _bcorbody(g, pool, 2), body)
    end
    return (head, body)
end

"A clause text with its variables renamed `A`, `B`, … in order of first occurrence (`_` stays)."
function _bnorm(text::String)::String
    names = Dict{String, String}()
    return replace(
        text, r"V\d+" => v -> get!(() -> string('A' + length(names)), names, String(v))
    )
end

# The decompiler's own cells: the goals compiled inline, whose other side is head-mode code, and
# every argument kind — compiled with `optimise_unify` false, as the disjunction cells are.
const _BC_DEC_CELLS = let X = _bv(1), Y = _bv(2), Z = _bv(3), T = _bv(4)
    [
        ("unify with a compound", _bf("e1", X),
            _bconj(_bf("=", X, _bf("f", Y, _bcons(_bs("a"), T), _bg("s"), _bg(1.5))),
                _bf("q", Y, T))),
        (
            "unify: voids in the term",             # H_VOID_N in the middle, then a slot
            _bf("e2", X),
            _bconj(_bf("=", X, _bf("g", _bv(7), _bv(8), Y, _bv(9))), _bf("q", Y))
        ),
        ("unify two first variables", _bs("e3"), _bconj(_bf("=", Y, Z), _bf("q", Y, Z))),
        ("unify first with old", _bf("e4", X), _bconj(_bf("=", Y, X), _bf("q", Y))),
        ("unify old with first", _bf("e5", X), _bconj(_bf("=", X, Y), _bf("q", Y))),
        ("unify two old", _bf("e6", X, Y), _bf("=", X, Y)),
        ("unify with constants", _bf("e7", X),
            _bconj(_bf("=", Y, _bs("a")), _bf("=", X, _bg(7)), _bf("q", Y))),
        ("== and \\==", _bf("e8", X, Y),
            _bconj(_bf("==", X, Y), _bf("\\==", X, _bs("a")), _bf("==", Y, _bs("b")),
                _bf("\\==", X, Y))),
        ("type tests", _bf("e9", X),
            _bconj(_bf("var", X), _bf("nonvar", X), _bf("atom", X), _bf("integer", X),
                _bf("callable", X))),
        ("is with a small constant", _bf("e10", X, Y), _bf("is", Y, _bf("+", X, _bg(1)))),
        ("is, constant first", _bf("e11", X, Y), _bf("is", Y, _bf("+", _bg(2), X))),
        ("is, minus", _bf("e12", X, Y), _bf("is", Y, _bf("-", X, _bg(3)))),
        ("arguments of every kind", _bf("e13", X),
            _bf("q", _bs("a"), _bg(1), mk_nil(_B), _bg(2.5), _bg(big(2)^70), _bg("s"),
                _bf("f", X, _bv(7), _bf("g", _bv(8))), _blist(X, Y), Y)),
        ("true, fail and a cut", _bs("e14"), _bconj(_bs("true"), _bs("!"), _bs("fail"))),
        ("a left-nested conjunction", _bs("e15"),
            _bf(",", _bf(",", _bs("a"), _bs("b")), _bs("c"))),
        (
            "a last call that reuses the frame",
            _bf("e16", X, Y),
            _bconj(_bf("q", X), _bf("e16", Y, X))
        ),
        ("a unification that is always true", _bs("e17"), _bconj(_bf("=", Y, Y), _bs("a")))
    ]
end

"""
The terms `xs` written into fresh term references by the engine's write — a caller's variable is one
cell in all of them, read back by ONE `lk_answers`; the first one's handle. The decompiler
and clause/2 take term references (f3b-2b). The caller undoes the write (`Mark`/`Undo!`).
"""
function _bput(ld::LK.PL_local_data{_B}, xs::_B...)::Int
    t = LK.PL_new_term_refs(ld, length(xs))
    pvm = LK.PutVarMap()                                      # one record: shared variables, one cell (Q3)
    for (i, x) in enumerate(xs)
        LK.putSlotValue!(ld, t + i, x, pvm)                   # term reference t + (i - 1)
    end
    return t
end
"`cl` decompiled (`decompile!`): its head and body, with fresh variables."
function _bdecompile(cl::LK.Clause{_B}, head::_B)::Tuple{_B, _B}
    ld = LK.PL_local_data{_B}(_BGD)
    name, ar = _bfunctor(head)
    fresh() = mk_var(_B, LK.fresh_var_keys!(1))
    h = ar == 0 ? name : mk_expr(_B, _B[name; [fresh() for _ in 1:ar]])
    t = _bput(ld, h, fresh())
    LK.decompile!(ld, cl, t, t + 1) || error("_bdecompile: decompile! failed")
    dh, db = lk_answers(ld, t, t + 1)                     # one read: shared variables
    return (dh, db)
end

# What `decompile!` rebuilds from each cell's code, variables renamed in order (`_bnorm`): pinned,
# so the jobs without swipl check the decompiler too. Each is a variant of swipl's clause/2 (below).
const _BC_OR_DECOMPILED = Dict{String, String}(
    "a ; b" => "':-'(d1,';'(a,b))",
    "a | b" => "':-'(d2,';'(a,b))",
    "not last" => "':-'(d3,','(';'(a,b),c))",
    "three branches" => "':-'(d4,';'(a,';'(b,c)))",
    "left-nested" => "':-'(d5,';'(';'(a,b),c))",
    "a conjunction in a branch" => "':-'(d6,';'(','(a,b),','(c,d)))",
    "one variable to balance" => "':-'(d7(A),','(';'(q(A,B),r(A)),s(B)))",
    "balance in the second branch" => "':-'(d8(A),','(';'(r(A),q(A,B)),s(B)))",
    "both branches set it" => "':-'(d9(A),','(';'(q(A,B),r(B)),s(B)))",
    "a run of four" => "':-'(d10,','(';'(q(A,B,C,D),true),r(A,B,C,D)))",
    "a run of three" => "':-'(d11,','(';'(a,q(A,B,C)),r(A,B,C)))",
    "two apart" => "':-'(d12,','(';'(','(q(A),','(z(B),s(C))),t(B)),r(A,B,C)))",
    "a cut in a branch" => "':-'(d13,';'(','(a,'!'),b))",
    "inline goals" => "':-'(d14(A),';'('='(A,a),';'('=='(A,b),var(A))))",
    "a first variable unified in one branch" => "':-'(d15,','(';'('='(A,a),true),q(A)))",
    "true ; fail" => "':-'(d16,';'(true,fail))",
    "arithmetic in a branch" => "':-'(d17(A,B),';'(is(B,'+'(A,1)),'='(B,0)))",
    "a variable only inside" => "':-'(d18,';'(','(q(A),r(A)),s(B,B)))",
    "after a disjunction that set nothing" => "':-'(d19(A),','(';'(a,b),','(q(A,B),r(B))))",
    "a disjunction in a disjunction's branch" => "':-'(d20(_),','(';'(','(';'(q(A),r(B)),s(A,B)),t(C)),u(A,B,C)))",
    # `$/1`, `$/0` (since V9f): each equal to swipl's `clause/2` (the differential below)
    "\$ a goal" => "':-'(d21(A),'\$'(q(A)))",
    "\$ sets a variable" => "':-'(d22(A),','('\$'(q(A,B)),r(B)))",
    "\$ the atom" => "':-'(d23,','(a,','('\$',b)))",
    "\$ nested" => "':-'(d24(A),'\$'('\$'(q(A))))",
    "\$ with a cut" => "':-'(d25,'\$'(','(a,'!')))",
    "\$ in a branch" => "':-'(d26(A),','(';'('\$'(q(A,B)),r(A)),s(B)))",
    "\\+ \$" => "':-'(d27,'\\\\+'('\$'(a)))",
    "\$ the atom last" => "':-'(d28,','(a,'\$'))",
    "\$ two goals, two variables" => "':-'(d29(_),','('\$'(','(q(A),r(A,B))),s(B,_)))"
)
const _BC_DEC_DECOMPILED = Dict{String, String}(
    "unify with a compound" => "':-'(e1(A),','('='(A,f(B,[a|C],\"s\",1.5)),q(B,C)))",
    "unify: voids in the term" => "':-'(e2(A),','('='(A,g(_,_,B,_)),q(B)))",
    "unify two first variables" => "':-'(e3,','('='(A,B),q(A,B)))",
    "unify first with old" => "':-'(e4(A),','('='(B,A),q(B)))",
    "unify old with first" => "':-'(e5(A),','('='(A,B),q(B)))",
    "unify two old" => "':-'(e6(A,B),'='(A,B))",
    "unify with constants" => "':-'(e7(A),','('='(B,a),','('='(A,7),q(B))))",
    "== and \\==" => "':-'(e8(A,B),','('=='(A,B),','('\\\\=='(A,a),','('=='(B,b),'\\\\=='(A,B)))))",
    "type tests" => "':-'(e9(A),','(var(A),','(nonvar(A),','(atom(A),','(integer(A),callable(A))))))",
    "is with a small constant" => "':-'(e10(A,B),is(B,'+'(A,1)))",
    "is, constant first" => "':-'(e11(A,B),is(B,'+'(2,A)))",
    "is, minus" => "':-'(e12(A,B),is(B,'-'(A,3)))",
    "arguments of every kind" => "':-'(e13(A),q(a,1,[],2.5,1180591620717411303424,\"s\",f(A,_,g(_)),[A,B],B))",
    "true, fail and a cut" => "':-'(e14,','(true,','('!',fail)))",
    "a left-nested conjunction" => "':-'(e15,','(a,','(b,c)))",
    "a last call that reuses the frame" => "':-'(e16(A,B),','(q(A),e16(B,A)))",
    "a unification that is always true" => "':-'(e17,','(true,a))"
)

@testset "disjunctions compile as swipl's (V9d)" begin
    ours = [_bc_kernel(_bclause(h, b)) for (_, h, b) in _BC_OR_CELLS]
    named(n) = ours[findfirst(c -> c[1] == n, _BC_OR_CELLS)]
    # the shape: C_OR's jump lands after the first branch's C_JMP, and that one at the end; the
    # first branch's goal is an I_CALL, the second's the body's last call (its LCO block included)
    @test named("a ; b") ==
        ["i_enter", "c_or(L1)", "i_call(P:[97]/0)", "c_jmp(L2)", "L1:", "l_nolco(L3)",
        "i_lcall(P:[98]/0)", "L3:", "i_depart(P:[98]/0)", "L2:", "i_exit"]
    @test named("not last")[2:6] ==
        ["c_or(L1)", "i_call(P:[97]/0)", "c_jmp(L2)", "L1:", "i_call(P:[98]/0)"]
    @test named("a | b")[2:end] == named("a ; b")[2:end]        # `|` is `;`
    # balancing: the branch that leaves a variable unset makes it fresh, before its C_JMP or at
    # its end — also a variable that lives in the other branch alone; a variable both branches
    # set is not touched
    @test count(startswith("c_var("), named("one variable to balance")) == 1
    @test count(startswith("c_var("), named("balance in the second branch")) == 1
    @test !any(startswith("c_var"), named("both branches set it"))
    @test named("a variable only inside") == [
        "i_enter", "c_or(L1)", "b_firstvar(0)", "i_call(P:[113]/1)", "b_var0",
        "i_call(P:[114]/1)", "c_var(1)", "c_jmp(L2)", "L1:", "b_firstvar(1)", "b_var1",
        "i_depart(P:[115]/2)", "c_var(0)", "L2:", "i_exit"
    ]
    # upstream's `c_var` joins a slot to a run only when it follows the run's FIRST slot: four
    # slots in a row are two C_VAR_N of two, three are a C_VAR_N of two and a C_VAR
    @test count(startswith("c_var_n("), named("a run of four")) == 2 &&
        !any(startswith("c_var("), named("a run of four"))
    @test count(startswith("c_var_n("), named("a run of three")) == 1 &&
        count(startswith("c_var("), named("a run of three")) == 1
    @test count(startswith("c_var("), named("two apart")) == 2
    @test "i_cut" in named("a cut in a branch")                 # a clause-level cut: I_CUT
    # `$/1` (since V9f, c:2577-2616, c:2793-2826): the block, its success exit jumping over the
    # failure exit; `$/0`: I_DET
    @test named("\$ a goal") == ["i_enter", "c_det(1,L1)", "b_var0", "i_call(P:[113]/1)",
        "c_dettrue(1)", "c_jmp(L2)", "L1:", "c_detfalse", "L2:", "i_exit"]
    @test "i_det" in named("\$ the atom") && "i_det" in named("\$ the atom last")
    @test count(startswith("c_det("), named("\$ nested")) == 2
    @test any(startswith("c_lcut("), named("\$ with a cut"))  # a cut in `$` is local

    g = _BcGen(Xoshiro(20261012), UInt64(50_000))
    random = [_bcorclause(g, k) for k in 1:400]
    rours = [_bc_kernel(_bclause(h, b)) for (h, b) in random]
    @testset "the random bodies exercise it" begin
        used = union((_bc_names(c) for c in rours)...)
        missing_ = setdiff(
            ["c_or", "c_jmp", "c_var", "c_var_n", "i_cut", "i_true", "i_fail",
                "b_unify_var",
                "b_unify_fc", "b_eq_vv", "i_var", "a_add_fc", "i_depart", "i_call"], used)
        isempty(missing_) || println(stderr, "  not exercised: ", missing_)
        @test isempty(missing_)
        @test count(c -> count(startswith("c_or"), c) >= 3, rours) > 50      # nested
    end
    # the decompiler (`decompile!`, `decompileBodyNoShift!`): compiled with `optimise_unify` false,
    # so no unification is moved into a head (those clauses are refused until V9d's last step)
    ldf = LK.PL_local_data{_B}(_BGD)
    ldf.prolog_flag_optimise_unify = false
    v2g = _BcGen(Xoshiro(20261005), UInt64(90_000))
    plain = [_bcclause(v2g, 2000 + k) for k in 1:200]           # V2's bodies: plain goals and `!`
    dcases = [
        [(h, b) for (_, h, b) in _BC_OR_CELLS]; [(h, b) for (_, h, b) in _BC_DEC_CELLS]
        random; plain
        # `\$catch` (since V9f): I_CATCH decompiles to the atom, I_EXITCATCH to nothing (c:6753, c:6927)
        [
            (_bf("dk1", _bv(1), _bv(2), _bv(3)), _bs("\$catch")),
            (_bs("dk2"), _bconj(_bs("q"), _bs("\$catch"))),
            # `\$call_cleanup` (since V9g): I_CALLCLEANUP decompiles to the atom and takes the
            # I_EXITCLEANUP after it along (c:6787)
            (
                _bf("dk3", _bv(1), _bv(2), _bv(3)),
                _bconj(_bf("sig_atomic", _bv(1)), _bs("\$call_cleanup"))
            ),
            (_bf("dk4", _bv(1), _bv(2)), _bs("\$call_cleanup"))
        ]
    ]
    dclauses = [_bclause(h, b; ld=ldf) for (h, b) in dcases]
    decomp = [
        try
            _bdecompile(cl, h)
        catch
            println(
                stderr, "  decompiling ", _bc_text(h, b), "\n    code ", _bc_kernel(cl)
            )
            rethrow()
        end for (cl, (h, b)) in zip(dclauses, dcases)
    ]
    @testset "the decompiler: pinned clauses" begin
        got = [(c[1], _bnorm(_bc_text(decomp[k]...))) for (k, c) in enumerate(_BC_OR_CELLS)]
        for (n, t) in got
            want = get(_BC_OR_DECOMPILED, n, "")
            t == want || println(stderr, "  (\"", n, "\", \"", escape_string(t), "\"),")
            @test t == want
        end
        xg = [
            (n, _bnorm(_bc_text(_bdecompile(_bclause(h, b; ld=ldf), h)...))) for
            (n, h, b) in _BC_DEC_CELLS
        ]
        for (n, t) in xg
            want = get(_BC_DEC_DECOMPILED, n, "")
            t == want || println(stderr, "  (\"", n, "\", \"", escape_string(t), "\"),")
            @test t == want
        end
        # a clause with a unification moved into its head gets it back as a goal (below: the
        # whole corpus again under the default flags)
        moved = _bclause(
            _bf("dm", _bv(1)), _bconj(_bf("=", _bv(1), _bf("f", _bs("a"))), _bcq(_bv(1)))
        )
        @test moved.flags & LK.CL_HEAD_TERMS != 0
        @test _bnorm(_bc_text(_bdecompile(moved, _bf("dm", _bv(1)))...)) ==
            "':-'(dm(A),','('='(A,f(a)),q(A)))"
        # a fact's body is `true`; an instantiated body or head that does not match fails
        fact = _bclause(_bf("df", _bs("a")), nothing)
        @test _bc_text(_bdecompile(fact, _bf("df", _bv(1)))...) == "':-'(df(a),true)"
        ld = LK.PL_local_data{_B}(_BGD)
        d1 = dclauses[1]
        function dc(cl, h, b)
            m = LK.Mark(ld)
            t = _bput(ld, h, b)
            r = LK.decompile!(ld, cl, t, t + 1)
            LK.Undo!(ld, m)
            LK.PL_reset_term_refs(ld, t)
            return r
        end
        @test dc(d1, _bs("d1"), _bf(";", _bs("a"), _bv(9001)))
        @test !dc(d1, _bs("d1"), _bf(";", _bs("b"), _bv(9002)))
        @test !dc(d1, _bs("d1"), _bs("true"))
        @test !dc(fact, _bf("df", _bv(9003)), _bs("a"))
    end
    @testset "clause/2 with a body (pl_clause!)" begin
        gd = LK.PL_global_data{_B}()
        user = LK.MODULE_user(gd)
        pr = LK.lookupProcedure(_bs("cz"), 1, user)
        for (h, b) in (
            (_bf("cz", _bs("a")), nothing),
            (_bf("cz", _bv(1)), _bf(";", _bf("q", _bv(1)), _bf("r", _bv(1), _bv(2)))),
            (_bf("cz", _bs("b")), _bconj(_bs("s"), _bs("!")))
        )
            cl = LK.compileClause(gd, ldf, h, b, pr, user)
            LK.assertDefinition!(gd, pr.definition, cl, LK.CL_END)
        end
        ld = LK.PL_local_data{_B}(gd)
        function answers(head, body)
            out = String[]
            m = LK.Mark(ld)
            t = _bput(ld, head, body)
            LK.pl_clause!(
                gd,
                ld,
                pr.definition,
                t,
                t + 1,
                _ -> begin
                    push!(out, _bc_text(lk_answers(ld, t, t + 1)...))
                    true
                end
            )
            LK.Undo!(ld, m)
            LK.PL_reset_term_refs(ld, t)
            return out
        end
        # f3-2 (audit D-0111 Q3/Q5): was `"':-'(cz(V1),';'(q(V1),r(V1,_)))"` (the caller's V1
        # handed back by f3b-1's TRANSITIONAL import_origin) — an answer's variable is now a fresh
        # one, so the check is the property: ONE variable, shared by head and body (`_bnorm`: A)
        @test _bnorm.(answers(_bf("cz", _bv(1)), _bv(2))) == [
            "':-'(cz(a),true)", "':-'(cz(A),';'(q(A),r(A,_)))", "':-'(cz(b),','(s,'!'))"
        ]
        @test answers(_bf("cz", _bs("b")), _bv(2)) ==           # the head's binding reaches the body
            ["':-'(cz(b),';'(q(b),r(b,_)))", "':-'(cz(b),','(s,'!'))"]
        @test answers(_bf("cz", _bv(1)), _bs("true")) == ["':-'(cz(a),true)"]
        # f3-2 (audit D-0111 Q3/Q5): was `["':-'(cz(V1),';'(q(V1),r(V1,_)))"]` — as above, the
        # caller's V1 is no longer handed back; one fresh variable shared by head and body
        @test _bnorm.(answers(_bf("cz", _bv(1)), _bf(";", _bv(2), _bv(3)))) ==
            ["':-'(cz(A),';'(q(A),r(A,_)))"]
        @test isempty(answers(_bf("cz", _bs("c")), _bs("true")))
        # the ORDER of two decompiled variables (f3b-2b, decompiler design obligation 1): clause(cy, B)
        # of `cy :- q(Y, Z), r(Z, Y)` builds q's argument cells and binds each, younger to older
        # (`unifyVar`, `v < var`), to Y's and Z's clause-variable cells; r's then to the same — so
        # Y @< Z. swipl agrees (below): its clause variables are local slots, each bound to q's
        # argument cell, and r's cells to those.
        py = LK.lookupProcedure(_bs("cy"), 0, user)
        cyb = _bconj(_bf("q", _bv(1), _bv(2)), _bf("r", _bv(2), _bv(1)))
        LK.assertDefinition!(
            gd, py.definition, LK.compileClause(gd, ldf, _bs("cy"), cyb, py, user),
            LK.CL_END
        )
        cy = Tuple{Int, String, String}[]
        m = LK.Mark(ld)
        t = _bput(ld, _bs("cy"), _bv(9))                    # cy, B; then Q, Y, Z
        LK.PL_new_term_refs(ld, 3)
        LK.pl_clause!(
            gd, ld, py.definition, t, t + 1,
            _ -> begin
                LK._PL_get_arg(ld, 1, t + 1, t + 2)         # B = (Q, _)
                LK._PL_get_arg(ld, 1, t + 2, t + 3)         # Q = q(Y, Z)
                LK._PL_get_arg(ld, 2, t + 2, t + 4)
                push!(
                    cy,
                    (LK.PL_compare(ld, t + 3, t + 4), LK.varName(ld, t + 3),
                        LK.varName(ld, t + 4))
                )
                true
            end
        )
        LK.Undo!(ld, m)
        LK.PL_reset_term_refs(ld, t)
        @test length(cy) == 1 && sign(cy[1][1]) == -1      # compare(<, Y, Z), as swipl (below)
        # their printed names, pinned: the clause-variable cells' positions (`varName`, f3b-2a), Y's
        # first. swipl 10.1.18 prints `_436-_438` for the same `print(A-B)` (its own addresses, also
        # Y's first) — a known difference in the numbers only (feedback: pin the exact answer).
        # Landing A (f3b-4) moved them from ("_20", "_22"): emptyStacks makes upstream's TMP_PTR_SIZE
        # handles (pl-setup.c), 4 more permanent cells (a new local data's gTop 4 -> 8, measured), and
        # this testset's earlier steps on the same local data allocate 4 more (internal identity,
        # D-0083; not traced cell by cell). AV1 moved them again from ("_28", "_30"): emptyStacks makes
        # the wakeup list's head and tail (pl-setup.c), 2 more permanent cells before every later one, so
        # each name grows by 4 (`varName` prints twice the offset; internal identity, D-0083). The order
        # against swipl above is unchanged.
        @test cy[1][2:3] == ("_32", "_34")
        if _BC_SWIPL_BIN !== nothing
            theirs = _bc_swipl([
                "(assertz((cy :- q(Y, Z), r(Z, Y))), clause(cy, (q(A, B), _)), " *
                "compare(O, A, B), writeln(O))"
            ])
            @test theirs == [["<"]]
        end
    end
    if _BC_SWIPL_BIN !== nothing
        @testset "the decompiled clauses are variants of swipl's clause/2" begin
            shows = [
                "bc_decomp(($(_bc_text(h, b))), ($(_bc_text(dh, db))))" for
                ((h, b), (dh, db)) in zip(dcases, decomp)
            ]
            theirs = _bc_swipl(shows; prelude="set_prolog_flag(optimise_unify, false)")
            @test length(theirs) == length(shows)
            bad = 0
            for k in eachindex(shows)
                k <= length(theirs) || break
                if theirs[k] != ["same"]
                    bad += 1
                    bad <= 5 &&
                        println(stderr, "  ", _bc_text(dcases[k]...), "\n    ours  ",
                            _bc_text(decomp[k]...), "\n    swipl ", theirs[k])
                end
            end
            @test bad == 0
        end
        @testset "identical to swipl" begin
            all_ = [[(h, b) for (_, h, b) in _BC_OR_CELLS]; random]
            allours = [ours; rours]
            theirs = _bc_swipl(["bc_case_show(($(_bc_text(h, b))))" for (h, b) in all_])
            @test length(theirs) == length(all_)
            bad = 0
            for k in eachindex(all_)
                k <= length(theirs) || break
                if allours[k] != theirs[k]
                    bad += 1
                    bad <= 5 && println(stderr, "  ", _bc_text(all_[k]...), "\n    ours  ",
                        allours[k], "\n    swipl ", theirs[k])
                end
            end
            @test bad == 0
        end
    end
end

# ── V9d: the conditionals `(A -> B ; C)` and `(A -> B)` ─────────────────────────────────────────
# `C_IFTHENELSE <A> C_CUT <B> C_JMP <C>` — `C_FASTCOND`/`C_FASTCUT` when A is only type tests and
# `==`/`\==` — and `C_IFTHEN <A> C_CUT <B> C_END`; each takes a frame slot past the Prolog
# variables for its choice-point reference (`allocChoiceVar!`), and a `!` in A cuts locally
# (`C_LCUT`, `C_LCUTIFTHEN`). Pinned cells, then random bodies of `,`, `;` and `->`.
const _BC_ITE_CELLS = let X = _bv(1), Y = _bv(2), Z = _bv(3)
    ite(a, b, c) = _bf(";", _bf("->", a, b), c)
    it(a, b) = _bf("->", a, b)
    [
        ("if-then-else", _bf("i1", X), ite(_bf("q", X), _bf("r", X), _bf("s", X))),
        ("a fast condition", _bf("i2", X),
            ite(_bconj(_bf("integer", X), _bf("==", X, _bg(1))), _bf("r", X), _bf("s", X))),
        (
            "rational/1 is not fast",
            _bf("i3", X),
            ite(_bf("rational", X), _bs("r"), _bs("s"))
        ),
        ("a cut in the condition", _bf("i4", X),
            ite(_bconj(_bf("q", X), _bs("!")), _bf("r", X), _bf("s", X))),
        ("if-then", _bf("i5", X), _bconj(it(_bf("q", X), _bf("r", X)), _bf("s", X))),
        ("a cut in an if-then's condition", _bf("i6", X),
            it(_bconj(_bf("q", X), _bs("!")), _bf("r", X))),
        ("a variable to balance", _bf("i7", X, Y),
            _bconj(ite(_bf("q", X), _bf("=", Y, _bg(1)), _bs("true")), _bf("u", Y))),
        ("nested in then and in else", _bs("i8"),
            ite(
                _bs("a"),
                ite(_bs("b"), _bs("c"), _bs("d")),
                ite(_bs("e"), _bs("f"), _bs("g"))
            )),
        ("a disjunction as the condition", _bs("i9"),
            ite(_bf(";", _bs("a"), _bs("b")), _bs("c"), _bs("d"))),
        ("a conditional as the condition", _bs("i10"),
            ite(ite(_bs("a"), _bs("b"), _bs("c")), _bs("d"), _bs("e"))),
        ("a cut in then is the clause's", _bs("i11"),
            _bconj(ite(_bs("a"), _bs("!"), _bs("b")), _bs("c"))),
        ("a cut in else", _bs("i12"), ite(_bs("a"), _bs("b"), _bs("!"))),
        ("if-then as a disjunction's right side", _bs("i13"),
            _bf(";", _bs("a"), it(_bs("b"), _bs("c")))),
        ("the condition binds a variable used after", _bf("i14", Y),
            _bconj(ite(_bf("q", Z), _bf("r", Z), _bf("=", Z, _bg(0))), _bf("s", Z, Y))),
        ("a fast condition on var/1", _bf("i15", X, Y),
            ite(_bf("var", X), _bf("=", Y, _bs("a")), _bf("=", Y, _bs("b")))),
        ("two conditionals in a row", _bs("i16"),
            _bconj(ite(_bs("a"), _bs("b"), _bs("c")), ite(_bs("d"), _bs("e"), _bs("f")))),
        ("== as the condition", _bf("i17", X, Y), ite(_bf("==", X, Y), _bs("a"), _bs("b"))),
        ("a chain of conditions", _bf("i18", X, Y),
            ite(
                _bf("\\==", X, Y),
                _bs("a"),
                ite(_bf("==", X, _bs("a")), _bs("b"), _bs("c"))
            )),
        ("if-then on a test: never fast", _bf("i19", X), it(_bf("atom", X), _bf("q", X))),
        ("a fast condition, then a call that is not", _bf("i20", X),
            ite(_bconj(_bf("atom", X), _bf("q", X)), _bs("a"), _bs("b")))
    ]
end

"A random body of `,`, `;`, `(C -> T ; E)` and `(C -> T)`; a condition is sometimes tests only."
function _bcitebody(g::_BcGen, pool::Vector{_B}, depth::Int)::_B
    r = rand(g.rng)
    v() = rand(g.rng, pool)
    tests() = _bconj(
        [
            if rand(g.rng, Bool)
                _bf(rand(g.rng, ("var", "nonvar", "atom", "integer")), v())
            else
                _bf(rand(g.rng, ("==", "\\==")), v(), rand(g.rng, Bool) ? v() : _bs("a"))
            end for
            _ in 1:rand(g.rng, 1:2)
        ]...
    )
    if depth < 4 && r < 0.2
        cond = rand(g.rng) < 0.4 ? tests() : _bcitebody(g, pool, depth + 1)
        return _bf(";", _bf("->", cond, _bcitebody(g, pool, depth + 1)),
            _bcitebody(g, pool, depth + 1))
    elseif depth < 4 && r < 0.3
        cond = rand(g.rng) < 0.3 ? tests() : _bcitebody(g, pool, depth + 1)
        return _bf("->", cond, _bcitebody(g, pool, depth + 1))
    elseif depth < 4 && r < 0.42
        return _bf(";", _bcitebody(g, pool, depth + 1), _bcitebody(g, pool, depth + 1))
    elseif depth < 4 && r < 0.6
        return _bf(",", _bcitebody(g, pool, depth + 1), _bcitebody(g, pool, depth + 1))
    end
    return _bcorbody(g, pool, 4)                                # a goal
end

"A random rule clause `bi<k>(…) :- Body`, the body a conditional at the top or below a `,`."
function _bciteclause(g::_BcGen, k::Int)::Tuple{_B, _B}
    pool = _B[_bcfresh!(g) for _ in 1:rand(g.rng, 2:6)]
    har = rand(g.rng, 0:3)
    head = har == 0 ? _bs("bi$k") : _be("bi$k", [rand(g.rng, pool) for _ in 1:har])
    cond = _bcitebody(g, pool, 2)
    body = if rand(g.rng) < 0.75
        _bf(";", _bf("->", cond, _bcitebody(g, pool, 2)), _bcitebody(g, pool, 2))
    else
        _bf("->", cond, _bcitebody(g, pool, 2))
    end
    r = rand(g.rng)
    if r < 0.3
        body = _bf(",", body, _bcitebody(g, pool, 2))
    elseif r < 0.5
        body = _bf(",", _bcitebody(g, pool, 2), body)
    end
    return (head, body)
end

# What `decompile!` rebuilds from each conditional cell, variables renamed in order (`_bnorm`).
const _BC_ITE_DECOMPILED = Dict{String, String}(
    "if-then-else" => "':-'(i1(A),';'('->'(q(A),r(A)),s(A)))",
    "a fast condition" => "':-'(i2(A),';'('->'(','(integer(A),'=='(A,1)),r(A)),s(A)))",
    "rational/1 is not fast" => "':-'(i3(A),';'('->'(rational(A),r),s))",
    "a cut in the condition" => "':-'(i4(A),';'('->'(','(q(A),'!'),r(A)),s(A)))",
    "if-then" => "':-'(i5(A),','('->'(q(A),r(A)),s(A)))",
    "a cut in an if-then's condition" => "':-'(i6(A),'->'(','(q(A),'!'),r(A)))",
    "a variable to balance" => "':-'(i7(A,B),','(';'('->'(q(A),'='(B,1)),true),u(B)))",
    "nested in then and in else" => "':-'(i8,';'('->'(a,';'('->'(b,c),d)),';'('->'(e,f),g)))",
    "a disjunction as the condition" => "':-'(i9,';'('->'(';'(a,b),c),d))",
    "a conditional as the condition" => "':-'(i10,';'('->'(';'('->'(a,b),c),d),e))",
    "a cut in then is the clause's" => "':-'(i11,','(';'('->'(a,'!'),b),c))",
    "a cut in else" => "':-'(i12,';'('->'(a,b),'!'))",
    "if-then as a disjunction's right side" => "':-'(i13,';'(a,'->'(b,c)))",
    "the condition binds a variable used after" => "':-'(i14(A),','(';'('->'(q(B),r(B)),'='(B,0)),s(B,A)))",
    "a fast condition on var/1" => "':-'(i15(A,B),';'('->'(var(A),'='(B,a)),'='(B,b)))",
    "two conditionals in a row" => "':-'(i16,','(';'('->'(a,b),c),';'('->'(d,e),f)))",
    "== as the condition" => "':-'(i17(A,B),';'('->'('=='(A,B),a),b))",
    "a chain of conditions" => "':-'(i18(A,B),';'('->'('\\\\=='(A,B),a),';'('->'('=='(A,a),b),c)))",
    "if-then on a test: never fast" => "':-'(i19(A),'->'(atom(A),q(A)))",
    "a fast condition, then a call that is not" => "':-'(i20(A),';'('->'(','(atom(A),q(A)),a),b))"
)

@testset "conditionals compile as swipl's (V9d)" begin
    ours = [_bc_kernel(_bclause(h, b)) for (_, h, b) in _BC_ITE_CELLS]
    named(n) = ours[findfirst(c -> c[1] == n, _BC_ITE_CELLS)]
    # the choice-point slot is the first past the Prolog variables; the condition's goals are
    # calls, the then branch ends at a C_JMP over the else branch
    @test named("if-then-else")[2:5] ==
        ["c_ifthenelse(1,L1)", "b_var0", "i_call(P:[113]/1)", "c_cut(1)"]
    @test named("a fast condition")[2:5] ==
        ["c_fastcond(1,L1)", "i_integer(0)", "b_eq_vc(0,i:1)", "c_fastcut(1)"]
    @test named("rational/1 is not fast")[2] == "c_ifthenelse(1,L1)"   # not in upstream's list
    @test named("a fast condition, then a call that is not")[2] == "c_ifthenelse(1,L1)"
    @test "c_lcut(1)" in named("a cut in the condition")
    @test "c_lcutifthen(1)" in named("a cut in an if-then's condition")
    @test named("if-then")[2] == "c_ifthen(1)" && "c_end" in named("if-then")
    @test named("if-then on a test: never fast")[2] == "c_ifthen(1)"
    @test "i_cut" in named("a cut in then is the clause's") &&
        "i_cut" in named("a cut in else")
    # each condition has a slot of its own, counted in the frame and not among the variables
    cl = _bclause(_BC_ITE_CELLS[8][2], _BC_ITE_CELLS[8][3])    # three conditions, no variable
    @test cl.prolog_vars == 0 && cl.variables == 3
    cl = _bclause(_BC_ITE_CELLS[7][2], _BC_ITE_CELLS[7][3])    # two variables, one condition
    @test cl.prolog_vars == 2 && cl.variables == 3

    g = _BcGen(Xoshiro(20261013), UInt64(70_000))
    random = [_bciteclause(g, k) for k in 1:400]
    rours = [_bc_kernel(_bclause(h, b)) for (h, b) in random]
    @testset "the random bodies exercise it" begin
        used = union((_bc_names(c) for c in rours)...)
        missing_ = setdiff(
            ["c_ifthenelse", "c_ifthen", "c_cut", "c_fastcond", "c_fastcut", "c_end",
                "c_lcut", "c_lcutifthen", "c_or", "c_jmp", "c_var", "i_cut"], used)
        isempty(missing_) || println(stderr, "  not exercised: ", missing_)
        @test isempty(missing_)
        @test count(c -> count(startswith("c_if"), c) >= 3, rours) > 50      # nested
    end
    ldf = LK.PL_local_data{_B}(_BGD)
    ldf.prolog_flag_optimise_unify = false
    dcases = [[(h, b) for (_, h, b) in _BC_ITE_CELLS]; random]
    dclauses = [_bclause(h, b; ld=ldf) for (h, b) in dcases]
    decomp = [
        try
            _bdecompile(cl, h)
        catch
            println(
                stderr, "  decompiling ", _bc_text(h, b), "\n    code ", _bc_kernel(cl)
            )
            rethrow()
        end for (cl, (h, b)) in zip(dclauses, dcases)
    ]
    @testset "the decompiler: pinned clauses" begin
        for (k, c) in enumerate(_BC_ITE_CELLS)
            t = _bnorm(_bc_text(decomp[k]...))
            want = get(_BC_ITE_DECOMPILED, c[1], "")
            t == want || println(stderr, "  (\"", c[1], "\", \"", escape_string(t), "\"),")
            @test t == want
        end
    end
    if _BC_SWIPL_BIN !== nothing
        @testset "the decompiled clauses are variants of swipl's clause/2" begin
            shows = [
                "bc_decomp(($(_bc_text(h, b))), ($(_bc_text(dh, db))))" for
                ((h, b), (dh, db)) in zip(dcases, decomp)
            ]
            theirs = _bc_swipl(shows; prelude="set_prolog_flag(optimise_unify, false)")
            @test length(theirs) == length(shows)
            bad = 0
            for k in eachindex(shows)
                k <= length(theirs) || break
                if theirs[k] != ["same"]
                    bad += 1
                    bad <= 5 &&
                        println(stderr, "  ", _bc_text(dcases[k]...), "\n    ours  ",
                            _bc_text(decomp[k]...), "\n    swipl ", theirs[k])
                end
            end
            @test bad == 0
        end
        @testset "identical to swipl" begin
            all_ = [[(h, b) for (_, h, b) in _BC_ITE_CELLS]; random]
            allours = [ours; rours]
            theirs = _bc_swipl(["bc_case_show(($(_bc_text(h, b))))" for (h, b) in all_])
            @test length(theirs) == length(all_)
            bad = 0
            for k in eachindex(all_)
                k <= length(theirs) || break
                if allours[k] != theirs[k]
                    bad += 1
                    bad <= 5 && println(stderr, "  ", _bc_text(all_[k]...), "\n    ours  ",
                        allours[k], "\n    swipl ", theirs[k])
                end
            end
            @test bad == 0
        end
    end
end

# ── V9d: negation `\+ A` ────────────────────────────────────────────────────────────────────────
# `C_NOT <A> C_CUT C_FAIL`, then — only when A first uses a variable — a `C_JMP` over the `C_VAR`s
# that make those variables fresh on the way out (pl-comp.c `compileBody`, CB_NOT_INNER).
const _BC_NOT_CELLS = let X = _bv(1), Y = _bv(2), Z = _bv(3)
    no(a) = _bf("\\+", a)
    [
        ("not", _bf("n1", X), no(_bf("q", X))),
        ("not, then a goal", _bf("n2", X), _bconj(no(_bf("q", X)), _bf("r", X))),
        (
            "a variable first used inside",
            _bf("n3", X),
            _bconj(no(_bf("q", X, Y)), _bf("r", Y))
        ),
        ("two variables first used inside", _bs("n4"),
            _bconj(no(_bf("q", Y, Z)), _bf("r", Y, Z))),
        ("a variable used before and inside", _bf("n5", X),
            _bconj(_bf("s", Y), no(_bf("q", X, Y)), _bf("r", Y))),
        ("a cut inside", _bs("n6"), no(_bconj(_bs("a"), _bs("!"), _bs("b")))),
        ("not not", _bf("n7", X), no(no(_bf("q", X)))),
        ("a conjunction inside", _bf("n8", X), no(_bconj(_bf("q", X), _bf("r", X)))),
        ("a disjunction inside", _bs("n9"), no(_bf(";", _bs("a"), _bs("b")))),
        ("a conditional inside", _bs("n10"),
            no(_bf(";", _bf("->", _bs("a"), _bs("b")), _bs("c")))),
        ("as a condition", _bf("n11", X),
            _bf(";", _bf("->", no(_bf("q", X)), _bs("a")), _bs("b"))),
        ("in a disjunction's branches", _bf("n12", X),
            _bf(";", no(_bf("q", X)), no(_bf("r", X, Y)))),
        ("an inline test inside", _bf("n13", X), no(_bf("==", X, _bs("a")))),
        (
            "a unification inside",
            _bf("n14", X),
            _bconj(no(_bf("=", X, _bs("a"))), _bs("b"))
        ),
        ("true and fail inside", _bs("n15"), _bconj(no(_bs("fail")), no(_bs("true")))),
        (
            "last, after a cut",
            _bf("n16", X),
            _bconj(_bf("q", X), _bs("!"), no(_bf("r", X)))
        )
    ]
end

"A random body like `_bcitebody`'s with `\\+` over any of it."
function _bcnotbody(g::_BcGen, pool::Vector{_B}, depth::Int)::_B
    r = rand(g.rng)
    if depth < 4 && r < 0.25
        return _bf("\\+", _bcnotbody(g, pool, depth + 1))
    elseif depth < 4 && r < 0.4
        return _bf(";",
            _bf("->", _bcnotbody(g, pool, depth + 1), _bcnotbody(g, pool, depth + 1)),
            _bcnotbody(g, pool, depth + 1))
    elseif depth < 4 && r < 0.5
        return _bf(";", _bcnotbody(g, pool, depth + 1), _bcnotbody(g, pool, depth + 1))
    elseif depth < 4 && r < 0.68
        return _bf(",", _bcnotbody(g, pool, depth + 1), _bcnotbody(g, pool, depth + 1))
    end
    return _bcorbody(g, pool, 4)                                # a goal
end

"A random rule clause `bn<k>(…) :- Body` with a `\\+` at the top or below a `,`."
function _bcnotclause(g::_BcGen, k::Int)::Tuple{_B, _B}
    pool = _B[_bcfresh!(g) for _ in 1:rand(g.rng, 2:6)]
    har = rand(g.rng, 0:3)
    head = har == 0 ? _bs("bn$k") : _be("bn$k", [rand(g.rng, pool) for _ in 1:har])
    body = _bf("\\+", _bcnotbody(g, pool, 2))
    r = rand(g.rng)
    if r < 0.45
        body = _bf(",", body, _bcnotbody(g, pool, 2))
    elseif r < 0.7
        body = _bf(",", _bcnotbody(g, pool, 2), body)
    end
    return (head, body)
end

# What `decompile!` rebuilds from each negation cell, variables renamed in order (`_bnorm`).
const _BC_NOT_DECOMPILED = Dict{String, String}(
    "not" => "':-'(n1(A),'\\\\+'(q(A)))",
    "not, then a goal" => "':-'(n2(A),','('\\\\+'(q(A)),r(A)))",
    "a variable first used inside" => "':-'(n3(A),','('\\\\+'(q(A,B)),r(B)))",
    "two variables first used inside" => "':-'(n4,','('\\\\+'(q(A,B)),r(A,B)))",
    "a variable used before and inside" => "':-'(n5(A),','(s(B),','('\\\\+'(q(A,B)),r(B))))",
    "a cut inside" => "':-'(n6,'\\\\+'(','(a,','('!',b))))",
    "not not" => "':-'(n7(A),'\\\\+'('\\\\+'(q(A))))",
    "a conjunction inside" => "':-'(n8(A),'\\\\+'(','(q(A),r(A))))",
    "a disjunction inside" => "':-'(n9,'\\\\+'(';'(a,b)))",
    "a conditional inside" => "':-'(n10,'\\\\+'(';'('->'(a,b),c)))",
    "as a condition" => "':-'(n11(A),';'('->'('\\\\+'(q(A)),a),b))",
    "in a disjunction's branches" => "':-'(n12(A),';'('\\\\+'(q(A)),'\\\\+'(r(A,_))))",
    "an inline test inside" => "':-'(n13(A),'\\\\+'('=='(A,a)))",
    "a unification inside" => "':-'(n14(A),','('\\\\+'('='(A,a)),b))",
    "true and fail inside" => "':-'(n15,','('\\\\+'(fail),'\\\\+'(true)))",
    "last, after a cut" => "':-'(n16(A),','(q(A),','('!','\\\\+'(r(A)))))"
)

@testset "negation compiles as swipl's (V9d)" begin
    ours = [_bc_kernel(_bclause(h, b)) for (_, h, b) in _BC_NOT_CELLS]
    named(n) = ours[findfirst(c -> c[1] == n, _BC_NOT_CELLS)]
    # A sets no variable: no jump after the C_FAIL; the C_NOT's own jump lands right after it
    @test named("not") ==
        ["i_enter", "c_not(1,L1)", "b_var0", "i_call(P:[113]/1)", "c_cut(1)", "c_fail",
        "L1:",
        "i_exit"]
    # A first uses Y: Y is made fresh on the way out, behind a jump nothing reaches
    @test named("a variable first used inside")[6:10] ==
        ["c_cut(2)", "c_fail", "c_jmp(L2)", "L1:", "c_var(1)"]
    @test any(startswith("c_var_n("), named("two variables first used inside"))
    @test !any(startswith("c_var"), named("a variable used before and inside"))
    @test "c_lcut(0)" in named("a cut inside")                  # a `!` in \+ cuts locally
    @test "i_cut" in named("last, after a cut")

    g = _BcGen(Xoshiro(20261014), UInt64(110_000))
    random = [_bcnotclause(g, k) for k in 1:400]
    rours = [_bc_kernel(_bclause(h, b)) for (h, b) in random]
    @testset "the random bodies exercise it" begin
        used = union((_bc_names(c) for c in rours)...)
        missing_ = setdiff(
            ["c_not", "c_fail", "c_cut", "c_lcut", "c_jmp", "c_var", "c_var_n",
                "c_ifthenelse",
                "c_or"], used)
        isempty(missing_) || println(stderr, "  not exercised: ", missing_)
        @test isempty(missing_)
        @test count(c -> count(startswith("c_not"), c) >= 2, rours) > 50     # nested
        # both forms occur: with the jump (A first uses a variable) and without
        @test any(
            c -> any(i -> c[i] == "c_fail" && startswith(c[i + 1], "c_jmp"),
                1:(length(c) - 1)), rours)
        @test any(
            c -> any(i -> c[i] == "c_fail" && !startswith(c[i + 1], "c_jmp"),
                1:(length(c) - 1)), rours)
    end
    ldf = LK.PL_local_data{_B}(_BGD)
    ldf.prolog_flag_optimise_unify = false
    dcases = [[(h, b) for (_, h, b) in _BC_NOT_CELLS]; random]
    dclauses = [_bclause(h, b; ld=ldf) for (h, b) in dcases]
    decomp = [
        try
            _bdecompile(cl, h)
        catch
            println(
                stderr, "  decompiling ", _bc_text(h, b), "\n    code ", _bc_kernel(cl)
            )
            rethrow()
        end for (cl, (h, b)) in zip(dclauses, dcases)
    ]
    @testset "the decompiler: pinned clauses" begin
        for (k, c) in enumerate(_BC_NOT_CELLS)
            t = _bnorm(_bc_text(decomp[k]...))
            want = get(_BC_NOT_DECOMPILED, c[1], "")
            t == want || println(stderr, "  (\"", c[1], "\", \"", escape_string(t), "\"),")
            @test t == want
        end
    end
    if _BC_SWIPL_BIN !== nothing
        @testset "the decompiled clauses are variants of swipl's clause/2" begin
            shows = [
                "bc_decomp(($(_bc_text(h, b))), ($(_bc_text(dh, db))))" for
                ((h, b), (dh, db)) in zip(dcases, decomp)
            ]
            theirs = _bc_swipl(shows; prelude="set_prolog_flag(optimise_unify, false)")
            @test length(theirs) == length(shows)
            bad = 0
            for k in eachindex(shows)
                k <= length(theirs) || break
                if theirs[k] != ["same"]
                    bad += 1
                    bad <= 5 &&
                        println(stderr, "  ", _bc_text(dcases[k]...), "\n    ours  ",
                            _bc_text(decomp[k]...), "\n    swipl ", theirs[k])
                end
            end
            @test bad == 0
        end
        @testset "identical to swipl" begin
            all_ = [[(h, b) for (_, h, b) in _BC_NOT_CELLS]; random]
            allours = [ours; rours]
            theirs = _bc_swipl(["bc_case_show(($(_bc_text(h, b))))" for (h, b) in all_])
            @test length(theirs) == length(all_)
            bad = 0
            for k in eachindex(all_)
                k <= length(theirs) || break
                if allours[k] != theirs[k]
                    bad += 1
                    bad <= 5 && println(stderr, "  ", _bc_text(all_[k]...), "\n    ours  ",
                        allours[k], "\n    swipl ", theirs[k])
                end
            end
            @test bad == 0
        end
    end
end

# ── V9d: decompiling a clause whose unifications were moved into its head ───────────────────────
# Under the default flags a leading `Arg = Term` of a static clause is compiled into the head
# (V9b). `decompile!` puts it back: `mark_bvar_access` finds the head arguments the code reads,
# the head decompiler gives such an argument its slot's variable and keeps the term, and
# `moved_unifications!` writes `Arg = Term` before the body's own goals — swipl's clause/2.
"A random rule clause `bm<k>(V1, …, Vn) :- Vi = Term, …, Body`: unifications on head arguments first."
function _bcmoveclause(g::_BcGen, k::Int)::Tuple{_B, _B}
    n = rand(g.rng, 1:3)
    hvars = _B[_bcfresh!(g) for _ in 1:n]
    pool = _B[hvars; [_bcfresh!(g) for _ in 1:2]]
    goals = _B[]
    for v in shuffle(g.rng, hvars)
        rand(g.rng) < 0.75 || continue
        t = _bcarg(g, pool, 1)
        push!(goals, rand(g.rng) < 0.8 ? _bf("=", v, t) : _bf("=", t, v))
    end
    isempty(goals) && push!(goals, _bf("=", hvars[1], _bcconst(g)))
    rand(g.rng) < 0.7 && push!(goals, _bcnotbody(g, pool, 2))
    rand(g.rng) < 0.3 && push!(goals, _bf("=", rand(g.rng, hvars), _bcconst(g)))  # one more, after
    return (_be("bm$k", hvars), _bconj(goals...))
end

# What `decompile!` rebuilds from each moved-unification cell (V9b's), variables renamed in order.
const _BC_MOVE_DECOMPILED = Dict{String, String}(
    "compound" => "':-'(mv1(f(a)),true)",
    "then a use" => "':-'(um1(A),','('='(A,f(a)),q(A)))",
    "atom" => "':-'(um2(A),','('='(A,a),q(A)))",
    "var = var: no move" => "':-'(mv2(A),','('='(A,B),q(B)))",
    "var = arg: no move" => "':-'(mv3(A),','('='(B,A),q(B)))",
    "after a goal: no move" => "':-'(mv4(A),','(q,'='(A,a)))",
    "a non-argument = does not stop it" => "':-'(mv6(a),','('='(A,b),q(A)))",
    "no head argument" => "':-'(mv7,','('='(A,f(B)),q(A,B)))",
    "cut first: no move" => "':-'(mv12(A),','('!','='(A,a)))",
    "then a cut" => "':-'(mv13(A),','('='(A,a),','('!',q(A))))",
    "reversed" => "':-'(mv15(A),','('='(A,a),q(A)))",
    "a repeated head argument" => "':-'(mv16(A,A),'='(A,a))",
    "the second = stays" => "':-'(mv17(A),','('='(A,a),'='(A,b)))",
    "true is skipped" => "':-'(mv19(a),true)",
    "the term holds the argument" => "':-'(mv20(A),'='(A,f(A)))",
    "a nested head variable: no move" => "':-'(mv22(f(A)),'='(A,a))",
    "a float" => "':-'(mv23(A),','('='(A,1.5),q(A)))",
    "then ==" => "':-'(mv24(A),','('='(A,a),'=='(A,a)))",
    "through another argument" => "':-'(mv25(A,B),','('='(A,f(B)),','('='(B,B),'='(B,A))))",
    "two arguments" => "':-'(mv29(a,b),true)",
    "two, out of order" => "':-'(mv30(A,B),','('='(A,a),','('='(B,b),q(A,B))))",
    "past the tagged range" => "':-'(mv35(3000000000),true)",
    "a list" => "':-'(mv42([a|A]),q(A))",
    "a string" => "':-'(mv43(A),','('='(A,\"str\"),q(A)))",
    "a void first" => "':-'(mv58(a),true)",
    "past var = var" => "':-'(mv59(A),','('='(A,a),','('='(A,B),'='(B,b))))",
    "past another =" => "':-'(mv67(a),','('='(A,true),q(A)))"
)

@testset "the decompiler puts moved unifications back (V9d)" begin
    g1 = _BcGen(Xoshiro(20261012), UInt64(50_000))
    g2 = _BcGen(Xoshiro(20261013), UInt64(70_000))
    g3 = _BcGen(Xoshiro(20261014), UInt64(110_000))
    gm = _BcGen(Xoshiro(20261016), UInt64(130_000))
    cells = [(h, b) for (_, h, b) in _BC_MOVE_CELLS]
    dcases = [
        cells; [(h, b) for (_, h, b) in _BC_OR_CELLS];
        [(h, b) for (_, h, b) in _BC_DEC_CELLS]
        [(h, b) for (_, h, b) in _BC_ITE_CELLS]; [(h, b) for (_, h, b) in _BC_NOT_CELLS]
        [_bcmoveclause(gm, k) for k in 1:400]; [_bcorclause(g1, k) for k in 1:400]
        [_bciteclause(g2, k) for k in 1:400]; [_bcnotclause(g3, k) for k in 1:400]
    ]
    dclauses = [_bclause(h, b) for (h, b) in dcases]                # the default flags
    nmoved = count(cl -> cl.flags & LK.CL_HEAD_TERMS != 0, dclauses)
    @test nmoved > 250                                              # the corpus has them
    decomp = [
        try
            _bdecompile(cl, h)
        catch
            println(
                stderr, "  decompiling ", _bc_text(h, b), "\n    code ", _bc_kernel(cl)
            )
            rethrow()
        end for (cl, (h, b)) in zip(dclauses, dcases)
    ]
    @testset "pinned clauses" begin
        for (k, c) in enumerate(_BC_MOVE_CELLS)
            t = _bnorm(_bc_text(decomp[k]...))
            want = get(_BC_MOVE_DECOMPILED, c[1], "")
            t == want || println(stderr, "  (\"", c[1], "\", \"", escape_string(t), "\"),")
            @test t == want
        end
        # where a moved argument is not read again the bit is never set (`mark_bvar_access` gives
        # `nothing`) and the term stays in the head — upstream's, and swipl's clause/2
        mv1 = dclauses[findfirst(c -> c[1] == "compound", _BC_MOVE_CELLS)]
        @test mv1.flags & LK.CL_HEAD_TERMS != 0 && LK.mark_bvar_access(mv1) === nothing
        um1 = dclauses[findfirst(c -> c[1] == "then a use", _BC_MOVE_CELLS)]
        @test LK.mark_bvar_access(um1) == BitVector([true])
    end
    if _BC_SWIPL_BIN !== nothing
        @testset "the decompiled clauses are variants of swipl's clause/2" begin
            shows = [
                "bc_decomp(($(_bc_text(h, b))), ($(_bc_text(dh, db))))" for
                ((h, b), (dh, db)) in zip(dcases, decomp)
            ]
            theirs = _bc_swipl(shows)
            @test length(theirs) == length(shows)
            bad = 0
            for k in eachindex(shows)
                k <= length(theirs) || break
                if theirs[k] != ["same"]
                    bad += 1
                    bad <= 8 &&
                        println(stderr, "  ", _bc_text(dcases[k]...), "\n    ours  ",
                            _bc_text(decomp[k]...), "\n    swipl ", theirs[k],
                            "\n    code  ",
                            _bc_kernel(dclauses[k]))
                end
            end
            @test bad == 0
        end
    end
end

# ── V9d: the soft-cut `(A *-> B ; C)` and `(A *-> B)` ───────────────────────────────────────────
# `C_SOFTIF <A> C_SOFTCUT <B> C_JMP <C>` and `C_SOFTIFTHEN <A> C_SCUT <B> C_END`; a `!` in the
# condition of the first is `C_LSCUT`, of the second `C_LCUTIFTHEN`; never a fast condition.
# The cells are the conditionals' own, `->` turned into `*->` — so each has its hard twin above.
"`t` with every `->` at a control position turned into `*->`."
function _bcsoften(t::_B)::_B
    kind(t) === EXPR || return t
    h = child(t, 1)
    kind(h) === SYM || return t
    n = String(lk_name(h))
    n in (",", ";", "->", "\\+") || return t
    return _be(n == "->" ? "*->" : n, [_bcsoften(child(t, i)) for i in 2:nchildren(t)])
end
const _BC_SOFT_CELLS = [
    (n,
        _be("s" * String(lk_name(kind(h) === SYM ? h : child(h, 1))),
            kind(h) === SYM ? _B[] : [child(h, i) for i in 2:nchildren(h)]), _bcsoften(b))
    for
    (n, h, b) in _BC_ITE_CELLS
]

"A random body of `,`, `;`, `->`, `*->` and `\\+`: `_bcnotbody`'s, some of its `->` softened."
function _bcsoftbody(g::_BcGen, pool::Vector{_B}, depth::Int)::_B
    r = rand(g.rng)
    if depth < 4 && r < 0.22
        return _bf(";",
            _bf("*->", _bcsoftbody(g, pool, depth + 1), _bcsoftbody(g, pool, depth + 1)),
            _bcsoftbody(g, pool, depth + 1))
    elseif depth < 4 && r < 0.32
        return _bf("*->", _bcsoftbody(g, pool, depth + 1), _bcsoftbody(g, pool, depth + 1))
    elseif depth < 4 && r < 0.42
        return _bf(";",
            _bf("->", _bcsoftbody(g, pool, depth + 1), _bcsoftbody(g, pool, depth + 1)),
            _bcsoftbody(g, pool, depth + 1))
    elseif depth < 4 && r < 0.5
        return _bf("\\+", _bcsoftbody(g, pool, depth + 1))
    elseif depth < 4 && r < 0.58
        return _bf(";", _bcsoftbody(g, pool, depth + 1), _bcsoftbody(g, pool, depth + 1))
    elseif depth < 4 && r < 0.75
        return _bf(",", _bcsoftbody(g, pool, depth + 1), _bcsoftbody(g, pool, depth + 1))
    end
    return _bcorbody(g, pool, 4)                                # a goal
end

"A random rule clause `bs<k>(…) :- Body`, the body a soft-cut at the top or below a `,`."
function _bcsoftclause(g::_BcGen, k::Int)::Tuple{_B, _B}
    pool = _B[_bcfresh!(g) for _ in 1:rand(g.rng, 2:6)]
    har = rand(g.rng, 0:3)
    head = har == 0 ? _bs("bs$k") : _be("bs$k", [rand(g.rng, pool) for _ in 1:har])
    cond = _bcsoftbody(g, pool, 2)
    body = if rand(g.rng) < 0.7
        _bf(";", _bf("*->", cond, _bcsoftbody(g, pool, 2)), _bcsoftbody(g, pool, 2))
    else
        _bf("*->", cond, _bcsoftbody(g, pool, 2))
    end
    r = rand(g.rng)
    if r < 0.3
        body = _bf(",", body, _bcsoftbody(g, pool, 2))
    elseif r < 0.5
        body = _bf(",", _bcsoftbody(g, pool, 2), body)
    end
    return (head, body)
end

# Each cell's code, as the kernel AND swipl 10.1.17 gave it in one run (2026-10-12).
const _BC_SOFT_CODE = Dict{String, Vector{String}}(
    "if-then-else" =>
        [
            "i_enter",
            "c_softif(1,L1)",
            "b_var0",
            "i_call(P:[113]/1)",
            "c_softcut(1)",
            "l_nolco(L2)",
            "i_lcall(P:[114]/1)",
            "L2:",
            "b_var0",
            "i_depart(P:[114]/1)",
            "c_jmp(L3)",
            "L1:",
            "l_nolco(L4)",
            "i_lcall(P:[115]/1)",
            "L4:",
            "b_var0",
            "i_depart(P:[115]/1)",
            "L3:",
            "i_exit"
        ],
    "a fast condition" =>
        [
            "i_enter",
            "c_softif(1,L1)",
            "i_integer(0)",
            "b_eq_vc(0,i:1)",
            "c_softcut(1)",
            "l_nolco(L2)",
            "i_lcall(P:[114]/1)",
            "L2:",
            "b_var0",
            "i_depart(P:[114]/1)",
            "c_jmp(L3)",
            "L1:",
            "l_nolco(L4)",
            "i_lcall(P:[115]/1)",
            "L4:",
            "b_var0",
            "i_depart(P:[115]/1)",
            "L3:",
            "i_exit"
        ],
    "rational/1 is not fast" =>
        [
            "i_enter",
            "c_softif(1,L1)",
            "i_rational(0)",
            "c_softcut(1)",
            "l_nolco(L2)",
            "i_lcall(P:[114]/0)",
            "L2:",
            "i_depart(P:[114]/0)",
            "c_jmp(L3)",
            "L1:",
            "l_nolco(L4)",
            "i_lcall(P:[115]/0)",
            "L4:",
            "i_depart(P:[115]/0)",
            "L3:",
            "i_exit"
        ],
    "a cut in the condition" =>
        [
            "i_enter",
            "c_softif(1,L1)",
            "b_var0",
            "i_call(P:[113]/1)",
            "c_lscut(1)",
            "c_softcut(1)",
            "l_nolco(L2)",
            "i_lcall(P:[114]/1)",
            "L2:",
            "b_var0",
            "i_depart(P:[114]/1)",
            "c_jmp(L3)",
            "L1:",
            "l_nolco(L4)",
            "i_lcall(P:[115]/1)",
            "L4:",
            "b_var0",
            "i_depart(P:[115]/1)",
            "L3:",
            "i_exit"
        ],
    "if-then" =>
        [
            "i_enter",
            "c_softifthen(1)",
            "b_var0",
            "i_call(P:[113]/1)",
            "c_scut",
            "b_var0",
            "i_call(P:[114]/1)",
            "c_end",
            "l_nolco(L1)",
            "i_lcall(P:[115]/1)",
            "L1:",
            "b_var0",
            "i_depart(P:[115]/1)",
            "i_exit"
        ],
    "a cut in an if-then's condition" =>
        [
            "i_enter",
            "c_softifthen(1)",
            "b_var0",
            "i_call(P:[113]/1)",
            "c_lcutifthen(1)",
            "c_scut",
            "l_nolco(L1)",
            "i_lcall(P:[114]/1)",
            "L1:",
            "b_var0",
            "i_depart(P:[114]/1)",
            "c_end",
            "i_exit"
        ],
    "a variable to balance" =>
        [
            "i_enter",
            "c_softif(2,L1)",
            "b_var0",
            "i_call(P:[113]/1)",
            "c_softcut(2)",
            "b_unify_vc(1,i:1)",
            "c_jmp(L2)",
            "L1:",
            "i_true",
            "L2:",
            "l_nolco(L3)",
            "l_var(0,1)",
            "i_lcall(P:[117]/1)",
            "L3:",
            "b_var1",
            "i_depart(P:[117]/1)",
            "i_exit"
        ],
    "nested in then and in else" =>
        [
            "i_enter",
            "c_softif(0,L1)",
            "i_call(P:[97]/0)",
            "c_softcut(0)",
            "c_softif(1,L2)",
            "i_call(P:[98]/0)",
            "c_softcut(1)",
            "l_nolco(L3)",
            "i_lcall(P:[99]/0)",
            "L3:",
            "i_depart(P:[99]/0)",
            "c_jmp(L4)",
            "L2:",
            "l_nolco(L5)",
            "i_lcall(P:[100]/0)",
            "L5:",
            "i_depart(P:[100]/0)",
            "L4:",
            "c_jmp(L6)",
            "L1:",
            "c_softif(2,L7)",
            "i_call(P:[101]/0)",
            "c_softcut(2)",
            "l_nolco(L8)",
            "i_lcall(P:[102]/0)",
            "L8:",
            "i_depart(P:[102]/0)",
            "c_jmp(L6)",
            "L7:",
            "l_nolco(L9)",
            "i_lcall(P:[103]/0)",
            "L9:",
            "i_depart(P:[103]/0)",
            "L6:",
            "i_exit"
        ],
    "a disjunction as the condition" =>
        [
            "i_enter",
            "c_softif(0,L1)",
            "c_or(L2)",
            "i_call(P:[97]/0)",
            "c_jmp(L3)",
            "L2:",
            "i_call(P:[98]/0)",
            "L3:",
            "c_softcut(0)",
            "l_nolco(L4)",
            "i_lcall(P:[99]/0)",
            "L4:",
            "i_depart(P:[99]/0)",
            "c_jmp(L5)",
            "L1:",
            "l_nolco(L6)",
            "i_lcall(P:[100]/0)",
            "L6:",
            "i_depart(P:[100]/0)",
            "L5:",
            "i_exit"
        ],
    "a conditional as the condition" =>
        [
            "i_enter",
            "c_softif(0,L1)",
            "c_softif(1,L2)",
            "i_call(P:[97]/0)",
            "c_softcut(1)",
            "i_call(P:[98]/0)",
            "c_jmp(L3)",
            "L2:",
            "i_call(P:[99]/0)",
            "L3:",
            "c_softcut(0)",
            "l_nolco(L4)",
            "i_lcall(P:[100]/0)",
            "L4:",
            "i_depart(P:[100]/0)",
            "c_jmp(L5)",
            "L1:",
            "l_nolco(L6)",
            "i_lcall(P:[101]/0)",
            "L6:",
            "i_depart(P:[101]/0)",
            "L5:",
            "i_exit"
        ],
    "a cut in then is the clause's" =>
        [
            "i_enter",
            "c_softif(0,L1)",
            "i_call(P:[97]/0)",
            "c_softcut(0)",
            "i_cut",
            "c_jmp(L2)",
            "L1:",
            "i_call(P:[98]/0)",
            "L2:",
            "l_nolco(L3)",
            "i_lcall(P:[99]/0)",
            "L3:",
            "i_depart(P:[99]/0)",
            "i_exit"
        ],
    "a cut in else" =>
        [
            "i_enter",
            "c_softif(0,L1)",
            "i_call(P:[97]/0)",
            "c_softcut(0)",
            "l_nolco(L2)",
            "i_lcall(P:[98]/0)",
            "L2:",
            "i_depart(P:[98]/0)",
            "c_jmp(L3)",
            "L1:",
            "i_cut",
            "L3:",
            "i_exit"
        ],
    "if-then as a disjunction's right side" =>
        [
            "i_enter",
            "c_or(L1)",
            "i_call(P:[97]/0)",
            "c_jmp(L2)",
            "L1:",
            "c_softifthen(0)",
            "i_call(P:[98]/0)",
            "c_scut",
            "l_nolco(L3)",
            "i_lcall(P:[99]/0)",
            "L3:",
            "i_depart(P:[99]/0)",
            "c_end",
            "L2:",
            "i_exit"
        ],
    "the condition binds a variable used after" =>
        [
            "i_enter",
            "c_softif(2,L1)",
            "b_firstvar(1)",
            "i_call(P:[113]/1)",
            "c_softcut(2)",
            "b_var1",
            "i_call(P:[114]/1)",
            "c_jmp(L2)",
            "L1:",
            "b_unify_fc(1,i:0)",
            "L2:",
            "b_var1",
            "b_var0",
            "i_depart(P:[115]/2)",
            "i_exit"
        ],
    "a fast condition on var/1" =>
        [
            "i_enter",
            "c_softif(2,L1)",
            "i_var(0)",
            "c_softcut(2)",
            "b_unify_vc(1,a:[97])",
            "c_jmp(L2)",
            "L1:",
            "b_unify_vc(1,a:[98])",
            "L2:",
            "i_exit"
        ],
    "two conditionals in a row" =>
        [
            "i_enter",
            "c_softif(0,L1)",
            "i_call(P:[97]/0)",
            "c_softcut(0)",
            "i_call(P:[98]/0)",
            "c_jmp(L2)",
            "L1:",
            "i_call(P:[99]/0)",
            "L2:",
            "c_softif(1,L3)",
            "i_call(P:[100]/0)",
            "c_softcut(1)",
            "l_nolco(L4)",
            "i_lcall(P:[101]/0)",
            "L4:",
            "i_depart(P:[101]/0)",
            "c_jmp(L5)",
            "L3:",
            "l_nolco(L6)",
            "i_lcall(P:[102]/0)",
            "L6:",
            "i_depart(P:[102]/0)",
            "L5:",
            "i_exit"
        ],
    "== as the condition" =>
        [
            "i_enter",
            "c_softif(2,L1)",
            "b_eq_vv(0,1)",
            "c_softcut(2)",
            "l_nolco(L2)",
            "i_lcall(P:[97]/0)",
            "L2:",
            "i_depart(P:[97]/0)",
            "c_jmp(L3)",
            "L1:",
            "l_nolco(L4)",
            "i_lcall(P:[98]/0)",
            "L4:",
            "i_depart(P:[98]/0)",
            "L3:",
            "i_exit"
        ],
    "a chain of conditions" =>
        [
            "i_enter",
            "c_softif(2,L1)",
            "b_neq_vv(0,1)",
            "c_softcut(2)",
            "l_nolco(L2)",
            "i_lcall(P:[97]/0)",
            "L2:",
            "i_depart(P:[97]/0)",
            "c_jmp(L3)",
            "L1:",
            "c_softif(3,L4)",
            "b_eq_vc(0,a:[97])",
            "c_softcut(3)",
            "l_nolco(L5)",
            "i_lcall(P:[98]/0)",
            "L5:",
            "i_depart(P:[98]/0)",
            "c_jmp(L3)",
            "L4:",
            "l_nolco(L6)",
            "i_lcall(P:[99]/0)",
            "L6:",
            "i_depart(P:[99]/0)",
            "L3:",
            "i_exit"
        ],
    "if-then on a test: never fast" =>
        [
            "i_enter",
            "c_softifthen(1)",
            "i_atom(0)",
            "c_scut",
            "l_nolco(L1)",
            "i_lcall(P:[113]/1)",
            "L1:",
            "b_var0",
            "i_depart(P:[113]/1)",
            "c_end",
            "i_exit"
        ],
    "a fast condition, then a call that is not" =>
        [
            "i_enter",
            "c_softif(1,L1)",
            "i_atom(0)",
            "b_var0",
            "i_call(P:[113]/1)",
            "c_softcut(1)",
            "l_nolco(L2)",
            "i_lcall(P:[97]/0)",
            "L2:",
            "i_depart(P:[97]/0)",
            "c_jmp(L3)",
            "L1:",
            "l_nolco(L4)",
            "i_lcall(P:[98]/0)",
            "L4:",
            "i_depart(P:[98]/0)",
            "L3:",
            "i_exit"
        ]
)
# What `decompile!` rebuilds from each cell, variables renamed in order — variants of swipl's clause/2.
const _BC_SOFT_DECOMPILED = Dict{String, String}(
    "if-then-else" => "':-'(si1(A),';'('*->'(q(A),r(A)),s(A)))",
    "a fast condition" => "':-'(si2(A),';'('*->'(','(integer(A),'=='(A,1)),r(A)),s(A)))",
    "rational/1 is not fast" => "':-'(si3(A),';'('*->'(rational(A),r),s))",
    "a cut in the condition" => "':-'(si4(A),';'('*->'(','(q(A),'!'),r(A)),s(A)))",
    "if-then" => "':-'(si5(A),','('*->'(q(A),r(A)),s(A)))",
    "a cut in an if-then's condition" => "':-'(si6(A),'*->'(','(q(A),'!'),r(A)))",
    "a variable to balance" => "':-'(si7(A,B),','(';'('*->'(q(A),'='(B,1)),true),u(B)))",
    "nested in then and in else" => "':-'(si8,';'('*->'(a,';'('*->'(b,c),d)),';'('*->'(e,f),g)))",
    "a disjunction as the condition" => "':-'(si9,';'('*->'(';'(a,b),c),d))",
    "a conditional as the condition" => "':-'(si10,';'('*->'(';'('*->'(a,b),c),d),e))",
    "a cut in then is the clause's" => "':-'(si11,','(';'('*->'(a,'!'),b),c))",
    "a cut in else" => "':-'(si12,';'('*->'(a,b),'!'))",
    "if-then as a disjunction's right side" => "':-'(si13,';'(a,'*->'(b,c)))",
    "the condition binds a variable used after" => "':-'(si14(A),','(';'('*->'(q(B),r(B)),'='(B,0)),s(B,A)))",
    "a fast condition on var/1" => "':-'(si15(A,B),';'('*->'(var(A),'='(B,a)),'='(B,b)))",
    "two conditionals in a row" => "':-'(si16,','(';'('*->'(a,b),c),';'('*->'(d,e),f)))",
    "== as the condition" => "':-'(si17(A,B),';'('*->'('=='(A,B),a),b))",
    "a chain of conditions" => "':-'(si18(A,B),';'('*->'('\\\\=='(A,B),a),';'('*->'('=='(A,a),b),c)))",
    "if-then on a test: never fast" => "':-'(si19(A),'*->'(atom(A),q(A)))",
    "a fast condition, then a call that is not" => "':-'(si20(A),';'('*->'(','(atom(A),q(A)),a),b))"
)

@testset "the soft-cut compiles as swipl's (V9d)" begin
    ours = [_bc_kernel(_bclause(h, b)) for (_, h, b) in _BC_SOFT_CELLS]
    # pinned from the run in which every cell was identical to swipl's code (the jobs without
    # swipl check these)
    for (k, c) in enumerate(_BC_SOFT_CELLS)
        want = get(_BC_SOFT_CODE, c[1], String[])
        ours[k] == want || println(stderr, "  CODE (\"", c[1], "\", ", repr(ours[k]), "),")
        @test ours[k] == want
    end
    g = _BcGen(Xoshiro(20261017), UInt64(150_000))
    random = [_bcsoftclause(g, k) for k in 1:400]
    rours = [_bc_kernel(_bclause(h, b)) for (h, b) in random]
    @testset "the random bodies exercise it" begin
        used = union((_bc_names(c) for c in rours)...)
        missing_ = setdiff(
            ["c_softif", "c_softcut", "c_softifthen", "c_scut", "c_lscut", "c_lcutifthen",
                "c_ifthenelse", "c_not", "c_or", "c_end", "c_var"], used)
        isempty(missing_) || println(stderr, "  not exercised: ", missing_)
        @test isempty(missing_)
        @test !any(c -> any(startswith("c_fastcond"), c), ours)     # a soft condition is never fast
    end
    dcases = [[(h, b) for (_, h, b) in _BC_SOFT_CELLS]; random]
    dclauses = [_bclause(h, b) for (h, b) in dcases]                # the default flags
    decomp = [
        try
            _bdecompile(cl, h)
        catch
            println(
                stderr, "  decompiling ", _bc_text(h, b), "\n    code ", _bc_kernel(cl)
            )
            rethrow()
        end for (cl, (h, b)) in zip(dclauses, dcases)
    ]
    @testset "the decompiler: pinned clauses" begin
        for (k, c) in enumerate(_BC_SOFT_CELLS)
            t = _bnorm(_bc_text(decomp[k]...))
            want = get(_BC_SOFT_DECOMPILED, c[1], "")
            t == want ||
                println(stderr, "  DEC (\"", c[1], "\", \"", escape_string(t), "\"),")
            @test t == want
        end
    end
    if _BC_SWIPL_BIN !== nothing
        @testset "the decompiled clauses are variants of swipl's clause/2" begin
            shows = [
                "bc_decomp(($(_bc_text(h, b))), ($(_bc_text(dh, db))))" for
                ((h, b), (dh, db)) in zip(dcases, decomp)
            ]
            theirs = _bc_swipl(shows)
            @test length(theirs) == length(shows)
            bad = 0
            for k in eachindex(shows)
                k <= length(theirs) || break
                if theirs[k] != ["same"]
                    bad += 1
                    bad <= 5 &&
                        println(stderr, "  ", _bc_text(dcases[k]...), "\n    ours  ",
                            _bc_text(decomp[k]...), "\n    swipl ", theirs[k])
                end
            end
            @test bad == 0
        end
        @testset "identical to swipl" begin
            all_ = [[(h, b) for (_, h, b) in _BC_SOFT_CELLS]; random]
            allours = [ours; rours]
            theirs = _bc_swipl(["bc_case_show(($(_bc_text(h, b))))" for (h, b) in all_])
            @test length(theirs) == length(all_)
            bad = 0
            for k in eachindex(all_)
                k <= length(theirs) || break
                if allours[k] != theirs[k]
                    bad += 1
                    bad <= 5 && println(stderr, "  ", _bc_text(all_[k]...), "\n    ours  ",
                        allours[k], "\n    swipl ", theirs[k])
                end
            end
            @test bad == 0
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

@testset "what is still refused (V2's interim; V6b, V6b2, V9a: the inline compilers decide), and swipl's type_error(callable, Body)" begin
    p = _bs("pr")
    for body in (
        _bf(":", _bs("m"), _bs("g")), _bf("@", _bs("g"), _bs("m")),
        _bconj(_bs("q"), _bs("\$reset"))                       # a reserved goal atom (V9)
    )
        @test_throws LK.NotPortedError _bclause(p, body)
    end
    # since V9a `true` and `fail` compile to I_TRUE and I_FAIL, as swipl's do
    # since V9f `\$catch` compiles to I_CATCH I_EXITCATCH (c:3539): boot/init.pl's catch/3 is `\$catch`
    tf = [
        (_bs("pt1"), _bconj(_bs("q"), _bs("true"))), (_bs("pt2"), _bs("fail")),
        (_bf("pt3", _bv(1), _bv(2), _bv(3)), _bs("\$catch")),
        (_bs("pt4"), _bconj(_bs("q"), _bs("\$catch"))),
        # since V9g `\$call_cleanup` compiles to I_CALLCLEANUP I_EXITCLEANUP (c:3547): boot/init.pl's
        # setup_call_cleanup/3 is `sig_atomic(Setup), '\$call_cleanup'`
        (
            _bf("pt5", _bv(1), _bv(2), _bv(3)),
            _bconj(_bf("sig_atomic", _bv(1)), _bs("\$call_cleanup"))
        ),
        (_bf("pt6", _bv(1), _bv(2)), _bs("\$call_cleanup"))
    ]
    ours_tf = [_bc_kernel(_bclause(h, b)) for (h, b) in tf]
    @test any(startswith("i_true"), ours_tf[1]) && any(startswith("i_fail"), ours_tf[2])
    @test ours_tf[3] == ["i_enter", "i_catch", "i_exitcatch", "i_exit"]     # c:3540-3541, then compileClause's I_EXIT
    if _BC_SWIPL_BIN !== nothing
        @test _bc_swipl(["bc_case_show(($(_bc_text(h, b))))" for (h, b) in tf]) == ours_tf
    end
    # type_error(callable, Body): the WHOLE body, as swipl 10.1.16 reports it (probed) — raised
    # with PL_error (since V9c): compileClause answers `nothing`, the error pending in its local data
    "The error compiling `pr :- body` raises, in a local data of its own; `nothing` if none."
    function clause_error(body)
        ld = LK.PL_local_data{_B}(_BGD)
        user = LK.MODULE_user(_BGD)
        cl = LK.compileClause(_BGD, ld, p, body, LK.lookupProcedure(p, 0, user), user)
        (cl === nothing && ld.exception_term != 0) || return nothing
        return lk_answer(ld, ld.exception_term)
    end
    for body in (
        _bconj(_bs("q"), _bv(1)),                               # p :- q, _
        _bconj(_bs("q"), _bg(1)),                               # p :- q, 1
        _bconj(_bs("q"), _bconj(_bs("r"), _bg("s"))),           # p :- q, r, "s"
        mk_nil(_B),                                             # p :- []
        _bconj(_bs("q"), mk_expr(_B, _B[_bv(1), _bs("a")]))     # p :- q, (X a): `$expr/2`
    )
        # a VARIANT of the body: the ball is a copy with fresh variables (copy_exception:
        # duplicate_term, pl-fli.c; since V9f)
        ball = clause_error(body)
        @test ball !== nothing &&
            LK.is_variant_ptr(child(ball, 2), _bf("type_error", _bs("callable"), body))
        kind(body) === EXPR && !is_ground(body) &&
            @test !lk_eq(child(ball, 2), _bf("type_error", _bs("callable"), body))
    end
    # representation_error(max_procedure_arity): a goal of 1025 arguments (MAXARITY)
    ball = clause_error(_be("q", [_bg(1) for _ in 1:(LK.MAXARITY + 1)]))
    @test ball !== nothing &&
        lk_eq(child(ball, 2), _bf("representation_error", _bs("max_procedure_arity")))
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
        gd, LK.PL_local_data{O}(gd), lk_sym(O, :po), mk_expr(O, O[lk_sym(O, :q), v]), po,
        user
    )
    i = findfirst(==(LK.L_ATOM), cl.codes)
    j = findfirst(==(LK.B_ATOM), cl.codes)
    @test i !== nothing && j !== nothing && cl.codes[i + 2] == cl.codes[j + 1]
    @test cl.literals[LK.atom_literal(cl.codes[j + 1])] === v
    @test LK.atom_operand_word(cl.codes[j + 1]) == 0        # an opaque literal: no atom word
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

# ── the meta-call of plain goals (V9e-1): a variable goal and call/N compile as swipl's ──────────
# A variable goal is `I_CALL1` after its argument, `call/1` the same, `call/N` is `I_CALLN N-1`
# (pl-comp.c compileSubClause); a void variable stays a type error. Each cell's code is compared
# whole with swipl's (the cells run in the meta-call's own file too: test/core_lang/test_metacall.jl).
const _BC_META_CELLS = let X = _bv(1), Y = _bv(2), Z = _bv(3), G = _bv(4)
    [
        ("a variable goal", _bf("mv1", G), G),
        ("a variable goal, not last", _bf("mv2", G, X), _bconj(G, _bf("=", X, _bs("a")))),
        ("a variable goal after a goal", _bf("mv3", G), _bconj(_bs("a"), G, _bs("b"))),
        (
            "a variable goal built in the body",
            _bf("mv4", X),
            _bconj(_bf("=", G, _bf("p", X)), G)
        ),
        ("call/1", _bf("mc1", G), _bf("call", G)),
        ("call/1 of a callable", _bs("mc2"), _bf("call", _bs("a"))),
        ("call/1 of a compound", _bf("mc3", X), _bf("call", _bf("p", X, _bs("b")))),
        ("call/2", _bf("mc4", G, X), _bf("call", G, X)),
        ("call/3", _bf("mc5", G, X, Y), _bf("call", G, X, Y)),
        ("call/8", _bf("mc6", G, X), _bf("call", G, X, X, X, X, X, X, X)),
        ("call/N not last", _bf("mc7", G, X), _bconj(_bf("call", G, X), _bs("a"))),
        ("call/1 twice", _bf("mc8", G, Z), _bconj(_bf("call", G), _bf("call", Z))),
        ("call/2 with a constant", _bf("mc9", G), _bf("call", G, _bg(1))),
        (
            "a variable that is a goal and an argument",
            _bf("mv5", G),
            _bconj(_bf("p", G), G)
        )
    ]
end

@testset "a variable goal and call/N compile as swipl's (V9e-1)" begin
    ours = [_bc_kernel(_bclause(h, b)) for (_, h, b) in _BC_META_CELLS]
    for (k, (shape, _, _)) in enumerate(_BC_META_CELLS)
        @test any(startswith(c, "i_call1") || startswith(c, "i_calln") for c in ours[k])
    end
    @test any(c -> any(startswith("i_call1"), c), ours) &&
        any(c -> any(startswith("i_calln"), c), ours)
    # a void variable is no goal
    let ld = LK.PL_local_data{_B}(_BGD), user = LK.MODULE_user(_BGD), h = _bf("mv0", _bv(1))
        @test LK.compileClause(
            _BGD, ld, h, _bv(2), LK.lookupProcedure(_bs("mv0"), 1, user), user
        ) ===
              nothing && ld.exception_term != 0
    end
    if _BC_SWIPL_BIN !== nothing
        theirs = _bc_swipl([
            "bc_case_show(($(_bc_text(h, b))))" for (_, h, b) in _BC_META_CELLS
        ])
        @test length(theirs) == length(_BC_META_CELLS)
        for (k, (shape, _, _)) in enumerate(_BC_META_CELLS)
            k <= length(theirs) || break
            ours[k] == theirs[k] ||
                println(
                    stderr, "  ", shape, "\n    ours  ", ours[k], "\n    swipl ", theirs[k]
                )
            @test ours[k] == theirs[k]
        end
    elseif _BC_SWIPL_REQUIRED
        @test false
    end
end
