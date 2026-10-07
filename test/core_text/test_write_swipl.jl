# ORIGINAL: R1e's gate — the writer's core (src/pl-write.jl `writeTerm2` and its state machine, the token layer, `PL_write_term`; term_to_atom/2 and term_string/2's write direction) against swipl 10.1.16.
# test/core_text/test_write_swipl.jl — R1e's gate (user, 2026-10-07: 1b — the writer's CORE first;
# 3a — print/1 pinned against swipl; 4a — a cyclic term refused explicitly):
#   * THE TEXT WRITTEN, five ways for every term — term_to_atom/2 and term_string/2 through the
#     query API, and `PL_write_term` with writeq/1's, print/1's and write/1's flags — compared with
#     swipl's term_to_atom/2, term_string/2, writeq/1, print/1 (no user:portray/1) and write/1, on
#     a hand corpus (operators of every type and priority, prefix operators before numbers and
#     brackets, atoms that are operators as arguments, quoting and escapes, Unicode, `'$VAR'`,
#     lists, `{}`, bracket pairs, numbers, strings) and on random terms built on both sides from
#     one encoding. A variable is written `_<number>`, and its number is never compared: both
#     texts name their variables `_V0`, `_V1`… by first occurrence before they are compared;
#   * THE OPERATOR TABLE: swipl's boot files add `$` (boot/topvars.pl, R2; the kernel has pl-op.c's
#     table, `.` and `:=` included); the driver removes it, so both sides write with one table;
#   * THE REFUSALS: a float (R1e's floats), a cyclic term (`X = f(X)`, and a cyclic exception
#     ball), user:portray/1 defined (calling Prolog), an atom holding the character 0 — each an
#     explicit `NotPortedError`, never a wrong text, a hang or a stack overflow;
#   * DEPTH: a term 100,000 levels deep and a list of 100,000 elements, written without recursion;
#   * KNOWN UPSTREAM DEFECTS, ported AS IS and pinned (docs/upstream_reports.md #11, #12).
using Test, LogicKernel, Random
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TW = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_tws(x) = lk_sym(_TW, Symbol(x))
_twf(f, xs::_TW...) = mk_expr(_TW, _TW[_tws(f), xs...])
_tw_var() = mk_var(_TW, LK.fresh_var_keys!(1))
_tw_int(n::Integer) =
    typemin(Int64) <= n <= typemax(Int64) ? lk_gnd(_TW, Int64(n)) : lk_gnd(_TW, BigInt(n))

const _TW_SWIPL = Sys.which("swipl")
const _TW_SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

# The database every query of this file runs in.
const _TW_GD = LK.PL_global_data{_TW}()
const _TW_LD = LK.PL_local_data{_TW}()

"""
Run the predicate `name` on `args` through the query API: `(rc, answers)` — the resolved
arguments after a success, the ball (resolved) after an exception, or `:notported`.
"""
function _tw_call(name::String, args::Vector{_TW}; gd=_TW_GD, ld=_TW_LD)
    proc = LK.isCurrentProcedure(sym_key(_tws(name)), length(args), LK.MODULE_system(gd))
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
            (:false, _TW[])
        end
    catch e
        e isa LK.NotPortedError || rethrow()
        (:notported, _TW[])
    end
    out[1] === :notported || LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return out
end

"`PL_write_term` of `t` with `flags` to a memory stream: its text, or `NOTPORTED`, or `fails`."
function _tw_write(t::_TW, flags::Int; gd=_TW_GD, ld=_TW_LD)::String
    fid = LK.PL_open_foreign_frame(ld)
    r = LK.PL_new_term_refs(ld, 1)
    ld.slots[r + 1] = t
    bufp = Ref{Union{Nothing, Vector{UInt8}}}(nothing)
    sizep = Ref(0)
    s = LK.Sopenmem(bufp, sizep, "w")
    res = try
        LK.PL_write_term(gd, ld, s, r, 1200, flags) ? :ok : :fails
    catch e
        e isa LK.NotPortedError || rethrow()
        :notported
    end
    LK.Sclose(s)
    LK.PL_close_foreign_frame(ld, fid)
    res === :notported && return "NOTPORTED"
    res === :fails && return "fails"
    b = bufp[]
    return (b === nothing || sizep[] == 0) ? "" : String(b[1:sizep[]])
end

# writeq/1, print/1 (print_write_options [portray(true), quoted(true), numbervars(true)]: probed),
# write/1 — the flags pl-write.c's do_write2 and pl_write_term3 give them; PL_write_term adds the
# module's character escapes, as both do. print/1 is NOT writeq/1 plus portray (decision 3a's
# condition, measured here): pl_write_term3 also adds `PL_WRT_CHARESCAPES_UNICODE` from the
# `character_escapes_unicode` flag (true by default), so print/1 writes `'\u0001'` where writeq/1
# writes `'\x1\'`
const _TW_WRITEQ = LK.PL_WRT_QUOTED | LK.PL_WRT_NUMBERVARS
const _TW_PRINT =
    LK.PL_WRT_QUOTED | LK.PL_WRT_NUMBERVARS | LK.PL_WRT_PORTRAY |
    LK.PL_WRT_CHARESCAPES_UNICODE
const _TW_WRITE = LK.PL_WRT_NUMBERVARS

# write_term/2's flags through PL_write_term, each beside the swipl options that give it (pl-write.c
# pl_write_term3): `character_escapes_unicode` is on unless switched off, as the flag's default
# adds it; `ignore_ops(true)` sets BRACETERMS too, `portable(true)` IGNOREOPS and INFIX_COMMA,
# `back_quotes(string)` BACKQUOTED_STRING, `character_escapes(false)` NO escapes
const _TW_CU = LK.PL_WRT_QUOTED | LK.PL_WRT_CHARESCAPES_UNICODE
const _TW_FLAGSETS = [
    (
        _TW_CU | LK.PL_WRT_IGNOREOPS | LK.PL_WRT_BRACETERMS,
        "[quoted(true),ignore_ops(true)]"
    ),
    (_TW_CU | LK.PL_WRT_DOTLISTS, "[quoted(true),dotlists(true)]"),
    (_TW_CU | LK.PL_WRT_NO_LISTS, "[quoted(true),no_lists(true)]"),
    (_TW_CU | LK.PL_WRT_BRACETERMS, "[quoted(true),brace_terms(false)]"),
    (_TW_CU | LK.PL_WRT_PORTABLE, "[quoted(true),portable(true)]"),
    (_TW_CU | LK.PL_WRT_QUOTE_NON_ASCII, "[quoted(true),quote_non_ascii(true)]"),
    (_TW_CU | LK.PL_WRT_PATTERN_SYNTAX_SOLO, "[quoted(true),pattern_syntax_solo(true)]"),
    (_TW_CU | LK.PL_WRT_BACKQUOTED_STRING, "[quoted(true),back_quotes(string)]"),
    (_TW_CU | LK.PL_WRT_NO_CHARESCAPES, "[quoted(true),character_escapes(false)]"),
    (LK.PL_WRT_QUOTED, "[quoted(true),character_escapes_unicode(false)]"),
    (LK.PL_WRT_CHARESCAPES_UNICODE | LK.PL_WRT_IGNOREOPS | LK.PL_WRT_BRACETERMS,
        "[ignore_ops(true)]"),
    (LK.PL_WRT_CHARESCAPES_UNICODE | LK.PL_WRT_DOTLISTS | LK.PL_WRT_NUMBERVARS,
        "[dotlists(true),numbervars(true)]")
]
_tw_flag_outputs(t::_TW; gd=_TW_GD, ld=_TW_LD) =
    [_tw_write(t, f; gd=gd, ld=ld) for (f, _) in _TW_FLAGSETS]

"The kernel's five texts of `t`: term_to_atom/2, term_string/2, writeq/1, print/1, write/1."
function _tw_outputs(t::_TW; gd=_TW_GD, ld=_TW_LD)::Vector{String}
    out = String[]
    for name in ("term_to_atom", "term_string")
        rc, ans = _tw_call(name, _TW[t, _tw_var()]; gd=gd, ld=ld)
        push!(
            out,
            if rc === :true
                a = ans[2]
                kind(a) === SYM ? sym_text(a) : String(lk_value(a))
            elseif rc === :notported
                "NOTPORTED"
            elseif rc === :exception
                "err"
            else
                "fails"
            end
        )
    end
    for flags in (_TW_WRITEQ, _TW_PRINT, _TW_WRITE)
        push!(out, _tw_write(t, flags; gd=gd, ld=ld))
    end
    return out
end

"Name the variables of a written text `_V0`, `_V1`… by first occurrence (their numbers differ)."
function _tw_norm(s::String)::String
    seen = Dict{String, Int}()
    return replace(
        s,
        r"(?<![A-Za-z0-9_])_G?[0-9]+(?![A-Za-z0-9_])" =>
            m -> "_V" * string(get!(seen, m, length(seen)))
    )
end

const _TW_DRIVER = raw"""
:- op(0, fx, $).
dec(a(Cs), A, _) :- !, atom_codes(A, Cs).
dec(nil, [], _) :- !.
dec(i(N), N, _) :- !.
dec(q(N, D), Q, _) :- !, Q is N rdiv D.
dec(s(Cs), S, _) :- !, string_codes(S, Cs).
dec(v(K), V, Vs) :- !, nth0(K, Vs, V).
dec(cn(As), T, Vs) :- !, decl(As, Xs, Vs), compound_name_arguments(T, [], Xs).
dec(c(Cs, As), T, Vs) :- atom_codes(N, Cs), decl(As, Xs, Vs), compound_name_arguments(T, N, Xs).
decl([], [], _).
decl([A|As], [X|Xs], Vs) :- dec(A, X, Vs), decl(As, Xs, Vs).
out(G) :- catch(( with_output_to(codes(Cs), G) -> format("~w", [Cs]) ; write(fails) ), _, write(err)).
wt(T) :- out((term_to_atom(T, A), write(A))), write(' '), out((term_string(T, S), write(S))),
    write(' '), out(writeq(T)), write(' '), out(print(T)), write(' '), out(write(T)), nl.
we(Enc) :- length(Vs, 8), dec(Enc, T, Vs), wt(T).
wo(T, Os) :- forall(nth1(I, Os, O), (( I > 1 -> write(' ') ; true ), out(write_term(T, O)))), nl.
wfe(Enc, Os) :- length(Vs, 8), dec(Enc, T, Vs), wo(T, Os).
rf(Cs, Os) :- atom_codes(A, Cs), term_to_atom(T, A), wo(T, Os).
rt(Cs) :- atom_codes(A, Cs),
    ( catch(term_to_atom(T, A), _, fail) -> wt(T)
    ; write('unreadable unreadable unreadable unreadable unreadable'), nl ).
"""

"swipl's five texts for each goal (`rt([codes])` or `we(Enc)`), from one swipl process."
function _tw_swipl(goals::Vector{String}; prelude::String="")::Vector{Vector{String}}
    prog = IOBuffer()
    print(prog, _TW_DRIVER, prelude, "run :- ")
    for g in goals
        print(prog, g, ", ")
    end
    println(prog, "true.\n:- initialization((run, halt)).")
    out = mktempdir() do d
        f = joinpath(d, "w.pl")
        write(f, String(take!(prog)))
        read(pipeline(`swipl -q $f`; stderr=devnull), String)
    end
    lines = split(chomp(out), '\n')
    return [
        [
            if startswith(w, "[")
                String(Char.(parse.(Int, split(w[2:(end - 1)], ',';
                    keepempty=false))))
            else
                String(w)
            end for w in split(l, ' ')
        ] for l in lines
    ]
end

_tw_codes(s::String)::String = "[" * join(Int.(collect(s)), ",") * "]"

"Compare the kernel's and swipl's texts, printing the first divergences."
function _tw_compare(
    labels, ours, theirs; what="",
    modes=("term_to_atom", "term_string", "writeq", "print", "write")
)
    @test length(ours) == length(theirs)
    bad = Tuple{String, String, String, String}[]
    @test all(
        k -> length(ours[k]) == length(theirs[k]) == length(modes),
        1:min(length(ours), length(theirs))
    )
    for k in 1:min(length(ours), length(theirs)), m in 1:length(modes)
        o, s = _tw_norm(ours[k][m]), _tw_norm(theirs[k][m])
        o == s || push!(bad, (labels[k], modes[m], o, s))
    end
    for (l, m, o, s) in bad[1:min(end, 12)]
        println(stderr, "  DIVERGES", what, " ", m, ": ", l, "\n    kernel ", repr(o),
            "\n    swipl  ", repr(s))
    end
    @test isempty(bad)
    return length(bad)
end

# ── the hand corpus: texts both sides read, then write ─────────────────────────────────────────
const _TW_CORPUS = [
    # operators: priorities, associativity, embracing
    "a:-b,c;d->e", "(a:-b):-c", "f((a:-b))", "[(a:-b)]", "{a:-b}", "1+2+3", "1+(2+3)",
    "2^3^4",
    "(2^3)^4", "a*(b+c)", "a*b+c", "a=..b", "a:b:c", "(a,b)", "f((a,b))", "f(a;b)",
    "f((a->b))",
    "\\+a", "\\+ (a,b)", "\\+ \\+ q", "a=(\\+b)", "- (1)", "-(a)", "- - a", "- (-(1))",
    "1 - -1",
    "a- (-1)", "-(2)^2", "(-2)^2", "-(2^2)", "1 + -2", "1- - 2", "a = -5", "f(- 1)",
    "-(1)+2",
    "+(1)", "+(a)", "+(-(1))", "- - - a", "- - - 1", "a: -1", "a- (1r3)", "- (1r3)",
    "-(-1r3)",
    "-(a,b)", "dynamic a", "dynamic (a,b)", "(dynamic a), b", "f(dynamic)", "- (dynamic)",
    "\\ (-)", "- (-)", "f(-)", "[-]", "[- , +]", "-(-(-))", "- (:-)", "f(:-, a)",
    "(:-) :- (:-)",
    "[:-|:-]", "{:-}", "a-(',')", "f(',')", "','(a,b)", "'|'(a,b)", "f('|')", "a|b",
    "(a|b)",
    "f(;)", "f(a, (b:-c))", "- {a}", "- (a)", "- [a]", "-(\"s\")", "-'[]'", "- []",
    "- '{}'",
    "f(?-)", "?-a", ":- (a,b)", "a-->b", "a=>b", "a==>b", "x is 1+2", "a mod b", "a rem b",
    "a xor b", "a rdiv b", "a//b", "a<<b", "a>>b", "a/\\b", "a\\/b", "a**b", "a**(b**c)",
    "(a**b)**c", "a=@=b", "a\\=@=b", "a>:<b", "a:<b", "a as b", "a*->b", "1-(2-3)",
    "(1-2)-3",
    "- (1-2)", "-(1)-2", "2-(-1)", "2 - (- 1)", "1*(-1)", "1*(- 1)", "- a^2", "(- a)^2",
    "f(a- -1)", "\\+ (-)", "dynamic - a",
    # atoms and quoting
    "'hello world'", "'[]'", "[]", "'{}'", "{}", "'[|]'", "'()'", "''", "'\\t'", "'\\n'",
    "'it''s'",
    "'a\\\\b'", "'/*'", "'%'", "'.'", "'a.b'", "'A'", "'_'", "'_x'", "abc", "aBc", "'1a'",
    "é",
    "'éa'", "aé", "'ŝ'", "f(é)", "'Ωmega'", "αβ", "日本", "'e\\x301\\'", "'\\x301\\'",
    "'\\x2028\\'",
    "'\\x7F\\'", "'\\x85\\'", "'\\x1\\'", "'\\xA0\\'", "'∀'", "'≠'", "'😀'", "⟨⟩", "'«»'",
    "'⟨'",
    "!", ";", "'|'", "','", "[]", "'$VAR'", "end_of_file", "'\\\\'", "\\", "?", "@", "#",
    "'`'",
    "'\"'", "'a b'", "f('A', 'b c', \"d\")",
    # dynamic é: KNOWN UPSTREAM DEFECT #11 (a Latin-1 first letter after a letter: no space)
    "dynamic é", "dynamic 'éa'", "- é", "a- é", "dynamic ŝ", "dynamic 'Ωmega'",
    # bracket pairs: '⟨⟩'(a) prints ⟨a⟩; KNOWN UPSTREAM DEFECT #12: '[]'(a) prints [a], '()'(a) (a)
    "'⟨⟩'(a)", "⟨a⟩", "'«»'(a)", "'[]'(a)", "'()'(a)", "- '()'(a)", "'[]'(a,b)", "'{}'(a)",
    "'{}'(a,b)", "{a,b}", "{}(a)",
    # lists
    "[a]", "[a|b]", "[a,b|c]", "[a|[]]", "[a,b,c]", "[[a]]", "[a|X]", "'[|]'(a,b,c)",
    "'[|]'",
    "[a|'[]']", "[1,-1,- 1]",
    # numbers and strings
    "1r3", "-1r3", "123456789012345678901234567890", "-123456789012345678901234567890", "0",
    "-0", "f(-5)", "- (5)", "1152921504606846976", "\"str\\n\"", "\"\"", "\"a b\"",
    "f(\"x\",'Y',\"\")", "\"x\\\"y\"", "\"it's\"", "\"é\"", "\"\\x301\\\"", "\"`\"",
    "\"\\\\\"",
    # '$VAR'
    "'\$VAR'(1)", "'\$VAR'(27)", "'\$VAR'(-3)", "'\$VAR'('Foo')", "'\$VAR'(x)",
    "'\$VAR'('?x')",
    "'\$VAR'('A_1')", "'\$VAR'('_')", "'\$VAR'(\"s\")", "'\$VAR'(1r3)", "'\$VAR'(a,b)",
    "'\$VAR'(72057594037927935)", "'\$VAR'(72057594037927936)",
    "'\$VAR'(-72057594037927936)",
    "'\$VAR'(-72057594037927937)", "f('\$VAR'(1), '\$VAR'(2))", "- '\$VAR'(1)",
    "'\$VAR'(1)- a",
    # variables
    "f(X,Y,X)", "X", "[X|Y]", "- X", "f(_)", "X = Y", "{X}", "'⟨⟩'(X)",
    # the operator table: `$` is no operator on either side; `.` and `:=` are on both
    "f(\$)", "- (\$)", "'\$'(a)", "'.'(a,b)", "':='(a,b)"
]

# ── random terms, built on both sides from one encoding ─────────────────────────────────────────
const _TW_ATOMS = [
    "a", "foo", "b1", "[]", "{}", "[|]", "()", "'", "\"", "`", ",", "|", ";", "!", "-", "+",
    "*",
    "\\", "\\+", ":-", "?-", "-->", "->", "=", "is", "mod", "dynamic", "table", "^", "**",
    ":",
    "\$", ".", ":=", "", " ", "hello world", "A", "Abc", "_", "_x", "é", "éa", "aé", "ŝ",
    "Ωmega", "αβ", "日本", "é", "́", "x‍", "⟨⟩", "«»", "⟨", "/*", "%", "a.b", "\n",
    "\t", "it's", "a\\b", " ", "\x7f", "\u0085", "\x01", "\$VAR", "end_of_file", "[a]",
    "{a}", "?", "@", "#", "&", "~", "-1", "1", "xor", "rdiv", " ", "　", "∀", "≠", "a b",
    "😀", "\\=", "=..", "@<", "<", "//", "/", "\\/", "rem", "as", "*->", "=>", "=@="
]
const _TW_STRINGS = [
    "", "a", "a b", "x\"y", "it's", "é", "日本", "\n", "`", "\\", "é", "😀", "\$", "''"
]
const _TW_VARNAMES = ["A", "Foo", "_", "x", "?x", "A_b", "é", "Ω", "?", "_a", "a b"]
const _TW_INTS = BigInt[
    0, 1, -1, 7, -42, 25, 26, 27, -26, big(2) ^ 56 - 1, big(2) ^ 56, -big(2) ^ 56,
    -big(2) ^ 56 - 1,
    big(10) ^ 30, -big(10) ^ 30, big(2) ^ 63, -big(2) ^ 63
]

"A random term of depth at most `d`: its encoding for the swipl driver and the kernel term."
function _tw_gen(rng, d::Int, vars::Vector{_TW})::Tuple{String, _TW}
    r = d <= 0 ? rand(rng, 1:6) : rand(rng, 1:14)
    if r == 1
        a = rand(rng, _TW_ATOMS)
        return ("a(" * _tw_codes(a) * ")", _tws(a))
    elseif r == 2
        return ("nil", mk_nil(_TW))
    elseif r == 3
        n = rand(rng, _TW_INTS)
        return ("i($n)", _tw_int(n))
    elseif r == 4
        q = rand(rng, [1 // 3, -2 // 7, big(10)^20 // 3, -1 // big(10)^20])
        q = Rational{BigInt}(q)
        return ("q($(numerator(q)),$(denominator(q)))", lk_gnd(_TW, q))
    elseif r == 5
        s = rand(rng, _TW_STRINGS)
        return ("s(" * _tw_codes(s) * ")", lk_gnd(_TW, s))
    elseif r == 6
        k = rand(rng, 0:3)
        return ("v($k)", vars[k + 1])
    elseif r <= 9                                   # a compound named by any atom
        name = rand(rng, _TW_ATOMS)
        args = [_tw_gen(rng, d - 1, vars) for _ in 1:rand(rng, 1:3)]
        return (
            "c(" * _tw_codes(name) * ",[" * join(first.(args), ",") * "])",
            mk_expr(_TW, _TW[_tws(name), last.(args)...])
        )
    elseif r == 10                                  # '$VAR'(…)
        x = if rand(rng, Bool)
            n = rand(rng, _TW_INTS)
            ("i($n)", _tw_int(n))
        else
            v = rand(rng, _TW_VARNAMES)
            ("a(" * _tw_codes(v) * ")", _tws(v))
        end
        return ("c(" * _tw_codes("\$VAR") * ",[" * x[1] * "])", _twf("\$VAR", x[2]))
    elseif r == 11                                  # a list, its tail [], a variable or a term
        n = rand(rng, 1:3)
        els = [_tw_gen(rng, d - 1, vars) for _ in 1:n]
        tail = rand(rng, [("nil", mk_nil(_TW)), ("v(0)", vars[1]), _tw_gen(rng, 0, vars)])
        enc, t = tail
        for (e, x) in reverse(els)
            enc = "c(" * _tw_codes("[|]") * ",[" * e * "," * enc * "])"
            t = _twf("[|]", x, t)
        end
        return (enc, t)
    elseif r == 12                                  # a compound named by the reserved `[]`
        args = [_tw_gen(rng, d - 1, vars) for _ in 1:rand(rng, 1:2)]
        return (
            "cn([" * join(first.(args), ",") * "])",
            mk_expr(_TW, _TW[mk_nil(_TW), last.(args)...])
        )
    else                                            # an operator term of the right arity
        ops = LK.operators
        op = ops[rand(rng, 1:length(ops))]
        arity = (op[2] & LK.OP_MASK) == LK.OP_INFIX ? 2 : 1
        args = [_tw_gen(rng, d - 1, vars) for _ in 1:arity]
        return (
            "c(" * _tw_codes(op[1]) * ",[" * join(first.(args), ",") * "])",
            mk_expr(_TW, _TW[_tws(op[1]), last.(args)...])
        )
    end
end

if _TW_SWIPL !== nothing
    @testset "the hand corpus: read, then written five ways, as swipl" begin
        ours = [
            begin
                rc, ans = _tw_call("term_to_atom", _TW[_tw_var(), _tws(t)])
                @assert rc === :true "the kernel cannot read $(repr(t))"
                _tw_outputs(ans[1])
            end for t in _TW_CORPUS
        ]
        theirs = _tw_swipl(["rt(" * _tw_codes(t) * ")" for t in _TW_CORPUS])
        _tw_compare(_TW_CORPUS, ours, theirs; what=" (corpus)")
    end

    # op/3 in `user` on both sides, each set in a database of its own (R1d's sets): postfix
    # operators (writePostfixOp), an operator both prefix and infix, and the block operators —
    # `[]` and `{}` as postfix (`a[b]`), as prefix (`[x] a`) and `[]` as infix (`a [x] b`):
    # isBlockOp and the WF_*_BLOCK levels
    _tw_opsets = [
        [(200, "xfx", "++"), (200, "xf", "++"), (300, "fy", "pre"), (300, "xfy", "pre"),
            (650, "xfx", "@@"), (650, "fx", "@@"), (100, "yf", "[]"), (100, "yf", "{}"),
            (150, "xf", "pp"), (150, "yf", "qq")],
        [(200, "fy", "[]"), (200, "fy", "{}")],
        [(700, "xfx", "[]")]
    ]
    _tw_optexts = [
        ["a ++", "a ++ b", "a ++ ++", "(a ++) ++ b", "a ++ ++ b", "- ++", "a ++ - b",
            "f(a ++)",
            "[a ++, b]", "pre a", "a pre b", "pre pre a", "pre", "f(pre)", "pre - a",
            "a pre pre b", "@@ a", "a @@ b", "@@ @@ a", "a @@ @@ b", "@@", "f(@@, a)",
            "a[b]",
            "a[b][c]", "f(x)[1,2]", "a {b}", "a {b}[c]", "[a][b]", "- a[b]", "a[b] ++",
            "X[Y]",
            "pre a[b]", "a ++ [b]", "f([])", "a = []", "a pp", "(a pp) pp", "a qq qq",
            "- a pp", "f(a pp)", "a pp + b", "(a + b) pp", "(a + b) qq", "a pp ++", "1 pp",
            "- 1 pp", "(- 1) pp", "(a:-b) qq", "\\+ a qq", "a = b qq", "[] qq", "{} qq",
            "'$VAR'(1) pp", "\"s\" qq", "a {b} qq", "a[b] qq", "a {X}", "a {}", "pp",
            "f(pp, qq)",
            "- pp", "pp pp", "qq qq qq"],
        ["[x] _", "[x] a", "[x] [y] _", "[x] [y] a", "- [x] _", "f([x] _)", "[x] _ = _",
            "[x] (a)", "{x} _", "{x} a", "[x] {y} _", "[] a", "[a,b] c", "[x] - _", "[x] X",
            "[X] X", "[x] f(_, _)", "{X} _", "[x] 1", "[x] - 1", "[x] (a, b)", "[x] [y]"],
        ["a [x] b", "a [x] (b [y] c)", "(a [x] b) [y] c", "f(a [x] b)", "- a [x] b",
            "a [x, y] b", "a [x|y] b", "a [] b"]
    ]
    for (k, (ops, texts)) in enumerate(zip(_tw_opsets, _tw_optexts))
        @testset "user operators, set $k: read, then written five ways, as swipl" begin
            gd, ld = LK.PL_global_data{_TW}(), LK.PL_local_data{_TW}()
            for (p, t, n) in ops
                name = n == "[]" ? mk_nil(_TW) : _tws(n)
                @test _tw_call(
                    "op", _TW[lk_gnd(_TW, Int64(p)), _tws(t), name]; gd=gd, ld=ld
                )[1] ===
                    :true
            end
            ours = Vector{String}[]
            for t in texts                          # R1d's texts: some are syntax errors
                rc, ans = _tw_call("term_to_atom", _TW[_tw_var(), _tws(t)]; gd=gd, ld=ld)
                push!(
                    ours,
                    if rc === :true
                        _tw_outputs(ans[1]; gd=gd, ld=ld)
                    else
                        fill("unreadable", 5)
                    end
                )
            end
            @test count(o -> o[1] == "unreadable", ours) < length(ours) ÷ 4
            prelude = ":- " * join(("op($p, $t, $n)" for (p, t, n) in ops), ", ") * ".\n"
            theirs = _tw_swipl(["rt(" * _tw_codes(t) * ")" for t in texts]; prelude=prelude)
            _tw_compare(texts, ours, theirs; what=" (user operators, set $k)")
        end
    end

    @testset "random terms: written five ways, as swipl" begin
        rng = MersenneTwister(20261007)
        encs = String[]
        ours = Vector{String}[]
        for _ in 1:3000
            vars = _TW[_tw_var() for _ in 1:4]
            enc, t = _tw_gen(rng, 4, vars)
            push!(encs, enc)
            push!(ours, _tw_outputs(t))
        end
        theirs = _tw_swipl(["we(" * e * ")" for e in encs])
        @test _tw_compare(encs, ours, theirs; what=" (random)") == 0
        # the generator reaches what it is for: no refusal, every mode written
        @test !any(o -> any(==("NOTPORTED"), o), ours)
        @test count(o -> occursin("_V", _tw_norm(o[1])), ours) > 100      # variables
        @test count(o -> o[3] != o[1], ours) > 100      # numbervars changes the text
        @test count(o -> o[5] != o[3], ours) > 1000     # quoting changes the text
    end

    @testset "write_term/2's flags through PL_write_term, as swipl" begin
        os = "[" * join(last.(_TW_FLAGSETS), ",") * "]"
        modes = Tuple(last.(_TW_FLAGSETS))
        # the hand corpus
        ours = [
            begin
                rc, ans = _tw_call("term_to_atom", _TW[_tw_var(), _tws(t)])
                _tw_flag_outputs(ans[1])
            end for t in _TW_CORPUS
        ]
        theirs = _tw_swipl(["rf(" * _tw_codes(t) * ", " * os * ")" for t in _TW_CORPUS])
        _tw_compare(_TW_CORPUS, ours, theirs; what=" (corpus, flags)", modes=modes)
        # random terms
        rng = MersenneTwister(20261008)
        encs = String[]
        ours = Vector{String}[]
        for _ in 1:1000
            vars = _TW[_tw_var() for _ in 1:4]
            enc, t = _tw_gen(rng, 4, vars)
            push!(encs, enc)
            push!(ours, _tw_flag_outputs(t))
        end
        theirs = _tw_swipl(["wfe(" * e * ", " * os * ")" for e in encs])
        @test _tw_compare(encs, ours, theirs; what=" (random, flags)", modes=modes) == 0
        # each flag set changes some text from plain quoted writing (the flag is exercised)
        base = [
            _tw_write(t, _TW_CU) for t in (
                begin
                    rc, ans = _tw_call("term_to_atom", _TW[_tw_var(), _tws(x)])
                    ans[1]
                end for x in _TW_CORPUS
            )
        ]
        for (m, (f, o)) in enumerate(_TW_FLAGSETS)
            corpus_m = [
                _tw_write(t, f) for t in (
                    begin
                        rc, ans = _tw_call("term_to_atom", _TW[_tw_var(), _tws(x)])
                        ans[1]
                    end for x in _TW_CORPUS
                )
            ]
            @test count(k -> _tw_norm(corpus_m[k]) != _tw_norm(base[k]), eachindex(base)) >
                0
        end
    end
elseif _TW_SWIPL_REQUIRED
    error(
        "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the writer differential would be skipped"
    )
else
    @info "WRITER DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
    @testset "writer differential skipped only where it is not required" begin
        @test !_TW_SWIPL_REQUIRED
    end
end

@testset "a variable is written _<number>: one name per variable" begin
    x, y = _tw_var(), _tw_var()
    rc, ans = _tw_call("term_to_atom", _TW[_twf("f", x, y, x), _tw_var()])
    @test rc === :true
    m = match(r"^f\((_[0-9]+),(_[0-9]+),(_[0-9]+)\)$", sym_text(ans[2]))
    @test m !== nothing
    @test m[1] == m[3] && m[1] != m[2]
    # and it reads back as a variable: f(A,B,A)
    rc2, ans2 = _tw_call("term_to_atom", _TW[_tw_var(), ans[2]])
    @test rc2 === :true
    t = ans2[1]
    @test kind(child(t, 2)) === VAR && lk_eq(child(t, 2), child(t, 4)) &&
        !lk_eq(child(t, 2), child(t, 3))
end

@testset "KNOWN UPSTREAM DEFECTS, ported as is" begin
    # #11: writeText passes a Latin-1 text's first character as C's signed `char`, so after a
    # letter no space separates it: `dynamic é` is written `dynamicé`, which reads as one atom
    t = _twf("dynamic", _tws("é"))
    @test _tw_write(t, _TW_WRITEQ) == "dynamicé"
    rc, ans = _tw_call("term_to_atom", _TW[_tw_var(), _tws("dynamicé")])
    @test rc === :true && kind(ans[1]) === SYM && sym_text(ans[1]) == "dynamicé"
    @test _tw_write(_twf("dynamic", _tws("ŝ")), _TW_WRITEQ) == "dynamic ŝ"   # a wide one: spaced
    # …and atomType passes a single-byte atom's characters as signed `char` and never tests the
    # first one, so quote_non_ascii(true) (write_canonical/1's flag) leaves a Latin-1 atom
    # unquoted, where it quotes a wide one
    qna = LK.PL_WRT_QUOTED | LK.PL_WRT_QUOTE_NON_ASCII
    @test _tw_write(_tws("aé"), qna) == "aé"
    @test _tw_write(_tws("éa"), qna) == "éa"
    @test _tw_write(_tws("aŝ"), qna) == "'aŝ'"
    # #12: a bracket pair need not be above ASCII: '[]'(a) is written [a] (a list), '()'(a) (a)
    @test _tw_write(_twf("[]", _tws("a")), _TW_WRITEQ) == "[a]"
    @test _tw_write(_twf("()", _tws("a")), _TW_WRITEQ) == "(a)"
    @test _tw_write(_twf("⟨⟩", _tws("a")), _TW_WRITEQ) == "⟨a⟩"
end

@testset "the refusals: explicit, never a wrong text, a hang or a stack overflow" begin
    # a float: format_float is R1e's floats
    @test _tw_call("term_to_atom", _TW[_twf("f", lk_gnd(_TW, 1.5)), _tw_var()])[1] ===
        :notported
    @test _tw_write(lk_gnd(_TW, -0.0), _TW_WRITE) == "NOTPORTED"
    # an atom holding the character 0 (a string written quoted keeps it raw, as upstream): the
    # term interface's atoms cannot hold it; term_string/2's string can
    s0 = lk_gnd(_TW, "a\0b")
    @test _tw_call("term_to_atom", _TW[s0, _tw_var()])[1] === :notported
    rc, ans = _tw_call("term_string", _TW[s0, _tw_var()])
    @test rc === :true && lk_value(ans[2]) == "\"a\0b\""

    # a cyclic term: X = f(X) with the occurs check off (the flag's default)
    ld = LK.PL_local_data{_TW}()
    x = _tw_var()
    @test LK.unify_ptrs(ld, x, _twf("f", x))
    @test _tw_write(x, _TW_WRITEQ; ld=ld) == "NOTPORTED"
    @test _tw_call("term_to_atom", _TW[_twf("g", x), _tw_var()]; ld=ld)[1] === :notported
    @test _tw_call("term_string", _TW[x, _tw_var()]; ld=ld)[1] === :notported
    # …deep inside a term, and a cycle through two terms
    y, z = _tw_var(), _tw_var()
    @test LK.unify_ptrs(ld, y, _twf("[|]", _tws("a"), z))
    @test LK.unify_ptrs(ld, z, _twf("[|]", _tws("b"), y))
    @test _tw_write(_twf("h", _tws("a"), _twf("k", y)), _TW_PRINT; ld=ld) == "NOTPORTED"

    # a cyclic exception ball (V5d keeps its cycle): written, it is refused the same way
    gd2, ld2 = LK.PL_global_data{_TW}(), LK.PL_local_data{_TW}()
    b = _tw_var()
    th = LK.isCurrentProcedure(sym_key(_tws("throw")), 1, LK.MODULE_system(gd2))
    fid = LK.PL_open_foreign_frame(ld2)
    a = LK.PL_new_term_refs(ld2, 1)
    @test LK.unify_ptrs(ld2, b, _twf("error", _twf("e", b), _tw_var()))
    ld2.slots[a + 1] = b
    qid = LK.PL_open_query(
        gd2, ld2, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, th, a
    )
    @test LK.PL_next_solution(gd2, ld2, qid) == LK.PL_S_EXCEPTION
    ex = LK.PL_exception(ld2, qid)
    @test ex != 0 && !LK.is_acyclic(ld2, ld2.slots[ex + 1])
    @test _tw_write(ld2.slots[ex + 1], _TW_WRITEQ; gd=gd2, ld=ld2) == "NOTPORTED"
    LK.PL_close_query(ld2, qid)
    LK.PL_close_foreign_frame(ld2, fid)

    # user:portray/1 defined: print/1 would call it (the meta-call, V9) — refused; writeq/1 is not
    # affected, and with portray/1 undefined print/1 writes as swipl (the differential above)
    gd3, ld3 = LK.PL_global_data{_TW}(), LK.PL_local_data{_TW}()
    @test _tw_write(_twf("f", _tws("a")), _TW_PRINT; gd=gd3, ld=ld3) == "f(a)"
    @test _tw_call("assertz", _TW[_twf("portray", _tw_var())]; gd=gd3, ld=ld3)[1] === :true
    @test _tw_write(_twf("f", _tws("a")), _TW_PRINT; gd=gd3, ld=ld3) == "NOTPORTED"
    @test _tw_write(_tw_var(), _TW_PRINT; gd=gd3, ld=ld3) != "NOTPORTED"    # no call on a variable
    @test _tw_write(_twf("f", _tws("a")), _TW_WRITEQ; gd=gd3, ld=ld3) == "f(a)"
end

@testset "a compound with no symbol head is written '\$expr'(…) (the kernel's \$expr/n)" begin
    v = _tw_var()
    t = mk_expr(_TW, _TW[v, _tws("a"), lk_gnd(_TW, Int64(1))])
    m = match(r"^'\$expr'\((_[0-9]+),a,1\)$", _tw_write(t, _TW_WRITEQ))
    @test m !== nothing
    @test _tw_write(mk_expr(_TW, _TW[_twf("f", _tws("x"))]), _TW_WRITEQ) == "'\$expr'(f(x))"
end

@testset "depth: no recursion, as upstream's explicit stack" begin
    n = 100_000
    t = _tws("a")
    for _ in 1:n
        t = _twf("f", t)
    end
    @test _tw_write(t, _TW_WRITEQ) == "f("^n * "a" * ")"^n
    l = mk_nil(_TW)
    for i in 1:n
        l = _twf("[|]", _tw_int(i % 10), l)
    end
    @test _tw_write(l, _TW_WRITEQ) == "[" * join((i % 10 for i in n:-1:1), ",") * "]"
    p = _tws("a")
    for _ in 1:n
        p = _twf("-", p)
    end
    @test _tw_write(p, _TW_WRITEQ) == "- "^(n - 1) * "-a"
    o = _tws("a")
    for _ in 1:n
        o = _twf("+", o, _tws("b"))
    end
    @test _tw_write(o, _TW_WRITEQ) == "a" * "+b"^n
end
