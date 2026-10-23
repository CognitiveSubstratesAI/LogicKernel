# ORIGINAL: L1d step 7b — the writer on TERM REFERENCES (pl-write.c: writeTerm2, writeTermResume, writeTerm,
# writeTopTerm, writePrimitive, writeNumberVar, isBlockOp, the list and operator helpers, over the FLI readers
# PL_get_name_arity, _PL_get_arg, PL_get_list, PL_get_nil, PL_is_functor, PL_is_pair, PL_get_atom, PL_is_variable,
# PL_is_atom, PL_is_integer, PL_is_number, PL_is_string); the workspace's L1_plan/stageL1d_design.md §3g (7b) and
# §3h. Upstream's writer reads the term through the FLI on `term_t` and reads words only in `var_name_ptr` and
# writeNumberVar; ours read TERMS until 7b phase 2 (every compound it met a cold export) and reads the term
# references since, as upstream.
# test/core_lang/test_write_cells.jl — on every term type:
#   * the write family against swipl on terms BUILT BY CLAUSE BODIES (the cells): write/1, writeq/1, print/1,
#     write_canonical/1 and write_term/2 with quoted, ignore_ops, max_depth, variable_names, numbervars
#     true/false (the frame's older '$VAR' a term, its newer one a name), brace_terms, dotlists, no_lists,
#     spacing; operators (prefix, postfix, infix, negative numbers, the block operators `[](L, …)` and
#     `{}({…}, …)`, operator atoms as arguments), lists with tails, `{a,b}`, floats, integers past the tagged
#     range, strings, quoted atoms. The expected text is swipl's (`swipl -q -g main -t halt` on the same
#     program); a fresh variable's name differs between the systems (`_` and a number), so each is renamed by
#     its first occurrence on both sides before the texts are compared;
#   * kernel-only cases: a `$expr/n` compound (no symbol head — swipl has no such term), its text pinned; the
#     boundary (a slot's side value, a keyed variable), written as the same term on the cells, counted;
#   * the meter: writeq of an operator term, a list and a nested compound in a loop to a null stream — the
#     cold exports, imports, variable reads and boundary pairs PINNED: none since 7b phase 2.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

# ── the write family: the text, as swipl writes it ──────────────────────────────────────────────
# Each `wN/0` builds its terms in the clause body (on the cells) and writes them; the kernel and swipl
# run the same text, the output and the verdict compared per goal. The operator directives come first:
# both sides read every clause after them.
const _WC_PROGRAM = raw"""
:- op(200, xf, ++).
:- op(700, fx, ~~).
w1 :- T = f(X, g(Y, X), [Z, a, 1]), numbervars(T, 0, _), write(T), nl, writeq(T), nl, print(T), nl,
    write_canonical(T), nl.
w2 :- T = f('A', 'b c', "str", [], '[]', {}, '{}', 'hello'(world), 'it''s'), write(T), nl, writeq(T), nl,
    print(T), nl.
w3 :- writeq(-(1)), nl, writeq(-(-(1))), nl, writeq(-(a)), nl, writeq(-(-(a))), nl, writeq(1 - -1), nl,
    writeq(1 - (-(1))), nl, writeq(a- (-a)), nl, writeq(\+a), nl, writeq(\+ (a,b)), nl, writeq(-(1.0)), nl,
    writeq(- (-1)), nl, writeq(-(-(-(1)))), nl, writeq(- a + b), nl, writeq(-(a+b)), nl.
w4 :- writeq(1+2*3-4), nl, writeq((1+2)*3), nl, writeq(2**(-1)), nl, writeq(2^3^4), nl, writeq((2^3)^4), nl,
    writeq(a=b), nl, writeq((a:-b,c;d->e)), nl, writeq(f((a,b))), nl, writeq(f((a:-b))), nl,
    writeq([(a:-b),(c,d)]), nl, writeq(a mod b), nl, writeq(- (2^2)), nl, writeq((-2)^2), nl,
    writeq(-(2)^2), nl, writeq(1 + -2), nl, writeq(1*(-1)), nl, writeq((-1)*1), nl, writeq(a:b:c), nl,
    writeq((a:b):c), nl, writeq(1-(2-3)), nl, writeq((1-2)-3), nl.
w5 :- writeq(f(-)), nl, writeq(f(;)), nl, writeq(f(',')), nl, writeq(','(a,b,c)), nl, writeq((a|b)), nl,
    writeq('|'(a,b)), nl, writeq(f(:-)), nl, writeq([-]), nl, writeq(- - -), nl, writeq(-(-)), nl,
    writeq(f(!, ;, [], {})), nl, writeq((:- a)), nl, writeq(f(:- a)), nl, writeq(- = -), nl,
    writeq(f(=, \=)), nl, writeq([a= \+]), nl, writeq(\+ (-)), nl.
w6 :- writeq(a ++), nl, writeq((a ++) ++), nl, writeq(f(a ++)), nl, writeq(- (a ++)), nl, writeq(1 ++), nl,
    writeq((- 1) ++), nl, writeq((a+b) ++), nl, writeq(++), nl, writeq(f(++)), nl, writeq(- ++), nl,
    writeq(~~ a), nl, writeq(~~ (~~ a)), nl, writeq(~~ (a = b)), nl, writeq(~~ (-1)), nl, writeq(~~), nl,
    T = f(X), numbervars(T, 0, _), writeq(X ++), nl, writeq(~~ X), nl.
w7 :- X = [a, b | T], writeq(X), nl, T = [c], writeq(X), nl, writeq([a|b]), nl, writeq([[a],[]|[c]]), nl,
    writeq([a|'[]']), nl, writeq('[|]'(a, b)), nl, writeq('[|]'), nl, writeq([1,2|3]), nl,
    print([a-1,"s"|x]), nl, write([a, 'B c', "d"|e]), nl, writeq([[]]), nl, writeq([{}]), nl.
w8 :- writeq({a,b}), nl, writeq({}), nl, writeq('{}'(x)), nl, writeq({(a:-b)}), nl, writeq('{}'(a,b)), nl,
    writeq(f({a})), nl, writeq({-}), nl, writeq({[]}), nl, writeq({{a}}), nl, T = f(X), numbervars(T, 0, _),
    writeq({X}), nl.
w9 :- write_term(f('A', 'b c', "s", 'it''s', '\n', []), [quoted(true)]), nl,
    write_term(f('A', 'b c', "s", 'it''s'), [quoted(false)]), nl, write_term('hello world', []), nl,
    write_term([a, 'B'|'C'], [quoted(true)]), nl.
w10 :- write_term(1+2*a, [ignore_ops(true)]), nl, write_term([1,2], [ignore_ops(true)]), nl,
    write_term({a}, [ignore_ops(true)]), nl, write_term(- 1, [ignore_ops(true)]), nl,
    write_term(-(1), [ignore_ops(true)]), nl, write_term(a- (-1), [ignore_ops(true)]), nl,
    write_term((a,b), [ignore_ops(true), quoted(true)]), nl, write_term(-(-(a)), [ignore_ops(true)]), nl,
    write_term(a ++, [ignore_ops(true)]), nl.
w11 :- write_term(f(g(h(i(j)))), [max_depth(3)]), nl, write_term([1,2,3,4,5,6,7,8,9], [max_depth(3)]), nl,
    write_term(f([a,b,c,d], g(h(i))), [max_depth(2)]), nl, write_term(1+2+3+4+5, [max_depth(3)]), nl,
    write_term('hello world', [max_depth(1), quoted(true)]), nl, write_term({a,b,c}, [max_depth(2)]), nl,
    write_term([[1,2,3],[4,5,6]], [max_depth(2)]), nl, write_term(- (- (- a)), [max_depth(2)]), nl.
w12 :- T = f(X, Y, Z, X), write_term(T, [variable_names(['X'=X, 'Foo'=Y, 'Z'=Z])]), nl,
    write_term(T, [variable_names(['X'=X, 'Y'=Y, 'Z'=Z]), quoted(true)]), nl,
    write_term(g(X), [variable_names(['_X'=X])]), nl, write_term(h(X, Y), [variable_names(['X'=X])]), nl,
    write_term(T, [variable_names(['X'=X, 'Y'=X, 'Z'=Z])]), nl.
w13 :- T = f(X, Y, '$VAR'(25), '$VAR'(26), '$VAR'('Foo'), '$VAR'(x)), numbervars(T, 0, E),
    write_term(T, [numbervars(true)]), nl, write_term(T, [numbervars(false)]), nl,
    write_term(T, [numbervars(false), quoted(true)]), nl, write_term(T, [numbervars(true), quoted(true)]), nl,
    writeq(E), nl.
w14 :- writeq('$VAR'(-1)), nl, writeq('$VAR'("Foo")), nl, writeq('$VAR'(1.0)), nl, writeq('$VAR'(a,b)), nl,
    writeq('$VAR'('_')), nl, writeq('$VAR'('_G1')), nl, print('$VAR'(52)), nl, write('$VAR'(27)), nl,
    writeq(f('$VAR'(1), -('$VAR'(2)))), nl, writeq('$VAR'(f(x))), nl, writeq('$VAR'(1152921504606846976)), nl,
    writeq('$VAR'('Foo Bar')), nl, writeq('$VAR'('?x')), nl, writeq(- '$VAR'(1)), nl, writeq('$VAR'(1) ++), nl.
w15 :- T = f('$VAR'(1), X, '$VAR'('Foo')), write_term(T, [variable_names(['X'=X]), quoted(true)]), nl,
    write_term(T, [variable_names(['X'=X]), numbervars(true), quoted(true)]), nl,
    write_term(T, [variable_names(['X'=X])]), nl,
    T2 = g(A, B), numbervars(T2, 0, _), write_term(h(T2, C), [variable_names(['C'=C]), quoted(true)]), nl,
    write_term(h(T2, C), [variable_names(['C'=C]), numbervars(true)]), nl.
w16 :- write_term({a,b}, [brace_terms(false)]), nl, write_term('{}'(x), [brace_terms(false), quoted(true)]), nl,
    write_term({a}, [brace_terms(true)]), nl, write_term(f({a}), [brace_terms(false), quoted(true)]), nl.
w17 :- write_term([a,b|c], [dotlists(true)]), nl, write_term([a,b], [dotlists(true)]), nl,
    write_term([a,[b]], [dotlists(true), quoted(true)]), nl, write_term([], [dotlists(true)]), nl,
    write_term([a,b], [no_lists(true)]), nl, write_term(f([a]), [no_lists(true), quoted(true)]), nl.
w18 :- writeq(1.0), nl, writeq(-0.0), nl, writeq(1.0e10), nl, writeq(1.5e-7), nl, writeq(3.141592653589793), nl,
    writeq(- 1.0), nl, writeq(-(1.0)), nl, writeq(1 - 1.0), nl, writeq(f(1.0e300, 0.1)), nl, write(2.5), nl,
    X is 1.0e14 * 10, writeq(X), nl, writeq(0.3333333333333333), nl, writeq(- (0.0)), nl, writeq(1.0e-300), nl.
w19 :- writeq("abc"), nl, write("abc"), nl, print("a\nb"), nl, writeq("it's"), nl, writeq(""), nl,
    writeq(f("x", "y z")), nl, writeq('\n'), nl, writeq('a\\b'), nl, writeq(['\t', ' ', '']), nl,
    writeq("'q'"), nl, writeq('"'), nl, writeq('a"b'), nl, write(f("x", 'y z')), nl.
w20 :- writeq(0), nl, writeq(-1), nl, writeq(1152921504606846976), nl, writeq(4611686018427387903), nl,
    writeq(-4611686018427387904), nl, writeq(9223372036854775807), nl, writeq(-9223372036854775807), nl,
    writeq(- 9223372036854775807), nl, writeq(1 - -9223372036854775807), nl, writeq(f(72057594037927936)), nl,
    writeq(- (72057594037927936)), nl.
w21 :- X = []([1,2], a), writeq(X), nl, Y = '{}'({a}, b), writeq(Y), nl, Z = []([1], a, b), writeq(Z), nl,
    W = '{}'(x, b), writeq(W), nl, V = [](x, a), writeq(V), nl, U = []([1]), writeq(U), nl.
w22 :- write_term(f(a,b,[c,d]), [spacing(next_argument)]), nl, write_term(1+2, [spacing(next_argument)]), nl,
    write_term({a,b}, [spacing(next_argument)]), nl.
w23 :- length(L, 300), numbervars(L, 0, _), writeq(L), nl, length(M, 30), writeq(f(M)), nl.
w24 :- writeq([aB, 'Ab', 'a b', [], '[]', '{}', '!', ';', ',', '|', 'a.b', '.', 'hello'('W'), aé, 'é']), nl,
    writeq(f(a+b, (a:-b), [a|b], {c}, "s", 1.5, -3)), nl, print(g(h(i(j(k))), [l|m])), nl.
w25 :- writeq(a->b;c), nl, writeq((a*->b;c)), nl, writeq(?-(a)), nl, writeq(dynamic(a)), nl,
    writeq((dynamic a, b)), nl, writeq(1 = 2), nl, writeq(a\=b), nl, writeq(a=..b), nl, writeq([a]=[b]), nl,
    writeq(f(a;b)), nl, writeq([a=b,c|d]), nl, writeq(\+ \+ a), nl, writeq(@(a)), nl, writeq(@(a, b)), nl.
w26 :- T = f(X, Y, X), print(T), nl, writeq(T), nl, write(T), nl, writeq([X, Y|X]), nl, writeq(X+Y), nl,
    writeq(- X), nl, writeq({X, Y}), nl, writeq(X ++), nl, print(T-Y), nl.
w27 :- write_term(f(X, '$VAR'(1), "s", 'a b'), [portray(true), numbervars(true)]), nl,
    write_term(f('$VAR'(1), 'a b'), [portray(true), numbervars(true), quoted(true)]), nl.
"""
const _WC_GOALS = ["w$i" for i in 1:27]
const _WC_DRIVER = raw"""
:- style_check(-singleton).
run(G) :- ( catch(G, E, true) -> ( var(E) -> true ; ex(E) ) ; write('FAIL') ), nl, write('---'), nl.
ex(error(F, _)) :- !, write('EX '), write_canonical(F).
ex(E) :- write('EX '), write_canonical(E).
"""

"The kernel's text for `name/0` loaded in `db`: its output, then the verdict and `---`, as `_WC_DRIVER`'s `run/1`."
function _wc_run(db::_RDB, name::String)::String
    gd, ld = db.gd, db.ld
    out = IOBuffer()
    LK.set_standard_stream!(ld, LK.SNO_USER_OUTPUT, out)
    proc = LK.lookupProcedure(_rs(name), 0, db.user)
    fid = LK.PL_open_foreign_frame(ld)
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, 0
    )
    verdict = try
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            ""
        elseif rc == LK.PL_S_EXCEPTION
            ball = lk_answer(ld, LK.PL_exception(ld, qid))
            f =
                if (
                    kind(ball) === EXPR && nchildren(ball) == 3 &&
                    _ratom_text(child(ball, 1)) == "error"
                )
                    child(ball, 2)
                else
                    ball
                end
            "EX " * _rcanonical(f)
        else
            "FAIL"
        end
    catch e
        e isa LK.NotPortedError || rethrow()
        "NOTPORTED"
    end
    verdict == "NOTPORTED" || LK.PL_close_query(ld, qid)
    LK.PL_discard_foreign_frame(ld, fid)
    LK.Sflush(LK.Suser_output(ld))
    return String(take!(out)) * verdict * "\n---\n"
end

"A database with `text` loaded through load_file!."
function _wc_load(text::String)::_RDB
    db = _RDB()
    f = joinpath(mktempdir(), "wc.pl")
    write(f, text)
    st, ball, msgs = LK.load_file!(db.gd, db.ld, f)
    @test st === :ok && all(m -> m[1] === :warning, msgs)     # (the singleton warnings)
    return db
end

# A fresh variable is written `_` and a number on both sides, but not the same number: each is renamed
# `_V1`, `_V2`, … by its first occurrence in a goal's text (a `_` after a letter, a digit or `_` — as in
# `S_1`, numbervars' negative name — is no variable).
"`text` with each fresh variable name renamed by its first occurrence."
function _wc_norm(text::AbstractString)::String
    names = Dict{String, String}()
    return replace(
        text,
        r"(?<![A-Za-z0-9_'])_G?[0-9]+" =>
            s -> get!(() -> "_V$(length(names) + 1)", names, String(s))
    )
end

"swipl's text for `goals` of `program`, one `run/1` each, split per goal (each ends in `---\\n`)."
function _wc_swipl(program::String, goals::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "w.pl")
        write(
            f,
            _WC_DRIVER * program * "main :- " * join(("run($g)" for g in goals), ", ") *
            ".\n"
        )
        read(
            pipeline(
                ignorestatus(`swipl -q -g main -t halt $f`); stdin=devnull, stderr=devnull
            ),
            String
        )
    end
    parts = split(out, "---\n")
    return [String(p) * "---\n" for p in parts[1:(end - 1)]]
end

@testset "the write family on cells, as swipl writes it" begin
    db = _wc_load(_WC_PROGRAM)
    ours = [_wc_norm(_wc_run(db, g)) for g in _WC_GOALS]
    # the kernel's side alone (also where swipl is absent: Pkg.test) — a few lines, each from swipl
    @test startswith(
        ours[1], "f(A,g(B,A),[C,a,1])\nf(A,g(B,A),[C,a,1])\nf(A,g(B,A),[C,a,1])\n"
    )
    @test all(o -> !occursin("NOTPORTED", o), ours)
    # every goal loaded and ran (a clause the reader refused would be an existence error on both sides)
    @test !any(o -> occursin("existence_error(procedure", o), ours)
    @test ours[8] ==
        "{a,b}\n{}\n{x}\n{a:-b}\n{}(a,b)\nf({a})\n{-}\n{[]}\n{{a}}\n{A}\n\n---\n"
    if _R_SWIPL
        theirs = [_wc_norm(t) for t in _wc_swipl(_WC_PROGRAM, _WC_GOALS)]
        @test length(theirs) == length(_WC_GOALS)
        for (i, g) in enumerate(_WC_GOALS)
            o, s = ours[i], get(theirs, i, "—")
            @test o == s
            o == s || @info "the write family: $g differs" ours = o swipl = s
        end
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

# The block operators (pl-write.c isBlockOp): with `[]` and `{}` postfix operators, `[](List, X)` is written
# `X[…]` and `{}({…}, X)` `X {…}` — and the `[]` atom an operand in parentheses. A program of its own: the
# operators change how every later write of `[]` reads.
const _WC_BLOCK_PROGRAM = raw"""
:- op(100, yf, []).
:- op(100, yf, {}).
b1 :- X = []([1,2], a), writeq(X), nl, Y = '{}'({a}, b), writeq(Y), nl, Z = []([1], a, b), writeq(Z), nl,
    V = [](x, a), writeq(V), nl, writeq(f(X)), nl, writeq(- X), nl, writeq([] + []), nl, writeq({}), nl,
    writeq(-([])), nl, W = '{}'(x, b), writeq(W), nl, writeq([]([a|b], c)), nl, write_canonical(X), nl.
b2 :- T = f(A, B), numbervars(T, 0, _), writeq([]([A], B)), nl, print('{}'({A}, B)), nl,
    write_term([]([1], x), [ignore_ops(true)]), nl.
"""
const _WC_BLOCK_GOALS = ["b1", "b2"]

@testset "the block operators on cells, as swipl writes them" begin
    db = _wc_load(_WC_BLOCK_PROGRAM)
    ours = [_wc_norm(_wc_run(db, g)) for g in _WC_BLOCK_GOALS]
    @test !any(o -> occursin("existence_error(procedure", o), ours)
    @test startswith(ours[1], "a[1,2]\nb {a}\n")
    if _R_SWIPL
        theirs = [_wc_norm(t) for t in _wc_swipl(_WC_BLOCK_PROGRAM, _WC_BLOCK_GOALS)]
        @test length(theirs) == length(_WC_BLOCK_GOALS)
        for (i, g) in enumerate(_WC_BLOCK_GOALS)
            o, s = ours[i], get(theirs, i, "—")
            @test o == s
            o == s || @info "the block operators: $g differs" ours = o swipl = s
        end
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

# a block operator whose BLOCK is itself an operator term: under brace_terms(false) the block
# `{x}` is written as `{}` applied by its prefix operator (1100), and an infix block operator's
# block is written at 999 — so swipl embraces nothing here. A program of its own: its ops change
# every later `{}` write.
const _WC_BLOCK2_PROGRAM = raw"""
:- op(700, xfx, {}).
:- op(1100, fy, {}).
b3 :- X = '{}'({x}, a, b), write_term(X, [brace_terms(false)]), nl,
    write_term(f(X), [brace_terms(false), quoted(true)]), nl,
    Y = '{}'({x, y}, a, b), write_term(Y, [brace_terms(false)]), nl, writeq(X), nl.
"""

@testset "a block operator's block as an operator term (brace_terms(false)), as swipl" begin
    db = _wc_load(_WC_BLOCK2_PROGRAM)
    ours = _wc_norm(_wc_run(db, "b3"))
    @test !occursin("existence_error(procedure", ours)
    if _R_SWIPL
        theirs = _wc_swipl(_WC_BLOCK2_PROGRAM, ["b3"])
        @test length(theirs) == 1 && ours == _wc_norm(theirs[1])
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

# ── a kernel-only term: `$expr/n` (no symbol head; swipl has no such compound) ──────────────────
"An engine with the values of `vs` put into term references; `(ld, t)` (reference `t + i - 1` is slot `t + i`)."
function _wc_engine(vs::Vector{_R})
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, length(vs))
    pvm = LK.PutVarMap()
    for (i, v) in enumerate(vs)
        LK.putSlotValue!(ld, t + i, v, pvm)
    end
    return ld, t
end

"Term reference `t`'s term written by PL_write_term with `flags`."
function _wc_write(ld, t::Int, flags::Int)::String
    out = IOBuffer()
    LK.set_standard_stream!(ld, LK.SNO_USER_OUTPUT, out)
    @test LK.PL_write_term(LK._query_gd(ld), ld, LK.Suser_output(ld), t, 1200, flags)
    LK.Sflush(LK.Suser_output(ld))
    return String(take!(out))
end

"The text of each `\$expr/n` case (the testset below), as the writer writes it today."
const _WC_EXPR_PIN = (
    "'\$expr'(g(a),b,1)",
    "f('\$expr'(_V1,x),['\$expr'(g(a))])",
    "\$expr(g(a),b,1)"
)

# HAND-PINNED (no swipl: a compound whose head is no symbol is the kernel's, the term interface's `$expr/n`
# — Q2): the writer names it `$expr` and writes every child as an argument (PL_get_name_arity's DIVERGES);
# the text is the CURRENT writer's, measured 2026-10-18 on 7a's tree — 7b must not change it.
@testset "a \$expr/n compound: written as today (kernel-only, pinned)" begin
    g = _rf("g", _rs("a"))
    e1 = mk_expr(_R, _R[g, _rs("b"), _rg(1)])               # (g(a))(b, 1)
    e2 = _rf("f", mk_expr(_R, _R[_rv(7), _rs("x")]), _rlist(mk_expr(_R, _R[g])))
    ld, t = _wc_engine(_R[e1, e2])
    @test _wc_write(ld, t, LK.PL_WRT_QUOTED) == _WC_EXPR_PIN[1]
    @test _wc_norm(_wc_write(ld, t + 1, LK.PL_WRT_QUOTED)) == _WC_EXPR_PIN[2]
    @test _wc_write(ld, t, 0) == _WC_EXPR_PIN[3]
end

# ── the boundary: a slot's side value and a keyed variable (kernel-only, TRANSITIONAL until L1f) ──
# A term reference whose slot holds a SIDE VALUE (`SLOT_VALUE`: the exception's ball, a value with no word)
# and a KEYED variable (no cell): the writer's word path meets `DU_TERM` and reads it as its term, counted in
# `cold_pairs` (varName, writePrimitive's value, writeNumberVar's root and argument, the FLI readers). The
# text is the same term's put on the cells (`putSlotValue!`), compared whole (the variable names renamed).
# 2026-10-18 L1d 7b: the writer on term references — the boundary case (mutant: its fallback skipped).
@testset "the boundary: a side value and a keyed variable, written as on the cells, counted" begin
    kv = lk_var(_R, UInt64(4743))
    v1 = _rf(
        "f", kv, _rf("\$VAR", _rg(1)), _rg("s"), _rg(1.5), _rs("a"), _rf("g", kv),
        _rcons(kv, _rv(9))
    )
    v2 = _rf("\$VAR", _rg(1))
    v3 = _rf("\$VAR", _rs("Foo"))
    flags = LK.PL_WRT_QUOTED | LK.PL_WRT_NUMBERVARS
    ld, t = _wc_engine(_R[v1, v2, v3])                  # on the cells
    cells = [_wc_norm(_wc_write(ld, t + i, flags)) for i in 0:2]
    @test cells == ["f(_V1,B,\"s\",1.5,a,g(_V1),[_V1|_V2])", "B", "Foo"]
    ld, t = _wc_engine(_R[_rs("x"), _rs("x"), _rs("x")])
    for (i, v) in enumerate((v1, v2, v3))
        LK._slot_store_value!(ld, t + i, v)            # the side value: no word
    end
    # f3-2: the keyed machinery's write sharing is gone (Q3); this testset goes in f3-3. Was
    # `== cells[i + 1]` for all three — on the boundary path the side value's keyed variable kv, met
    # three times, is now three variables (each occurrence a write of its own, a fresh cell), where
    # the put on the cells keeps it one: `g(_V2)`, `[_V3|_V4]` for `g(_V1)`, `[_V1|_V2]`
    boundary = ["f(_V1,B,\"s\",1.5,a,g(_V2),[_V3|_V4])", cells[2], cells[3]]
    for i in 0:2
        @test ld.slots[t + i + 1] == LK.SLOT_VALUE
        p0 = ld.cold_pairs
        @test _wc_norm(_wc_write(ld, t + i, flags)) == boundary[i + 1]
        @test ld.cold_pairs > p0                        # the boundary, counted
    end
end

# ── the meter ───────────────────────────────────────────────────────────────────────────────────
const _WC_METER = """
op_loop(0) :- !.
op_loop(N) :- writeq(a+b*c-(d:-e,f)), N1 is N - 1, op_loop(N1).
op_top :- op_loop(50).
li_loop(0) :- !.
li_loop(N) :- writeq([1,a,"s",2.5|t]), N1 is N - 1, li_loop(N1).
li_top :- li_loop(50).
ne_loop(0) :- !.
ne_loop(N) :- writeq(f(g(h(a), [b]), k(1, l(m)))), N1 is N - 1, ne_loop(N1).
ne_top :- ne_loop(50).
"""
_wc_counts(ld) = (ld.cold_exports, ld.cold_imports, ld.cold_vars, ld.cold_pairs)

"Run `name/0` once through the query API; the return code."
function _wc_meter_run(db::_RDB, name::Symbol)::Int
    proc = LK.lookupProcedure(_rs(name), 0, db.user)
    fid = LK.PL_open_foreign_frame(db.ld)
    qid = LK.PL_open_query(db.gd, db.ld, nothing, LK.PL_Q_NORMAL, proc, 0)
    rc = LK.PL_next_solution(db.gd, db.ld, qid)
    LK.PL_close_query(db.ld, qid)
    LK.PL_discard_foreign_frame(db.ld, fid)
    return rc
end

# the second call's traffic per loop (exports, imports, variable reads, boundary pairs), 50 iterations:
# MEASURED 2026-10-18 on 7a's tree — all the WRITER's (it read the term as terms: each compound a cold
# export): op_top (500, 0, 500, 0), li_top (350, 0, 400, 0), ne_top (600, 0, 500, 0).
# 2026-10-18 L1d 7b: the writer on term references — none left.
const _WC_METER_PIN = Dict(
    :op_top => (0, 0, 0, 0),
    :li_top => (0, 0, 0, 0),
    :ne_top => (0, 0, 0, 0)
)

@testset "the meter: writeq of an operator term, a list, a nested compound (no boundary traffic)" begin
    db = _wc_load(_WC_METER)
    LK.set_standard_stream!(db.ld, LK.SNO_USER_OUTPUT, IOBuffer())  # the null stream
    for name in (:op_top, :li_top, :ne_top)
        @test _wc_meter_run(db, name) == LK.PL_S_TRUE
        c1 = _wc_counts(db.ld)
        @test _wc_meter_run(db, name) == LK.PL_S_TRUE
        d = _wc_counts(db.ld) .- c1
        @info "$name: the second call's boundary traffic (exports, imports, variable reads, pairs)" d
        @test d == _WC_METER_PIN[name]
    end
end
