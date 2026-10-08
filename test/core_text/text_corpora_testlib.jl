# ORIGINAL: the text corpora the reader's, writer's and round-trip differentials share (R1d, R1e, R1f).
# test/core_text/text_corpora_testlib.jl — the corpora of test_read_term_swipl.jl (R1d's hand texts),
# test_write_swipl.jl (R1e's hand texts) and their random-term generator, shared since R1f by
# test_roundtrip_swipl.jl. Data and a generator generic over the term type; each including file
# runs in a module of its own (test/runtests.jl), so the constants are defined once per file.

# The differential's code list of a text.
_tc_codes(s::String)::String = "[" * join(Int.(collect(s)), ",") * "]"
_tc_sym(::Type{T}, x) where {T} = lk_sym(T, Symbol(x))
_tc_f(::Type{T}, f, xs...) where {T} = mk_expr(T, T[_tc_sym(T, f), xs...])
_tc_int(::Type{T}, n::Integer) where {T} =
    typemin(Int64) <= n <= typemax(Int64) ? lk_gnd(T, Int64(n)) : lk_gnd(T, BigInt(n))

# ── R1d: the reader's hand corpus ──────────────────────────────────────────────────────────────
const _TR_CORPUS = [
    "a", "f(X,Y,X)", "a+b*c", "a*b+c", "a-b-c", "a^b^c", "2 ** 3", "2 ** 3 ** 4", "- 1",
    "-1",
    "-(1)", "- (1)", "-(-(1))", "- - 1", "- - - a", "-a", "- a", "-(a)", "a- -1", "a - -1",
    "a- - -b", "1 - -1", "1 -1", "a * - 1", "a * -1", "a - (-1)", "- (1) ^ 2", "-(1) ^ 2",
    "- 1 ^ 2", "-1 ^ 2", "- (a) * b", "-(a) * b", "- a * b", "a = \\+", "\\+a", "\\+ \\+ a",
    "\\+ (a,b)", "\\+(a)", "- (-)", "-(-)", "- -", "- - -", "- - - -", "(-)", "[-]",
    "- = -",
    "f(- , -)", "f(- , a)", "f(a, -)", "[-, +]", "- \$", "a\$b", "a:b:c", "a:-b,c;d->e",
    "(a,b;c->d)", "p :- a, b ; c -> d", "a :- b :- c", ":- a", ":- dynamic a/1, b/2.",
    "?- a",
    "a --> b", "dynamic a, b", "dynamic foo/1", "X is 1 + 2", "1 + 2 * 3 - 4", "2 ^ 3 ^ 4",
    "a=b", "a=..b", "a = '|'", "a '|' b", "'|'(a,b)", "a|b", "a | b", "(a|b)", "(a|b|c)",
    "a|", "(a|)", "|", "{a|b}", "f(a;b)", "f(a:-b)", "[a:-b]", "{a:-b}", "(a:-b)",
    "[a]", "[a,b|c]", "[a|b]", "[a|[]]", "[a|b|c]", "[a|b,c]", "[a|b,]", "[a|]", "[a,]",
    "[a", "[|]", "'[|]'", "[]", "'[]'", "[ ]", "{}", "'{}'", "{ }", "{a}", "{a,b}", "{,}",
    "- [a]", "-[a]", "- {a}", "p:-{a}", "a- {a}", "f()", "f( )", "f(,)", "f(a,)", "f(a",
    "f(a b)",
    "f(a)(b)", "f(a)[b]", "a[b]", "[a](b)", "{a}(b)", "(a", "a)", "{a", "a}", "(a,)",
    "(a;)",
    "a,", "- ,", "a ;", "f(a ;)", ":- ,", "a = ,", ",", "- (,)", "(a,b)", "a , b",
    "','(a,b)",
    "\"s\"", "\"abc\"", "\"a||b\"", "`abc`", "`a`", "0'a", "0'c", "0''", "0'''", "0' ",
    "0'\\n",
    "1r3", "-1r3", "1.5", "1.0e10", "-0.0", "1.0Inf", "1.5NaN",
    "123456789012345678901234567890",
    "0x1F", "16'FF", "-16'2f", "2'", "X", "_", "_X", "f(_,_)", "[X|Y]", "f(A,g(B),_,h(_C))",
    "'hello world'(x)", "'\\+'(a)", "'a'", "'A'", "a.b", "X.b", "a.B", "\"s\".b", "f(a).b",
    "[a].b", "a. b", "a .b", "1.e", "a.", "f(.)", "a = .", ". = a", "a % comment",
    "a /* c */",
    "end_of_file", "f(a).%x", "a::b", "«x»", "«x", "⟨a⟩", "⟨a, b⟩", "f(⟨a⟩)", "⟩",
    "a||b", "(a||b)", "{a||b}", "f(||)", "'||'", "[|a]", "{ |a}", "[ |a]", "0'||", "0'|a",
    "[a||b]", "[a||b|}]", "a||b|}", "f(a)||g", "[a ||b|}]", "f(a||b|})", "x+ab||b|}",
    "a b", "ab cd", "f(ab cd)", "f(a, bc de)", "[a, bc de]", "a∀", "aé", "é", "Ébc",
    "Ébc ébc",
    "<stream>(0x40e8900)", "f(<a>(b))", "a<b>(c)", "<(a,b)", "<>(a)", "f(a<b, c>d)",
    "a:-b:-c", "\"\\0\\x\"", "hello(\"\\000\\x\")", "'\\x\\'", "'\\x61\\'", "f(a, (b:-c))",
    "[a, (b,c)]", "f((a,b))", "- (1,2)", "-(1,2)", "a- (1)", "\\+ (-)", "-(-) ", "f(;)",
    "f(;, a)", "[;]", "{;}", "a = ;", "(;)", "f(!)", "!", "a!", "[!]", "f(:-)", "f(:- , a)",
    # upstream report #10: the arguments of end_of_file_in_quoted and undefined_char_escape
    "“x", "'\\q'", "'\\é'", "'\\Ω'", "'\\中'", "'\\∀'", "'\\😀'", "'\\Ā'",
    "a = (:-)", "- - - - - - - - 1", "f(- - - 1)", "'-' 1", "'-'(1)", "'-' (1)", "'-'",
    "'\\+' a",
    "a '=' b", "a '+' b", "'dynamic' a", "f('-', -)", "[X, f(Y), Z|T]", "[f(X), Y|g(Z)]",
    "f([A|B], {C}, (D, E))", "g(X, Y, Z, Y, X)", "[_, _A, _]"
]

# ── R1e: the writer's hand corpus ──────────────────────────────────────────────────────────────
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

# ── R1e: random terms, built on both sides from one encoding ───────────────────────────────────
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

"A random term of type `T`, depth at most `d`: its encoding for the swipl driver and the kernel term."
function _tc_gen(::Type{T}, rng, d::Int, vars::Vector{T})::Tuple{String, T} where {T}
    r = d <= 0 ? rand(rng, 1:6) : rand(rng, 1:14)
    if r == 1
        a = rand(rng, _TW_ATOMS)
        return ("a(" * _tc_codes(a) * ")", _tc_sym(T, a))
    elseif r == 2
        return ("nil", mk_nil(T))
    elseif r == 3
        n = rand(rng, _TW_INTS)
        return ("i($n)", _tc_int(T, n))
    elseif r == 4
        q = rand(rng, [1 // 3, -2 // 7, big(10)^20 // 3, -1 // big(10)^20])
        q = Rational{BigInt}(q)
        return ("q($(numerator(q)),$(denominator(q)))", lk_gnd(T, q))
    elseif r == 5
        s = rand(rng, _TW_STRINGS)
        return ("s(" * _tc_codes(s) * ")", lk_gnd(T, s))
    elseif r == 6
        k = rand(rng, 0:3)
        return ("v($k)", vars[k + 1])
    elseif r <= 9                                   # a compound named by any atom
        name = rand(rng, _TW_ATOMS)
        args = [_tc_gen(T, rng, d - 1, vars) for _ in 1:rand(rng, 1:3)]
        return (
            "c(" * _tc_codes(name) * ",[" * join(first.(args), ",") * "])",
            mk_expr(T, T[_tc_sym(T, name), last.(args)...])
        )
    elseif r == 10                                  # '$VAR'(…)
        x = if rand(rng, Bool)
            n = rand(rng, _TW_INTS)
            ("i($n)", _tc_int(T, n))
        else
            v = rand(rng, _TW_VARNAMES)
            ("a(" * _tc_codes(v) * ")", _tc_sym(T, v))
        end
        return ("c(" * _tc_codes("\$VAR") * ",[" * x[1] * "])", _tc_f(T, "\$VAR", x[2]))
    elseif r == 11                                  # a list, its tail [], a variable or a term
        n = rand(rng, 1:3)
        els = [_tc_gen(T, rng, d - 1, vars) for _ in 1:n]
        tail = rand(rng, [("nil", mk_nil(T)), ("v(0)", vars[1]), _tc_gen(T, rng, 0, vars)])
        enc, t = tail
        for (e, x) in reverse(els)
            enc = "c(" * _tc_codes("[|]") * ",[" * e * "," * enc * "])"
            t = _tc_f(T, "[|]", x, t)
        end
        return (enc, t)
    elseif r == 12                                  # a compound named by the reserved `[]`
        args = [_tc_gen(T, rng, d - 1, vars) for _ in 1:rand(rng, 1:2)]
        return (
            "cn([" * join(first.(args), ",") * "])",
            mk_expr(T, T[mk_nil(T), last.(args)...])
        )
    else                                            # an operator term of the right arity
        ops = LK.operators
        op = ops[rand(rng, 1:length(ops))]
        arity = (op[2] & LK.OP_MASK) == LK.OP_INFIX ? 2 : 1
        args = [_tc_gen(T, rng, d - 1, vars) for _ in 1:arity]
        return (
            "c(" * _tc_codes(op[1]) * ",[" * join(first.(args), ",") * "])",
            mk_expr(T, T[_tc_sym(T, op[1]), last.(args)...])
        )
    end
end
