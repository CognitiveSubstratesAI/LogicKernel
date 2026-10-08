# ORIGINAL: R1d's gate — the parser (src/pl-read.jl `complex_term` and the constructs, `read_term`, term_to_atom/2, term_string/2, atom_to_term/3) against swipl 10.1.16; upstream's own reader units are ported beside it (test_read.jl, test_syntax.jl).
# test/core_text/test_read_term_swipl.jl — R1d's gate (port_inventory row R1; user, 2026-10-07:
# SWI-7's default syntax, refused constructs an EXPLICIT error, never a misread):
#   * THE TERM READ: `term_to_atom(T, Text)` through the query API on a hand corpus (operators of
#     every type and priority, prefix operators as atoms, `-` before a number, lists, `{}`, `f()`,
#     strings, `0'c`, `1r3`, Unicode brackets, the quasi-quotation detection) and on texts made two
#     ways — random token soup (mostly syntax errors: their positions) and random operator terms
#     swipl writes with `writeq` (valid: the operator resolution). Compared by an encoding that
#     names every atom by its codes and numbers variables by first occurrence, so the TERM is
#     compared exactly; a syntax error is compared as its whole ball, `string(Text, CharNo)` too;
#   * THE ORDER OF THE VARIABLES read: the standard order of the term's variables, as swipl's
#     (its order is by address, which `readValHandle` gives; the kernel makes each variable's key
#     there, src/pl-read.jl);
#   * THE ENTRY POINTS: term_to_atom/2 and term_string/2 on every text a term can hold (atom,
#     string, number, code and character lists, `[]`) and their errors; atom_to_term/3's bindings;
#   * THE REFUSALS (R1's decision): a dict, a quasi-quotation — `NotPortedError` where swipl reads
#     or raises a syntax error — and a float's text (format_float, R1e's floats). The write
#     direction is R1e's (test_write_swipl.jl).
using Test, LogicKernel, Random
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "text_corpora_testlib.jl"))
const _TR = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_trs(x) = lk_sym(_TR, Symbol(x))

const _TR_SWIPL = Sys.which("swipl")
const _TR_SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

"""
The differential's encoding of a term: `V<n>` the n-th variable by first occurrence, `nil` for
`[]`, `a[codes]` an atom, `s[codes]` a string, `i…`, `q…r…`, `F<bits>` a float,
`c[codes]/N(args)` a compound (`c[]` for a compound named `[]`). The driver's `enc/1` writes the same.
"""
function _tr_enc(t::_TR, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        is_nil(t) && return "nil"
        return "a" * _tr_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _tr_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "F" * string(reinterpret(UInt64, Float64(v)); base=16)
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    hs = is_nil(h) ? "c[]" : "c" * _tr_codes(sym_text(h))
    return hs * "/$(nchildren(t) - 1)(" *
           join([_tr_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end
# A text's codes; a byte that is no UTF-8 character counts as its own code, as upstream's decoder
# takes it (a syntax error's text can end inside a character: docs/upstream_reports.md #8).
_tr_codes(s::String)::String =
    "[" * join([isvalid(c) ? Int(c) : Int(codeunit(string(c), 1)) for c in s], ",") * "]"

"The standard order of `t`'s variables as the driver's `ord/1` writes it: `|[i…]`, each by first occurrence."
function _tr_order(ld, t::_TR)::String
    vs = UInt64[]
    _tr_enc(t, vs)                                  # first-occurrence order
    vars = [mk_var(_TR, k) for k in vs]                 # the kernel's own keys
    p = sortperm(
        1:length(vars); lt=(a, b) -> LK.compareStandard(ld, vars[a], vars[b], false) < 0
    )
    return "|[" * join(p .- 1, ",") * "]"
end

# The database every read of this file runs in (`op/3` adds to its `user` module).
const _TR_GD = LK.PL_global_data{_TR}()
const _TR_LD = LK.PL_local_data{_TR}()

"""
Run the predicate `name` on `args` through the query API: `(rc, answers)` where `answers` are the
resolved arguments after a success, the ball (resolved) after an exception — or the
`NotPortedError` the kernel raised.
"""
function _tr_call(name::String, args::Vector{_TR}; gd=_TR_GD, ld=_TR_LD)
    proc = LK.isCurrentProcedure(sym_key(_trs(name)), length(args), LK.MODULE_system(gd))
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, length(args))
    for (i, x) in enumerate(args)
        ld.slots[a + i] = x
    end
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    out = try
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            (:true, [LK.resolve_term(ld, ld.slots[a + i]) for i in 1:length(args)])
        elseif rc == LK.PL_S_EXCEPTION
            (:exception, [LK.resolve_term(ld, ld.slots[LK.PL_exception(ld, qid) + 1])])
        else
            (:false, _TR[])
        end
    catch e
        e isa LK.NotPortedError || rethrow()
        (:notported, _TR[])
    end
    out[1] === :notported || LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return out
end

_tr_var() = mk_var(_TR, LK.fresh_var_keys!(1))

"`term_to_atom(T, Text)` as the driver's `rd/1` reports it: the term and its variables' order, `fails`, `err <ball>`, or `NOTPORTED`."
function _tr_read(text::String; gd=_TR_GD, ld=_TR_LD)::String
    rc, ans = _tr_call("term_to_atom", _TR[_tr_var(), _trs(text)]; gd=gd, ld=ld)
    rc === :true && return _tr_enc(ans[1]) * _tr_order(ld, ans[1])
    rc === :exception && return "err " * _tr_enc(ans[1])
    rc === :notported && return "NOTPORTED"
    return "fails"
end

const _TR_DRIVER = raw"""
enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- T == [], !, write(nil).
enc(T, S, S) :- atom(T), !, atom_codes(T, Cs), format("a~w", [Cs]).
enc(T, S, S) :- string(T), !, string_codes(T, Cs), format("s~w", [Cs]).
enc(T, S, S) :- integer(T), !, format("i~w", [T]).
enc(T, S, S) :- rational(T, N, D), !, format("q~wr~w", [N, D]).
enc(T, S, S) :- float(T), !, format("f~w", [T]).
enc(T, S0, S) :- compound_name_arity(T, N, A),
    ( N == [] -> write('c[]') ; atom_codes(N, Cs), format("c~w", [Cs]) ),
    format("/~w(", [A]), encargs(1, A, T, S0, S), write(')').
encargs(I, A, _, S, S) :- I > A, !.
encargs(I, A, T, S0, S) :- arg(I, T, X), enc(X, S0, S1), ( I < A -> write(',') ; true ),
    I1 is I+1, encargs(I1, A, T, S1, S).
vidx([X|_], V, I, I) :- X == V, !.
vidx([_|Xs], V, I0, I) :- I1 is I0+1, vidx(Xs, V, I1, I).
ord(T) :- term_variables(T, Vs), msort(Vs, Ss), findall(I, (member(S, Ss), vidx(Vs, S, 0, I)), Is),
    atomic_list_concat(Is, ',', A), format("|[~w]", [A]).
rd(Cs) :- atom_codes(A, Cs),
    catch(( term_to_atom(T, A) -> enc(T), ord(T) ; write(fails) ), E, (write('err '), enc(E))),
    nl.
"""

"swipl's `rd/1` line for each text, from one swipl process (`prelude`: directives run first)."
function _tr_swipl_read(texts::Vector{String}; prelude::String="")::Vector{String}
    prog = IOBuffer()
    print(prog, _TR_DRIVER, prelude, "run :- ")
    for t in texts
        print(prog, "rd([", join(Int.(collect(t)), ","), "]), ")
    end
    println(prog, "true.\n:- initialization((run, halt)).")
    out = mktempdir() do d
        f = joinpath(d, "r.pl")
        write(f, String(take!(prog)))
        read(pipeline(`swipl -q $f`; stderr=devnull), String)
    end
    return [_tr_swipl_floats(String(l)) for l in split(chomp(out), '\n')]
end

# swipl writes a float as its shortest text (`f1.5`); the kernel's encoding is its bits (`F…`).
_tr_swipl_floats(l::String)::String =
    replace(
        l,
        r"f(-?(?:[0-9]+\.[0-9]+Inf|1\.5NaN|[0-9]+\.[0-9]+(?:e[-+]?[0-9]+)?))" =>
            m -> begin
                s = m[2:end]
                v = if s == "1.0Inf"
                    Inf
                elseif s == "-1.0Inf"
                    -Inf
                elseif endswith(s, "NaN")
                    LK.const_nan
                else
                    parse(Float64, s)
                end
                "F" * string(reinterpret(UInt64, v); base=16)
            end
    )

"Compare the kernel's and swipl's lines for `texts`, printing the first divergences."
function _tr_compare(texts, ours, theirs; label="")
    @test length(ours) == length(theirs)
    bad = [
        (texts[k], ours[k], theirs[k]) for
        k in 1:min(length(ours), length(theirs)) if ours[k] != theirs[k]
    ]
    for (t, o, s) in bad[1:min(end, 10)]
        println(
            stderr,
            "  DIVERGES",
            label,
            ": ",
            repr(t),
            "\n    kernel ",
            o,
            "\n    swipl  ",
            s
        )
    end
    @test isempty(bad)
    return bad
end

# THE HAND CORPUS — operators of every type and priority (SWI-7's default table), prefix operators
# taken as atoms, `-` before a number, the comma and the bar, lists and their errors, `{}`, `f()`,
# strings and the quotes, numbers, Unicode brackets, the full stop, layout and comments, and the
# quasi-quotation detection (`||`, `[|`, `{ |`: swipl's `quasi_quotations` flag is on).
# (the hand corpus: text_corpora_testlib.jl)

@testset "the variables' order: where readValHandle places them, as swipl's (by address)" begin
    # probed (swipl 10.1.16): term_to_atom(T, 'f(A,g(B),_,h(_C))'), T = f(A,g(B),V,h(C)):
    # A @> B, A @< V, V @> C, B @< C — B and C live in g and h, which are built before f
    rc, ans = _tr_call("term_to_atom", _TR[_tr_var(), _trs("f(A,g(B),_,h(_C))")])
    @test rc === :true
    t = ans[1]
    A, B, V, C = child(t, 2), child(child(t, 3), 2), child(t, 4), child(child(t, 5), 2)
    cmp(x, y) = LK.compareStandard(_TR_LD, x, y, false)
    @test cmp(A, B) > 0 && cmp(A, V) < 0 && cmp(V, C) > 0 && cmp(B, C) < 0
end

@testset "unquoted_atom: may a text atom be written bare (pl-write.c, the parser's TK_QNAME rule)" begin
    # as upstream's atomType/unquoted_text with no options: `'[]'` is quoted (SWI-7's `[]` is a
    # reserved symbol, never the text atom: writeq('[]') writes '[]', probed), `{}` is not
    for (name, bare) in [("abc", true), ("Abc", false), ("a b", false), ("[]", false),
        ("{}", true), ("+", true), ("=..", true), ("/*", false), ("!", true), (";", true),
        (",", false), ("|", false), ("é", true), ("aé", true), ("«»", false), ("%", false),
        ("a1_", true), ("_a", false), ("", false), ("α∀", false)]
        @test LK.unquoted_atom(_trs(name)) == bare
    end
    @test !LK.unquoted_atom(mk_nil(_TR))           # a reserved symbol is no text atom
end

if _TR_SWIPL !== nothing
    @testset "term_to_atom/2 == swipl: the hand corpus, the variables' order, the errors" begin
        ours = [_tr_read(t) for t in _TR_CORPUS]
        theirs = _tr_swipl_read(_TR_CORPUS)
        refused = Dict(                         # R1's decision: refused, never a misread
            "{a||b}" => "a quasi-quotation's raw text in braces", "-{a}" => "a dict"
        )
        # swipl's answer where the kernel refuses: pinned below, not compared here
        keep = [k for k in eachindex(_TR_CORPUS) if ours[k] != "NOTPORTED"]
        _tr_compare(_TR_CORPUS[keep], ours[keep], theirs[keep])
        # floors (measured 2026-10-07: 256 texts, 72 errors, 135 compounds)
        @test count(startswith("err "), ours) > 60 && count(startswith("c"), ours) > 120
    end

    @testset "the refusals: a dict, a quasi-quotation — explicit, where swipl reads or errs" begin
        # swipl reads a dict (`a{}`) or raises a syntax error inside one (`-{a}`: colon_expected);
        # a complete quasi-quotation calls its Prolog syntax hook (`{|x||y|}`) — the kernel refuses
        # each with NotPortedError (src/pl-read.jl `start_pframe`), never a misread
        texts = ["-{a}", "a{b}", "a{}", "X{a:1}", "_{a:1}", "point{x: 1}", "{|a}",
            "{|x||y|}",
            "f({|x||y|})"]
        ours = [_tr_read(t) for t in texts]
        theirs = _tr_swipl_read(texts)
        @test all(==("NOTPORTED"), ours)
        @test all(s -> s != "NOTPORTED", theirs)
    end

    @testset "`\$` is no operator: boot/topvars.pl's op(1, fx, \$) in `user` is not loaded" begin
        # swipl's boot file topvars.pl declares `:- op(1, fx, user:(\$))`; the kernel loads no
        # boot file (R1f's loader reads Prolog source), so `\$a` is a syntax error where swipl
        # reads `\$(a)`. Never a misread: without the operator, a `\$` that takes an operand is
        # two operands in a row. This pin fails when the operator is there.
        @test _tr_swipl_read(["\$a"]) == ["c[36]/1(a[97])|[]"]
        @test startswith(
            _tr_read("\$a"),
            "err c[101,114,114,111,114]/2(c[115,121,110,116,97,120,95,101,114,114,111,114]/1(a[111,112,101,114,97,116,111,114,95,101,120,112,101,99,116,101,100])"
        )
    end

    @testset "user operators == swipl: infix-and-postfix, prefix-and-infix, block operators" begin
        # op/3 in `user` on both sides: an operator that is also postfix (`modify_op` takes the
        # infix one as postfix where no operand follows), one prefix and infix, and the block
        # operators `[]` and `{}` (yf 100: `a[b]`, a term whose name is the block)
        ops = [(200, "xfx", "++"), (200, "xf", "++"), (300, "fy", "pre"),
            (300, "xfy", "pre"),
            (650, "xfx", "@@"), (650, "fx", "@@"), (100, "yf", "[]"), (100, "yf", "{}")]
        gd, ld = LK.PL_global_data{_TR}(), LK.PL_local_data{_TR}()
        for (p, t, n) in ops
            name = n == "[]" ? mk_nil(_TR) : _trs(n)
            @test _tr_call("op", _TR[lk_gnd(_TR, p), _trs(t), name]; gd=gd, ld=ld)[1] ===
                :true
        end
        texts = ["a ++", "a ++ b", "a ++ ++", "(a ++) ++ b", "a ++ ++ b", "- ++",
            "a ++ - b",
            "f(a ++)", "[a ++, b]", "pre a", "a pre b", "pre pre a", "pre", "f(pre)",
            "pre - a",
            "a pre pre b", "@@ a", "a @@ b", "@@ @@ a", "a @@ @@ b", "@@", "f(@@, a)",
            "a[b]", "a[b][c]", "f(x)[1,2]", "a {b}", "a {b}[c]", "[a][b]", "- a[b]",
            "a[b] ++",
            "X[Y]", "pre a[b]", "a ++ [b]", "f([])", "[]", "{}", "a = []", "a = {}"]
        prelude =
            ":- " *
            join(
                (
                    "op($p, $t, $(n == "[]" ? "[]" : n == "{}" ? "{}" : n))" for
                    (p, t, n) in ops
                ),
                ", "
            ) * ".\n"
        ours = [_tr_read(t; gd=gd, ld=ld) for t in texts]
        theirs = _tr_swipl_read(texts; prelude=prelude)
        @test !any(==("NOTPORTED"), ours)
        _tr_compare(texts, ours, theirs; label=" (user ops)")
        @test count(startswith("err "), ours) < length(ours) ÷ 2
        # PREFIX block operators (fy 200: `[x] a` is `[]([x], a)`), in a database of their own:
        # the block's term-stack entry is left a value when `finish_block_op` takes it, so the
        # entry `_` reuses next must be reset (alloc_term's PL_put_variable)
        ops2 = [(200, "fy", "[]"), (200, "fy", "{}")]
        gd2, ld2 = LK.PL_global_data{_TR}(), LK.PL_local_data{_TR}()
        for (p, t, n) in ops2
            name = n == "[]" ? mk_nil(_TR) : _trs(n)
            @test _tr_call("op", _TR[lk_gnd(_TR, p), _trs(t), name]; gd=gd2, ld=ld2)[1] ===
                :true
        end
        texts2 = ["[x] _", "[x] a", "[x] [y] _", "[x] [y] a", "[x]", "- [x] _", "f([x] _)",
            "[x] _ = _", "[x] (a)", "{x} _", "{x} a", "[x] {y} _", "[]", "[] a", "[a,b] c",
            "[x] - _", "f([x], _)", "[x] X", "[X] X", "[x] f(_, _)", "{X} _"]
        prelude2 = ":- op(200, fy, []), op(200, fy, {}).\n"
        ours2 = [_tr_read(t; gd=gd2, ld=ld2) for t in texts2]
        theirs2 = _tr_swipl_read(texts2; prelude=prelude2)
        @test !any(==("NOTPORTED"), ours2)
        _tr_compare(texts2, ours2, theirs2; label=" (prefix blocks)")
        @test count(startswith("err "), ours2) < length(ours2) ÷ 2
    end

    @testset "random token soup == swipl: mostly syntax errors, their positions" begin
        pieces = ["a", "b", "X", "_", "1", "-1", "- ", "-", "+", "*", "^", "**", ":-", "?-",
            "-->", ",", ";", "|", "->", "\\+", "=", " is ", "(", ")", "[", "]", " { ",
            " } ",
            "f(", "'+'", "\"s\"", " ", ":", "0'a", "1.5", "1r3", "[]", " {} ", "'[]'",
            "dynamic ", " . ", ".", "!", "'a b'", "«", "»", "⟨", "⟩", "é", "%c\n", "/*c*/",
            "x"]
        rng = Xoshiro(20261007)
        texts = unique!([join(rand(rng, pieces, rand(rng, 1:8))) for _ in 1:3000])
        # a dict tag or `{|` cannot be made (every `{` has a blank before and after it)
        ours = [_tr_read(t) for t in texts]
        theirs = _tr_swipl_read(texts)
        refused = [t for (t, o) in zip(texts, ours) if o == "NOTPORTED"]
        isempty(refused) ||
            println(stderr, "  NOTPORTED (soup): ", repr.(refused[1:min(end, 10)]))
        @test isempty(refused)
        _tr_compare(texts, ours, theirs; label=" (soup)")
        # floors (measured 2026-10-07: 2624 texts, 2344 syntax errors, 280 terms)
        @test count(startswith("err "), ours) > 2000 &&
            count(!startswith("err "), ours) > 250
    end

    @testset "swipl's writeq of random operator terms == swipl's reading of them" begin
        # swipl makes random terms over SWI-7's default operators — operators as operands too —
        # writes each with writeq/1 (one line per text: its codes) and reads it back (`rd/1`)
        gen = raw"""
        bin([+,-,*,/,//,^,**,=,\=,==,\==,@<,@>,=..,is,<,>,=<,>=,=:=,=\=,:-,-->,',',;,'|',->,'*->',:,mod,rem,xor,>>,<<,/\,\/,rdiv,div,as,>:<,:<,?=,:=]).
        pre([-,+,\,\+,?-,:-,dynamic,discontiguous,initialization,meta_predicate,multifile,public,table]).
        leaf(L) :- random_member(L, [a, b, 'A', [], '[]', {}, 1, -1, 0, -0.0, 1.5, "s", 1r3, f(a), [a,b], [a|b], {a}, -, +, ',', '|', :-, \+, *, ^, dynamic, 'a b']).
        gen(0, T, Vs) :- !, ( random(0, 4, 0) -> random_member(T, Vs) ; leaf(T) ).
        gen(D, T, Vs) :- D1 is D-1, random(0, 7, K), gen(K, D1, T, Vs).
        gen(0, D, T, Vs) :- bin(Os), random_member(O, Os), gen(D, A, Vs), gen(D, B, Vs), T =.. [O, A, B].
        gen(1, D, T, Vs) :- pre(Os), random_member(O, Os), gen(D, A, Vs), T =.. [O, A].
        gen(2, D, f(A, B), Vs) :- gen(D, A, Vs), gen(D, B, Vs).
        gen(3, D, [A, B|C], Vs) :- gen(D, A, Vs), gen(D, B, Vs), gen(D, C, Vs).
        gen(4, D, {A}, Vs) :- gen(D, A, Vs).
        gen(5, D, -(A), Vs) :- gen(D, A, Vs).
        gen(6, _, T, Vs) :- gen(0, T, Vs).
        one :- Vs = [_, _, _], gen(4, T, Vs), with_output_to(codes(Cs), writeq(T)), format("~w~n", [Cs]).
        :- initialization((set_random(seed(20261007)), forall(between(1, 1500, _), one), halt)).
        """
        texts = mktempdir() do d
            f = joinpath(d, "g.pl")
            write(f, gen)
            [
                String(Char.(parse.(Int, split(strip(l, ['[', ']']), ',')))) for
                l in eachline(pipeline(`swipl -q $f`; stderr=devnull)) if l != "[]"
            ]
        end
        @test length(texts) >= 1400
        ours = [_tr_read(t) for t in texts]
        theirs = _tr_swipl_read(texts)
        @test !any(==("NOTPORTED"), ours)
        _tr_compare(texts, ours, theirs; label=" (writeq)")
        @test count(startswith("err "), theirs) < 10      # writeq's texts read back
    end

    @testset "term_to_atom/2, term_string/2: the text a term holds, and its errors == swipl" begin
        # the text: an atom, a string, a number, a code or character list, [] (empty: end_of_string)
        cases = [
            ("term_to_atom", "f(x)"), ("term_to_atom", "12"), ("term_to_atom", "-12"),
            ("term_to_atom", "1r3"), ("term_to_atom", "\"a+b\""),
            ("term_to_atom", "[0'a,0'+,0'b]"),
            ("term_to_atom", "[a,+,b]"), ("term_to_atom", "[a|_]"),
            ("term_to_atom", "[a,1]"),
            ("term_to_atom", "[]"), ("term_to_atom", "'[]'"), ("term_to_atom", "[-1]"),
            ("term_to_atom", "[0x110000]"), ("term_to_atom", "''"),
            ("term_to_atom", "'  '"),
            ("term_to_atom", "'a. b'"), ("term_to_atom", "[0'a, 0'é]"),
            ("term_to_atom", "[0'a, 0'∀]"),
            ("term_to_atom", "[0'a|b]"), ("term_to_atom", "123456789012345678901234567890"),
            ("term_string", "f(x)"), ("term_string", "\"g(Y)\""), ("term_string", "'h(Z)'"),
            ("term_string", "[0'a]")
        ]
        prog = IOBuffer()
        print(prog, _TR_DRIVER)
        for (k, (p, t)) in enumerate(cases)          # a clause each: a fresh T
            println(
                prog,
                "c$k :- catch(( $p(T, $t) -> enc(T) ; write(fails) ), E, (write('err '), enc(E))), nl."
            )
        end
        println(
            prog,
            ":- initialization((",
            join(("c$k" for k in eachindex(cases)), ", "),
            ", halt))."
        )
        theirs = mktempdir() do d
            f = joinpath(d, "e.pl")
            write(f, String(take!(prog)))
            split(chomp(read(pipeline(`swipl -q $f`; stderr=devnull), String)), '\n')
        end
        # the kernel: the same text terms, made with the interface (code lists by their codes)
        mklist(xs) =
            foldr((x, l) -> mk_expr(_TR, _TR[_trs("[|]"), x, l]), xs; init=mk_nil(_TR))
        arg = Dict(
            "f(x)" => mk_expr(_TR, _TR[_trs("f"), _trs("x")]), "12" => lk_gnd(_TR, 12),
            "-12" => lk_gnd(_TR, -12), "1r3" => lk_gnd(_TR, 1 // big(3)),
            "\"a+b\"" => lk_gnd(_TR, "a+b"),
            "[0'a,0'+,0'b]" => mklist(lk_gnd.(_TR, [97, 43, 98])),
            "[a,+,b]" => mklist(_trs.(["a", "+", "b"])),
            "[a|_]" => mk_expr(_TR, _TR[_trs("[|]"), _trs("a"), _tr_var()]),
            "[a,1]" => mklist(_TR[_trs("a"), lk_gnd(_TR, 1)]), "[]" => mk_nil(_TR),
            "'[]'" => _trs("[]"), "[-1]" => mklist(_TR[lk_gnd(_TR, -1)]),
            "[0x110000]" => mklist(_TR[lk_gnd(_TR, Int(0x110000))]), "''" => _trs(""),
            "'  '" => _trs("  "),
            "'a. b'" => _trs("a. b"), "[0'a, 0'é]" => mklist(lk_gnd.(_TR, [97, 233])),
            "[0'a, 0'∀]" => mklist(lk_gnd.(_TR, [97, 8704])),
            "[0'a|b]" => mk_expr(_TR, _TR[_trs("[|]"), lk_gnd(_TR, 97), _trs("b")]),
            "123456789012345678901234567890" =>
                lk_gnd(_TR, big"123456789012345678901234567890"),
            "\"g(Y)\"" => lk_gnd(_TR, "g(Y)"), "'h(Z)'" => _trs("h(Z)"),
            "[0'a]" => mklist(_TR[lk_gnd(_TR, 97)])
        )
        ours = map(cases) do (p, t)
            rc, ans = _tr_call(p, _TR[_tr_var(), arg[t]])
            if rc === :true
                _tr_enc(ans[1])
            elseif rc === :exception
                "err " * _tr_enc(ans[1])
            elseif rc === :notported
                "NOTPORTED"
            else
                "fails"
            end
        end
        _tr_compare([string(p, "(T, ", t, ")") for (p, t) in cases], ours, String.(theirs))
    end

    @testset "atom_to_term/3: the bindings, and their errors == swipl" begin
        prog = IOBuffer()
        print(prog, _TR_DRIVER)
        print(
            prog,
            raw"""
a1 :- catch(( atom_to_term('f(X,Y,X,_,_Z)', T, B) -> enc(T-B) ; write(fails) ), E, (write('err '), enc(E))), nl.
a2 :- catch(( atom_to_term('f(X)', T, foo) -> enc(T) ; write(fails) ), E, (write('err '), enc(E))), nl.
a3 :- catch(( atom_to_term('f(X)', T, [x|y]) -> enc(T) ; write(fails) ), E, (write('err '), enc(E))), nl.
a4 :- catch(( atom_to_term('f(X,Y)', T, ['X'=1|R]) -> enc(T-R) ; write(fails) ), E, (write('err '), enc(E))), nl.
a5 :- catch(( atom_to_term(_, T, _) -> enc(T) ; write(fails) ), E, (write('err '), enc(E))), nl.
a6 :- catch(( atom_to_term('g', T, B) -> enc(T-B) ; write(fails) ), E, (write('err '), enc(E))), nl.
:- initialization((a1, a2, a3, a4, a5, a6, halt)).
"""
        )
        theirs = mktempdir() do d
            f = joinpath(d, "b.pl")
            write(f, String(take!(prog)))
            String.(
                split(chomp(read(pipeline(`swipl -q $f`; stderr=devnull), String)), '\n')
            )
        end
        pair(a, b) = mk_expr(_TR, _TR[_trs("-"), a, b])
        r(rc, ans, f) =
            if rc === :true
                _tr_enc(f(ans))
            elseif rc === :exception
                "err " * _tr_enc(ans[1])
            elseif rc === :notported
                "NOTPORTED"
            else
                "fails"
            end
        x1 = _tr_call("atom_to_term", _TR[_trs("f(X,Y,X,_,_Z)"), _tr_var(), _tr_var()])
        x2 = _tr_call("atom_to_term", _TR[_trs("f(X)"), _tr_var(), _trs("foo")])
        x3 = _tr_call(
            "atom_to_term",
            _TR[
                _trs("f(X)"),
                _tr_var(),
                mk_expr(_TR, _TR[_trs("[|]"), _trs("x"), _trs("y")])
            ]
        )
        rv = _tr_var()
        x4 = _tr_call(
            "atom_to_term",
            _TR[
                _trs("f(X,Y)"),
                _tr_var(),
                mk_expr(
                    _TR,
                    _TR[
                        _trs("[|]"),
                        mk_expr(_TR, _TR[_trs("="), _trs("X"), lk_gnd(_TR, 1)]),
                        rv
                    ]
                )
            ]
        )
        x5 = _tr_call("atom_to_term", _TR[_tr_var(), _tr_var(), _tr_var()])
        x6 = _tr_call("atom_to_term", _TR[_trs("g"), _tr_var(), _tr_var()])
        ours = [
            r(x1..., a -> pair(a[2], a[3])), r(x2..., a -> a[2]), r(x3..., a -> a[2]),
            r(x4..., a -> pair(a[2], child(a[3], 3))), r(x5..., a -> a[2]),
            r(x6..., a -> pair(a[2], a[3]))
        ]
        _tr_compare(["a1", "a2", "a3", "a4", "a5", "a6"], ours, theirs)
    end

    @testset "a float's text waits for format_float (R1e's floats)" begin
        # term_to_atom(T, 1.5): PL_get_text of a float needs format_float — refused, explicitly
        # (the write direction is R1e's core: test_write_swipl.jl)
        @test _tr_call("term_to_atom", _TR[_tr_var(), lk_gnd(_TR, 1.5)])[1] === :notported
    end
elseif _TR_SWIPL_REQUIRED
    error(
        "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the parser differential would be skipped"
    )
else
    @info "PARSER DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
    @testset "parser differential skipped only where it is not required" begin
        @test !_TR_SWIPL_REQUIRED
    end
end
