# ORIGINAL: LB1's gate — the reader's term positions (src/pl-read.jl: subterm_positions and term_position) and read_clause/3 as a predicate, against swipl 10.1.19 through the driver beside this file (test_read_positions_swipl.pl).
# test/core_text/test_read_positions_swipl.jl — LB1's gate (the R2 design, loader_boot.md §7 LB1 and
# its test T6; audit D-0149). Every expected answer is swipl's, computed when the test runs by the
# driver test_read_positions_swipl.pl; nothing below is written by hand:
#   * SUBTERM POSITIONS at every term kind: read_term_from_atom/3 with term_position(TP) and
#     subterm_positions(P) on the reader's hand corpus (text_corpora_testlib.jl: operators of every
#     type and priority, prefix operators as atoms, lists, braces, parentheses, strings, `0'c`,
#     numbers, Unicode brackets, layout and comments, syntax errors), on texts aimed at each kind
#     (`From-To`, string_position, list_position with and without a tail, brace_term_position,
#     parentheses_term_position, term_position of a compound and of an operator, multi-byte text),
#     upstream's nested `positions` text (tests/core_text/test_read.pl), user operators — postfix,
#     infix-and-postfix, and BLOCK operators prefix, infix and postfix — and 500 random operator
#     terms swipl writes with writeq/1. `TP-P` is compared whole (TP stays unbound: a string
#     stream keeps no line number, pl-read.c `unify_read_term_position`); a syntax error as its ball.
#   * TERM_POSITION on a stream: read_clause/3 clause after clause on a text (lines, layout,
#     comments, tabs, CR-LF, multi-byte characters, end_of_file, empty text) — the kernel reads
#     `user_input` made a buffer (`set_standard_stream!`), swipl an open_string/2 stream: both
#     count characters, lines and bytes from 0, 1 and 0. The clause, its
#     '$stream_position'(CharNo, LineNo, LinePos, ByteNo), its subterm positions and its variable
#     names compared together; an instantiated position that does not unify fails the read.
#   * read_clause/3's ERRORS: a stream that is no atom, not a stream, an output stream, an options
#     list that is no list — the whole ball, as swipl raises it.
#   * The refused constructs (a dict, a quasi-quotation: R1's decision) stay NotPortedError and are
#     left out by name; nothing else may be refused.
using Test, LogicKernel, Random
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "text_corpora_testlib.jl"))
const _RP = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_rps(x) = lk_sym(_RP, Symbol(x))
_rpi(n::Integer) = lk_gnd(_RP, Int64(n))
_rpf(f, xs::_RP...) = mk_expr(_RP, _RP[_rps(f), xs...])
_rpl(xs::Vector{_RP}) = foldr((x, l) -> _rpf("[|]", x, l), xs; init=mk_nil(_RP))
_rp_var() = mk_var(_RP, LK.fresh_var_keys!(1))

const _RP_SWIPL = (
    get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
)
const _RP_SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"
const _RP_DRIVER = joinpath(@__DIR__, "test_read_positions_swipl.pl")

"""
The driver's encoding of a term (its `enc/1`): `V<n>` the n-th variable by first occurrence, `nil`
for `[]`, `a[codes]` an atom, `s[codes]` a string, `i…`, `q…r…`, `c[codes]/N(args)`. A float
never occurs in what this file compares (positions, balls, clauses without floats): `?float`.
"""
function _rp_enc(t::_RP, seen::Vector{UInt64}=UInt64[])::String
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
        return "a" * _rp_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _rp_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    hs = is_nil(h) ? "c[]" : "c" * _rp_codes(sym_text(h))
    return hs * "/$(nchildren(t) - 1)(" *
           join([_rp_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end
# A string holding a CUT UTF-8 sequence (src/pl-read.jl "end_of_file_in_quoted": upstream names the
# quote's first BYTE, `string("Â", 0)` for `«x`, which the kernel ports as is) has no code points:
# its bytes are the codes, which is the Latin-1 character swipl's driver encodes (194 for 0xC2).
_rp_codes(s::String)::String =
    "[" * join(isvalid(s) ? [Int(c) for c in s] : Int.(codeunits(s)), ",") * "]"

"A database of its own; `ops` declared by op/3 in `user` (`\"[]\"`: SWI-7's `[]`)."
function _rp_db(ops=())
    gd = LK.PL_global_data{_RP}()
    ld = LK.PL_local_data{_RP}(gd)
    LK.set_standard_stream!(ld, LK.SNO_USER_OUTPUT, IOBuffer())
    LK.set_standard_stream!(ld, LK.SNO_USER_ERROR, IOBuffer())
    LK.set_standard_stream!(ld, LK.SNO_USER_INPUT, IOBuffer())
    for (p, t, n) in ops
        name = n == "[]" ? mk_nil(_RP) : _rps(n)
        _rp_call((gd, ld), "op", _RP[_rpi(p), _rps(t), name])[1] === :solved ||
            error("op($p, $t, $n) failed")
    end
    return (gd, ld)
end

"""
Run the `system` predicate `name` on `args` through the query API: `(:solved, answers)` with every
argument exported once (shared variables stay shared), `(:exception, [ball])`, `(:failed, [])`, or
`(:notported, [])` where the kernel raises NotPortedError.
"""
function _rp_call(db, name::String, args::Vector{_RP})
    gd, ld = db
    proc = LK.isCurrentProcedure(sym_key(_rps(name)), length(args), LK.MODULE_system(gd))
    proc === nothing && error("no system predicate $name/$(length(args))")
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, length(args))
    pvm = LK.PutVarMap()            # one PutVarMap: these puts share their variables
    for (i, x) in enumerate(args)
        LK.putSlotValue!(ld, a + i, x, pvm)
    end
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    out = try
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            ex = LK.cell_export{_RP}()
            (:solved, _RP[LK.export_cells(ld, ex, -(a + i)) for i in 1:length(args)])
        elseif rc == LK.PL_S_EXCEPTION
            (:exception, _RP[lk_answer(ld, LK.PL_exception(ld, qid))])
        else
            (:failed, _RP[])
        end
    catch e
        e isa LK.NotPortedError || rethrow()
        (:notported, _RP[])
    end
    out[1] === :notported || LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    return out
end

"The driver's line for an outcome: the encoded success term, `fails`, `err <ball>`, `NOTPORTED`."
function _rp_line(rc::Symbol, ans::Vector{_RP}, success)::String
    rc === :solved && return _rp_enc(success(ans))
    rc === :exception && return "err " * _rp_enc(ans[1])
    rc === :notported && return "NOTPORTED"
    return "fails"
end

_rp_pair(a::_RP, b::_RP) = _rpf("-", a, b)
# the n-th element (from 1) of a proper list, and the argument of an option term there
_rp_nth(l::_RP, n::Int)::_RP = n == 1 ? child(l, 2) : _rp_nth(child(l, 3), n - 1)

"The driver's `pa/1` in the kernel: read_term_from_atom/3 with term_position(TP), subterm_positions(P): `TP-P`."
function _rp_pa(db, text::String)::String
    opts = _rpl(_RP[_rpf("term_position", _rp_var()), _rpf("subterm_positions", _rp_var())])
    rc, ans = _rp_call(db, "read_term_from_atom", _RP[_rps(text), _rp_var(), opts])
    return _rp_line(
        rc, ans,
        a -> _rp_pair(child(_rp_nth(a[3], 1), 2), child(_rp_nth(a[3], 2), 2))
    )
end

"""
A read option list for a row, `(name, arg)` each — `arg` `nothing` for a fresh variable, a `Symbol`
for an atom, or `(term, text)`: the term as the kernel's and as swipl's text. `_rp_opts` makes the
kernel's term, `_rp_opts_text` swipl's text.
"""
_rp_opt_arg(a::Nothing) = _rp_var()
_rp_opt_arg(a::Symbol) = _rps(a)
_rp_opt_arg(a::Tuple) = a[1]
_rp_opt_text(a::Nothing) = "_"
_rp_opt_text(a::Symbol) = lk_atom_text(_rps(a))
_rp_opt_text(a::Tuple) = a[2]
_rp_opts(spec)::_RP = _rpl(_RP[_rpf(n, _rp_opt_arg(a)) for (n, a) in spec])
_rp_opts_text(spec)::String =
    "[" * join([string(n, "(", _rp_opt_text(a), ")") for (n, a) in spec], ", ") * "]"

"""
The driver's `rc/2` in the kernel: `user_input` made a buffer holding `text`, read_clause/3 on it
clause after clause up to end_of_file (at most 51 reads, as the driver's), `Clause-Opts` each; then
the line `.`.
"""
function _rp_rc(db, text::String, spec)::Vector{String}
    gd, ld = db
    LK.set_standard_stream!(ld, LK.SNO_USER_INPUT, IOBuffer(Vector{UInt8}(codeunits(text))))
    lines = String[]
    for n in 0:50
        rc, ans = _rp_call(
            db, "read_clause", _RP[_rps("user_input"), _rp_var(), _rp_opts(spec)]
        )
        push!(lines, _rp_line(rc, ans, a -> _rp_pair(a[2], a[3])))
        rc === :solved || break
        t = ans[2]
        kind(t) === SYM && lk_name(t) === :end_of_file && break
    end
    push!(lines, ".")
    return lines
end

"swipl's lines: the driver loaded, `prelude` (directives) run, then `calls` (goal texts) in order."
function _rp_swipl(calls::Vector{String}; prelude::String="")::Vector{String}
    prog = IOBuffer()
    println(
        prog, ":- ensure_loaded('", replace(_RP_DRIVER, "\\" => "\\\\", "'" => "\\'"), "')."
    )
    print(prog, prelude)
    println(prog, "run :-")
    for c in calls
        println(prog, "    ", c, ",")
    end
    println(prog, "    true.\n:- initialization((run, halt)).")
    out = mktempdir() do d
        f = joinpath(d, "r.pl")
        write(f, String(take!(prog)))
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'))
end

"The driver call `pa/1` for `text`: its codes."
_rp_pa_call(text::String)::String = "pa([" * join(Int.(collect(text)), ",") * "])"
"The driver call `rc/2` for `text` and the option spec."
_rp_rc_call(text::String, spec)::String =
    "rc([" * join(Int.(collect(text)), ",") * "], " * _rp_opts_text(spec) * ")"

"Compare the kernel's and swipl's lines, printing the first divergences; the diverging rows."
function _rp_compare(labels, ours::Vector{String}, theirs::Vector{String}; label="")
    @test length(ours) == length(theirs)
    bad = [
        (labels[k], ours[k], theirs[k]) for
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

# R1's decision: a dict is refused, never misread — left out by name. No text here holds one
# (`-{a}` is in test_read_term_swipl.jl), and `{a||b}` (a quasi-quotation) is swipl's syntax error
# `end_of_file_in_quasi_quotation` without the quasi_quotations option, which the kernel raises
# too: compared (first run, 2026-10-25). Any NOTPORTED row therefore fails the test.
const _RP_REFUSED = Set{String}()

# texts aimed at each position term, layout and multi-byte text (char positions count characters)
const _RP_KINDS = [
    "a", "  a  ", "X", " _ ", "123", " -123.45 ", "0'a", "1r3", "'a b'", "[]", " [ ] ",
    "'[]'",
    "{}", "\"abc\"", "`abc`", " \"\" ", "f(a)", " f( a , b ) ", "f()", "f( )",
    "'hello world'(x)",
    "[a]", "[a,b]", "[ a , b | c ]", "[a|[]]", "[[a],[b|c]|d]", "{a}", "{ a , b }", "( a )",
    "((a))", "f((a,b))", "- (1)", "-(1)", "- 1", "-1", "- a", "-a", "- - a", "\\+ \\+ a",
    "a- -1", "a - (-1)", "1 - -1", "a = \\+", "- = -", "f(- , -)", "[-, +]", "(-)", "-",
    "=", "->", "is", ":-", "dynamic", "xfx",
    # a lone PREFIX operator above an argument's 999 stays on the operator stack to the end of its
    # level (modify_op: maxpri 999 <= right_pri) and is read as an atom there: its own position
    # (pl-read.c complex_term "single operator"; LB1-15)
    "f(:-)", "f( dynamic )", "[:-]", "[dynamic|dynamic]", "f(:-, dynamic)", "{:-}", "(:-)",
    "- (dynamic)", "a = (:-)",
    "a:b:c", "a:-b,c;d->e", "p :- a, b ; c -> d", "a = '|'", "(a|b)", "f(;, '|', '[]')",
    "a /* c */ + b", "a % c\n+ b", "f(a,\n  b)\n", "\tf(\ta)", "é(ü)", "α(β, γδ)",
    "'αβ' + \"γ\"", "[α|β]", "{α}", "«x»", "⟨a, b⟩", "f(⟨a⟩)", "a. b", "f(a", "[a|b,c]",
    "(a",
    "- (a,b)", "1 + 2 * 3 - 4", "2 ** 3 ** 4", "a=..b", "X is 1 + 2", ":- dynamic a/1, b/2",
    "f(a)(b)", "[a](b)", "end_of_file", "",
    # upstream's `positions` unit (tests/core_text/test_read.pl, read_deep): f( 100 deep
    "f("^100 * "x" * ")"^100,
    # nesting of every construct
    "f([{-(a)}])", "["^30 * "a" * "]"^30, "{"^30 * "a" * "}"^30, "("^30 * "a" * ")"^30,
    "- "^30 * "a", "a" * " + b"^30
]

# user operators: postfix and infix-and-postfix, prefix-and-infix, postfix BLOCK operators
const _RP_OPS1 = [(200, "xfx", "++"), (200, "xf", "++"), (300, "fy", "pre"),
    (300, "xfy", "pre"), (100, "yf", "[]"), (100, "yf", "{}"), (150, "yf", "@@")]
const _RP_TEXTS1 = ["a ++", "a ++ b", "a ++ ++", "(a ++) ++ b", "a ++ - b", "f(a ++)",
    "[a ++, b]", "pre a", "a pre b", "pre pre a", "pre", "a pre pre b", "a[b]", "a[b][c]",
    "f(x)[1,2]", "a {b}", "a {b}[c]", "X[Y]", "pre a[b]", "a[b] ++", "a @@", "a @@ @@",
    "- a @@", "a @@ + b", "f(a) @@"]
# PREFIX block operators (fy 200)
const _RP_OPS2 = [(200, "fy", "[]"), (200, "fy", "{}")]
const _RP_TEXTS2 = ["[x] _", "[x] a", "[x] [y] a", "[x]", "- [x] a", "f([x] a)",
    "[x] a = b",
    "{x} a", "[x] {y} a", "[a,b] c", "[x] f(a, b)"]
# INFIX block operators (xfx 700)
const _RP_OPS3 = [(700, "xfx", "[]"), (700, "xfx", "{}")]
const _RP_TEXTS3 = ["a [b] c", "a {b} c", "f(a [b] c)", "a [b,c] d", "(a [b] c)",
    "a {b} c , d"]

# read_clause/3 rows: (text, option spec); every text holds no float and no singleton
const _RP_ALL3 = [("term_position", nothing), ("subterm_positions", nothing),
    ("variable_names", nothing)]
const _RP_CLAUSES = [
    ("foo(X) :- bar(X).\n  % c\n  baz.\n\n/* x */ q(a,\n b).", _RP_ALL3),
    ("α(β). γ.\nδ(\"ε\").", _RP_ALL3),
    ("a.\tb.\r\nc.  ", _RP_ALL3),
    ("", _RP_ALL3),
    ("   \n  ", _RP_ALL3),
    ("a :- b.\n% only a comment at the end\n", _RP_ALL3),
    (
        "p :- q, r ; s -> t.\n[a,b|c].\n{x,y}.\n\"str\".\n'q a'(x).\n- (1).\nf(- 1, -1, a- -1).\n",
        _RP_ALL3),
    ("f(X, Y) :- g(Y, X).\n  h([X|Y]) :- k(X, Y).", _RP_ALL3),
    ("x. y.", [("variable_names", nothing)]),
    ("x. y.", [("term_position", nothing)]),
    ("x. y.", [("subterm_positions", nothing)]),
    ("a.", [("term_position", :foo)]),
    ("a.", [("subterm_positions", :foo)]),
    (
        "f(x).",
        [(
            "subterm_positions",
            (
                _rpf(
                    "term_position",
                    _rpi(0),
                    _rpi(4),
                    _rpi(0),
                    _rpi(1),
                    _rpl(_RP[_rpf("-", _rpi(2), _rpi(3))])
                ),
                "term_position(0,4,0,1,[2-3])"
            )
        )]
    ),
    (
        "f(x).",
        [(
            "subterm_positions",
            (
                _rpf(
                    "term_position",
                    _rpi(0),
                    _rpi(4),
                    _rpi(0),
                    _rpi(1),
                    _rpl(_RP[_rpf("-", _rpi(1), _rpi(3))])
                ),
                "term_position(0,4,0,1,[1-3])"
            )
        )]
    )
]

# read_clause/3's errors: (stream, options) as the kernel's terms and swipl's text
const _RP_ERRORS = [
    (_rps("foo"), mk_nil(_RP), "read_clause(foo, _, [])"),
    (_rp_var(), mk_nil(_RP), "read_clause(_, _, [])"),
    (_rpi(1), mk_nil(_RP), "read_clause(1, _, [])"),
    (_rpf("f", _rps("x")), mk_nil(_RP), "read_clause(f(x), _, [])"),
    (_rps("user_output"), mk_nil(_RP), "read_clause(user_output, _, [])"),
    (_rps("user_error"), mk_nil(_RP), "read_clause(user_error, _, [])"),
    (_rps("user_input"), _rps("foo"), "read_clause(user_input, _, foo)"),
    (_rps("user_input"), _rpl(_RP[_rpi(1)]), "read_clause(user_input, _, [1])")
]

if _RP_SWIPL !== nothing
    @testset "subterm positions == swipl: the hand corpus and every term kind" begin
        db = _rp_db()
        texts = vcat(_TR_CORPUS, _RP_KINDS)
        ours = [_rp_pa(db, t) for t in texts]
        theirs = _rp_swipl(_rp_pa_call.(texts))
        refused = Set(texts[k] for k in eachindex(texts) if ours[k] == "NOTPORTED")
        @test refused == _RP_REFUSED                # refused by name; nothing else
        keep = [k for k in eachindex(texts) if !(texts[k] in _RP_REFUSED)]
        _rp_compare(texts[keep], ours[keep], theirs[keep])
        # floors (swipl 10.1.19, 2026-10-25: 365 texts — term_position 170, list_position 27,
        # brace_term_position 19, parentheses_term_position 30, string_position 14, errors 92)
        @test count(
            contains("c[116,101,114,109,95,112,111,115,105,116,105,111,110]/5"), ours
        ) > 150
        @test count(
            contains("c[108,105,115,116,95,112,111,115,105,116,105,111,110]/4"), ours
        ) > 20
        @test count(contains("c[98,114,97,99,101,95"), ours) > 10        # brace_term_position
        @test count(contains("c[112,97,114,101,110,116,104,101,115,101,115,95"), ours) > 20
        @test count(contains("c[115,116,114,105,110,103,95,112,111"), ours) > 10  # string_position
        @test count(startswith("err "), ours) > 80
    end

    @testset "subterm positions == swipl: user operators, postfix and block operators" begin
        for (ops, texts) in
            ((_RP_OPS1, _RP_TEXTS1), (_RP_OPS2, _RP_TEXTS2), (_RP_OPS3, _RP_TEXTS3))
            db = _rp_db(ops)
            prelude = ":- " * join(("op($p, $t, $n)" for (p, t, n) in ops), ", ") * ".\n"
            ours = [_rp_pa(db, t) for t in texts]
            theirs = _rp_swipl(_rp_pa_call.(texts); prelude=prelude)
            @test !any(==("NOTPORTED"), ours)
            _rp_compare(texts, ours, theirs; label=" (user ops)")
            @test count(startswith("err "), ours) < length(ours) ÷ 3
        end
    end

    # The single-operator branch (src/pl-read.jl complex_term, upstream pl-read.c:5498) is reached
    # ONLY with the iso flag: without it `maxpri` is 1201 (pl-read.c:5290) and modify_op turns every
    # lone prefix operator into an operand. TRACED 2026-10-27 (a probe in the branch): `f(:-)` and
    # `[dynamic]` reach it with iso, never without. The kernel has no set_prolog_flag/2 yet (R2 F1b):
    # the iso bit is set WHITE-BOX in the local data's mask, as test_prolog_flag_swipl.jl does;
    # swipl's side runs set_prolog_flag(iso, true) first. Kills LB1-15.
    @testset "subterm positions == swipl: lone operators under the iso flag" begin
        texts = ["f(:-)", "[dynamic]", "f(:-, dynamic)", "[a, -]", "f(- )", "{:-}"]
        db = _rp_db()
        ld = db[2]
        ld.prolog_flag_mask |= LK.prologFlagMask(LK.PLFLAG_ISO)
        @test LK.truePrologFlag(ld, LK.PLFLAG_ISO)
        ours = [_rp_pa(db, t) for t in texts]
        theirs = _rp_swipl(vcat(["set_prolog_flag(iso, true)"], _rp_pa_call.(texts)))
        @test !any(==("NOTPORTED"), ours)
        @test !any(startswith("err "), theirs)
        _rp_compare(texts, ours, theirs; label=" (iso)")
    end

    @testset "subterm positions == swipl: swipl's writeq of random operator terms" begin
        texts = [
            String(Char.(parse.(Int, split(strip(l, ['[', ']']), ',')))) for l in
            eachline(
                pipeline(
                    `swipl -q -g "gen_texts(500)" -t halt $_RP_DRIVER`;
                    stdin=devnull, stderr=devnull
                )
            ) if l != "[]"
        ]
        @test length(texts) >= 450
        db = _rp_db()
        ours = [_rp_pa(db, t) for t in texts]
        theirs = _rp_swipl(_rp_pa_call.(texts))
        @test !any(==("NOTPORTED"), ours)
        _rp_compare(texts, ours, theirs; label=" (writeq)")
        @test count(startswith("err "), theirs) < 10      # writeq's texts read back
    end

    @testset "read_clause/3 == swipl: term_position and subterm_positions on a stream" begin
        db = _rp_db()
        ours = String[]
        labels = String[]
        for (text, spec) in _RP_CLAUSES
            ls = _rp_rc(db, text, spec)
            append!(ours, ls)
            append!(labels, fill(text, length(ls)))
        end
        theirs = _rp_swipl([_rp_rc_call(t, s) for (t, s) in _RP_CLAUSES])
        @test !any(==("NOTPORTED"), ours)
        _rp_compare(labels, ours, theirs; label=" (read_clause)")
        sp = "c[36,115,116,114,101,97,109,95,112,111,115,105,116,105,111,110]/4"
        @test count(contains(sp), ours) > 25               # '$stream_position'/4 bound (30, 2026-10-25)
        @test count(==("fails"), ours) >= 2                # an instantiated position that does not unify
        @test count(==("."), ours) == length(_RP_CLAUSES)
    end

    @testset "read_clause/3's errors == swipl" begin
        db = _rp_db()
        ours = [
            _rp_line(_rp_call(db, "read_clause", _RP[s, _rp_var(), o])..., a -> a[1])
            for (s, o, _) in _RP_ERRORS
        ]
        theirs = _rp_swipl(["re($g)" for (_, _, g) in _RP_ERRORS])
        _rp_compare([g for (_, _, g) in _RP_ERRORS], ours, theirs; label=" (errors)")
        @test all(startswith("err "), ours)
    end
elseif _RP_SWIPL_REQUIRED
    error(
        "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the term-position differential would be skipped"
    )
else
    @info "TERM-POSITION DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
    @testset "term-position differential skipped only where it is not required" begin
        @test !_RP_SWIPL_REQUIRED
    end
end

# A WHITE-BOX row, hand-written: swipl cannot be asked. `user` names `Suser_input`, which a host
# may replace (`_PL_streams()`); upstream pl-file.c getInputStream refuses a stream that is not an
# input stream with permission_error(input, stream, user). Reached only through the alias `user`
# (a named stream is refused earlier, by get_stream_handle with SH_INPUT, the rows of
# `_RP_ERRORS`): the kernel's `user_input` is made an OUTPUT stream and read_clause/3 is asked.
@testset "read_clause/3 on user when user_input is not an input stream: permission_error" begin
    db = _rp_db()
    ld = db[2]
    ld.IO_streams[LK.SNO_USER_INPUT + 1] = ld.IO_streams[LK.SNO_USER_OUTPUT + 1]
    rc, ans = _rp_call(db, "read_clause", _RP[_rps("user"), _rp_var(), mk_nil(_RP)])
    @test rc === :exception
    rc === :exception || return nothing
    @test lk_eq(
        child(ans[1], 2),
        _rpf("permission_error", _rps("input"), _rps("stream"), _rps("user"))
    )
end

@testset "the refusals that stay: comments, var_prefix — read_clause/3 and read_term_from_atom/3" begin
    db = _rp_db()
    for (n, a) in (("comments", nothing), ("var_prefix", Symbol("true")))
        LK.set_standard_stream!(db[2], LK.SNO_USER_INPUT, IOBuffer("a."))
        rc, _ = _rp_call(
            db, "read_clause", _RP[_rps("user_input"), _rp_var(), _rp_opts([(n, a)])]
        )
        @test rc === :notported
        rc, _ = _rp_call(
            db, "read_term_from_atom", _RP[_rps("a"), _rp_var(), _rp_opts([(n, a)])]
        )
        @test rc === :notported
    end
end
