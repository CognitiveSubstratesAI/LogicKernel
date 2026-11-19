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
#     terms the boundary testset wrote (`'$VAR'` arguments, a shared variable) written on the cells, pinned
#     (until L1f f3 also the boundary itself: a slot's side value and a keyed variable, counted);
#   * the meter: writeq of an operator term, a list and a nested compound in a loop to a null stream — the
#     cold imports PINNED: none (until L1f f3 also the exports, variable reads and boundary pairs: none
#     since 7b phase 2).
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
    st, ball, msgs = lk_load_file_messages!(db.gd, db.ld, f)
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

# ── attributed variables (AV5: pl-write.c writeAttVar / writeAttributes; rows.tsv wr01-wr04, wr06, wr07) ──────
# A program of its own: one goal per row. swipl 10.1.19's text (the expected text is swipl's, as above: the
# variable names are renamed by first occurrence). `attributes(portray)` (wr05) is the next testset's (AV10). An
# attributed variable whose attribute contains the variable
# itself (at13, at14) is written as its name where it is met inside its own attributes (upstream fix ace539d7,
# BP2; swipl 10.1.19 recursed until the C stack was gone, so the file had no such row until then).
const _WC_ATT_PROGRAM = raw"""
at01 :- put_attr(X,a,1), write_term(X, [attributes(write)]), nl.
at02 :- put_attr(X,a,1), write_term(X, [attributes(dots)]), nl.
at03 :- put_attr(X,a,1), write_term(X, [attributes(ignore)]), nl.
at04 :- put_attr(X,a,1), write_canonical(f(X,X)), nl.
at05 :- put_attr(X,a,1), print(X), nl, write(X), nl, writeq(X), nl.
at06 :- current_prolog_flag(write_attributes, F), write(F), nl.
at07 :- put_attr(X,a,1), put_attr(X,b,g(Y,'A b')), write_term(f(X,Y), [attributes(write)]), nl,
    write_term(f(X,Y), [attributes(write), quoted(true)]), nl.
at08 :- put_attr(X,a,1), write_term([X|X], [attributes(dots)]), nl, write(X+X), nl,
    write_term(X+X, [attributes(write)]), nl.
at09 :- put_attr(X,a,1), write_term('$VAR'(X), [numbervars(true)]), nl,
    write_term('$VAR'(X), [numbervars(true), attributes(write)]), nl, print('$VAR'(X)), nl,
    writeq('$VAR'(X)), nl.
at10 :- put_attr(X,a,(p:-q,r)), write_term(X, [attributes(write)]), nl,
    put_attr(Y,a,-(1)), write_term(Y, [attributes(write), quoted(true)]), nl.
at11 :- put_attr(X,a,1), set_prolog_flag(write_attributes, write), write(X), nl, print(X), nl,
    writeq(f(X)), nl, write_term(X, [attributes(ignore)]), nl, write_canonical(X), nl,
    set_prolog_flag(write_attributes, dots), write(X), nl, set_prolog_flag(write_attributes, ignore).
at12 :- put_attr(X,a,1), put_attr(X,b,2), write_term(X, [attributes(write)]), nl,
    write_term(X, [attributes(dots)]), nl.
at13 :- put_attr(X,a,f(X)), write_term(X, [attributes(write)]), nl.
at14 :- put_attr(X,a,f(Y)), put_attr(Y,b,g(X)), write_term(h(X,Y), [attributes(write)]), nl.
at11w :- put_attr(X,a,1), write(X), nl, print(X), nl, writeq(f(X)), nl,
    write_term(X, [attributes(ignore)]), nl, write_canonical(X), nl.
at11d :- put_attr(X,a,1), write(X), nl.
"""
const _WC_ATT_GOALS = ["at$(lpad(i, 2, '0'))" for i in 1:14]

@testset "an attributed variable written, as swipl writes it (write_term attributes, write_canonical, the flag)" begin
    db = _wc_load(_WC_ATT_PROGRAM)
    ours = [_wc_norm(_wc_run(db, g)) for g in _WC_ATT_GOALS]
    @test !any(o -> occursin("NOTPORTED", o), ours)
    @test !any(o -> occursin("existence_error(procedure", o), ours)
    # the kernel's side alone: wr01-wr04, wr06, wr07 (rows.tsv; the variable's name renamed `_V1`)
    @test ours[1] == "_V1{a:1}\n\n---\n"                                    # wr01
    @test ours[2] == "_V1{…}\n\n---\n"                                      # wr02
    @test ours[3] == "_V1\n\n---\n"                                         # wr03
    @test ours[4] == "f(_V1,_V1)\n\n---\n"                                  # wr04
    @test ours[5] == "_V1\n_V1\n_V1\n\n---\n"                               # wr07 (print), write, writeq
    @test ours[6] == "ignore\n\n---\n"                                      # wr06
    @test ours[7] == "f(_V1{a:1,b:g(_V2,A b)},_V2)\nf(_V1{a:1,b:g(_V2,'A b')},_V2)\n\n---\n"
    @test ours[9] == "\$VAR(_V1)\n\$VAR(_V1{a:1})\n'\$VAR'(_V1)\n'\$VAR'(_V1)\n\n---\n"
    @test ours[10] == "_V1{a:(p:-q,r)}\n_V2{a: - 1}\n\n---\n"
    @test ours[13] == "_V1{a:f(_V1)}\n\n---\n"                             # upstream ace539d7: the cycle is the name
    @test ours[14] == "h(_V1{a:f(_V2{b:g(_V1)})},_V2{b:g(_V1{a:f(_V2)})})\n\n---\n"
    # at11: set_prolog_flag/2 (F1b) now answers as swipl 10.1.19 does (the pin of the missing predicate is gone);
    # `ours11` below drives the same flag through the local data, a second route to the same text.
    @test ours[11] == "_V1{a:1}\n_V1{a:1}\nf(_V1{a:1})\n_V1\n_V1\n_V1{…}\n\n---\n"
    ld = db.ld
    flag0 = ld.prolog_flag_write_attributes
    ours11 = try
        ld.prolog_flag_write_attributes = LK.PL_WRT_ATTVAR_WRITE
        w = _wc_norm(_wc_run(db, "at11w"))
        ld.prolog_flag_write_attributes = LK.PL_WRT_ATTVAR_DOTS
        d = _wc_norm(_wc_run(db, "at11d"))
        chopsuffix(w, "\n---\n") * d
    finally
        ld.prolog_flag_write_attributes = flag0
    end
    @test ours11 == "_V1{a:1}\n_V1{a:1}\nf(_V1{a:1})\n_V1\n_V1\n_V1{…}\n\n---\n"
    if _R_SWIPL
        theirs = [_wc_norm(t) for t in _wc_swipl(_WC_ATT_PROGRAM, _WC_ATT_GOALS)]
        @test length(theirs) == length(_WC_ATT_GOALS)
        for (i, g) in enumerate(_WC_ATT_GOALS)
            o, s = (i == 11 ? ours11 : ours[i]), get(theirs, i, "—")
            @test o == s
            o == s || @info "the attributed variable: $g differs" ours = o swipl = s
        end
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

# ── attributes(portray) (AV10: pl-write.c writeAttVar calls '$attvar':portray_attvar/1, boot/attvar.pl's) ──────
# The expected text is swipl 10.1.20's (`LC_ALL=C swipl -q -g main -t halt`, run twice, the two outputs byte-identical;
# the variable names renamed by first occurrence). m, m2, m3 are modules with an `attr_portray_hook/2`: m writes, m2 throws,
# m3 fails (portray_attvar/1 then writes `m3 = ...`); m4's hook writes the same variable again (at25: the nesting stops at
# MAX_PORTRAY_NESTING = 100 with resource_error(portray_nesting)); m5's hook writes `x` (at26: the second write goes through
# with_output_to/2, so the hook's output follows `Scurout`, the write's stream; at27 writes to a null stream: the hook's `x` goes
# there and `Scurout` is the user's output again after it); an attribute of a module with no hook is written `a = ...`; the
# `freeze` attribute is written as `freeze(Var, Goal)` (rows.tsv wr05). The text of an exception thrown by the hook
# follows the `{` the writer already wrote (at21). at19 sets the write_attributes flag to `portray` and puts it back;
# at19d, the next goal, shows the flag is `ignore` again. print/1 under the default flags (at24) writes the name only.
# at26's write goes to the current output, which is the write's stream too: its text does not tell the hook's stream from the
# current one. at28 writes to user_output while the current output is a with_output_to/2 string: the hook's `x` is on user_output
# (the write's stream), and the `write(after)` after the write lands in the string, so writeq(S) shows "after" (swipl 10.1.20,
# two identical runs): the current output is put back after the hook.
const _WC_ATTP_PROGRAM = raw"""
m:attr_portray_hook(V, _) :- write(hooked(V)).
m2:attr_portray_hook(_, _) :- throw(oops).
m3:attr_portray_hook(_, _) :- fail.
m4:attr_portray_hook(_, V) :- write_term(V, [attributes(portray)]).
m5:attr_portray_hook(_, _) :- write(x).
at15 :- put_attr(X,a,1), write_term(X, [attributes(portray)]), nl.
at16 :- put_attr(X,a,1), put_attr(X,b,g(Y,'A b')), write_term(f(X,Y), [attributes(portray)]), nl,
    write_term(f(X,Y), [attributes(portray), quoted(true)]), nl.
at17 :- freeze(X,true), write_term(X, [attributes(portray)]), nl.
at18 :- put_attr(X,m,1), put_attr(X,a,2), write_term(X, [attributes(portray)]), nl.
at19 :- put_attr(X,a,1), set_prolog_flag(write_attributes, portray), print(X), nl, write(X), nl, writeq(f(X)), nl,
    write_canonical(X), nl, set_prolog_flag(write_attributes, ignore).
at19d :- put_attr(X,a,1), write(X), nl.
at20 :- put_attr(X,a,1), write_term(X, [attributes(portray), portray(true)]), nl.
at21 :- put_attr(X,m2,1), write_term(X, [attributes(portray)]), nl.
at22 :- put_attr(X,m3,1), write_term(X, [attributes(portray)]), nl.
at23 :- freeze(X,format("hi~n")), freeze(X,true), write_term(f(X), [attributes(portray), quoted(true)]), nl.
at24 :- put_attr(X,a,1), print(X), nl, print(f(X,Y)), nl.
at25 :- put_attr(X,m4,1), write_term(X, [attributes(portray)]), nl.
at26 :- put_attr(X,m5,1), write_term(X, [attributes(portray)]), nl, put_attr(Y,m5,1),
    with_output_to(string(S), write_term(f(Y,Y), [attributes(portray)])), write(S), nl.
at27 :- put_attr(X,m5,1), open_null_stream(N), write_term(N, X, [attributes(portray)]), close(N), write(done), nl.
at28 :- put_attr(X,m5,1),
    with_output_to(string(S), (write_term(user_output, X, [attributes(portray)]), write(after))), writeq(S), nl.
"""
const _WC_ATTP_GOALS = [
    "at15", "at16", "at17", "at18", "at19", "at19d", "at20", "at21", "at22", "at23", "at24",
    "at25", "at26", "at27", "at28"
]

@testset "an attributed variable written with attributes(portray): '\$attvar':portray_attvar/1, as swipl writes it" begin
    db = _wc_load(_WC_ATTP_PROGRAM)
    ours = [_wc_norm(_wc_run(db, g)) for g in _WC_ATTP_GOALS]
    @test !any(o -> occursin("NOTPORTED", o), ours)
    # at27 (ours[14]) writes to open_null_stream/1, which owner STREAMS-A provides (wip/streams-a, pl-file.c); until that line
    # lands, at27 is `@test_broken` with the same comparisons (an unexpected pass is an error: the entry is deleted then).
    @test !any(o -> occursin("existence_error(procedure", o), ours[1:13])
    @test_broken !occursin("existence_error(procedure", ours[14])              # at27: owner STREAMS-A (open_null_stream/1)
    @test !occursin("existence_error(procedure", ours[15])
    # the kernel's side alone (the text of swipl 10.1.20, pinned)
    @test ours[1] == "_V1{a = ...}\n\n---\n"                                          # at15
    @test ours[2] == "f(_V1{a = ..., b = ...},_V2)\nf(_V1{a = ..., b = ...},_V2)\n\n---\n"   # at16
    @test ours[3] == "_V1{freeze(_V1, user:true)}\n\n---\n"                           # at17 (wr05)
    @test ours[4] == "_V1{hooked(1), a = ...}\n\n---\n"                               # at18
    @test ours[5] == "_V1{a = ...}\n_V1{a = ...}\nf(_V1{a = ...})\n_V1\n\n---\n"        # at19
    @test ours[6] == "_V1\n\n---\n"                                                  # at19d
    @test ours[7] == "_V1{a = ...}\n\n---\n"                                          # at20
    @test ours[8] == "_V1{EX oops\n---\n"                                             # at21
    @test ours[9] == "_V1{m3 = ...}\n\n---\n"                                         # at22
    @test ours[10] ==
        "f(_V1{freeze(_V1, '\$and'(user:format(\"hi~n\"),user:true))})\n\n---\n"   # at23
    @test ours[11] == "_V1\nf(_V1,_V2)\n\n---\n"                                     # at24
    @test ours[12] == "_V1{"^100 * "_V1EX resource_error(portray_nesting)\n---\n"       # at25
    @test ours[13] == "_V1{x}\nf(_V2{x},_V2{x})\n\n---\n"                             # at26
    @test_broken ours[14] == "done\n\n---\n"                                         # at27: to a null stream; Scurout put back (owner STREAMS-A)
    @test ours[15] == "_V1{x}\"after\"\n\n---\n"                                       # at28: the hook's `x` on the write's stream, `after` on the current output
    if _R_SWIPL
        theirs = [_wc_norm(t) for t in _wc_swipl(_WC_ATTP_PROGRAM, _WC_ATTP_GOALS)]
        @test length(theirs) == length(_WC_ATTP_GOALS)
        for (i, g) in enumerate(_WC_ATTP_GOALS)
            o, s = ours[i], get(theirs, i, "—")
            if g == "at27"
                @test_broken o == s                                          # owner STREAMS-A (open_null_stream/1), see above
            else
                @test o == s
            end
            o == s || @info "the attributed variable: $g differs" ours = o swipl = s
        end
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

# ── the terms of the boundary case, on the cells (kernel-only) ───────────────────────────────────
# Until L1f f3 a term reference whose slot held a SIDE VALUE (a value with no word) or a KEYED variable (no
# cell) was written through `DU_TERM`, as its term, counted in `cold_pairs`, and compared with the same term
# put on the cells; the boundary went with the keyed variables, the cells' text stays pinned (the variable
# names renamed).
@testset "the boundary's terms, written on the cells" begin
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
_wc_counts(ld) = ld.cold_imports        # (the export/variable/pair meters went with the keyed variables, f3)

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

# the second call's imports per loop, 50 iterations: none (until L1f f3 the pin was the four meters'
# `(0, 0, 0, 0)` per loop — the writer on term references since L1d 7b; MEASURED on 7a's tree: op_top
# (500, 0, 500, 0), li_top (350, 0, 400, 0), ne_top (600, 0, 500, 0)).
@testset "the meter: writeq of an operator term, a list, a nested compound (no boundary traffic)" begin
    db = _wc_load(_WC_METER)
    LK.set_standard_stream!(db.ld, LK.SNO_USER_OUTPUT, IOBuffer())  # the null stream
    for name in (:op_top, :li_top, :ne_top)
        @test _wc_meter_run(db, name) == LK.PL_S_TRUE
        c1 = _wc_counts(db.ld)
        @test _wc_meter_run(db, name) == LK.PL_S_TRUE
        @test _wc_counts(db.ld) == c1
    end
end
