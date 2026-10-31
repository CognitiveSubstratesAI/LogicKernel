#!/usr/bin/env python3
# Generator of the O1A rows (format/2,3 against swipl 10.1.19): writes o1a_rows.pl and driver.pl here, runs swipl
# TWICE (the two outputs must be byte-identical), writes o1a_rows.out, then test/core_lang/test_format_swipl.jl
# with the cases and the pins in it. Usage: python3 -I gen_rows.py <worktree>
import subprocess, sys, os

WT = sys.argv[1]
EV = os.path.join(WT, "evidence", "O1A")

PROGRAM = r"""
hello_out :- write(hello).
nested_out :- format("<~w>", [inner]).
col_out :- write(abc), format("~t~w~8|", [x]).
nl_out :- write(a), nl, write(b).
thrower :- throw(boom).
failer :- fail.
tabs(0, S, S) :- !.
tabs(N, S0, S) :- string_concat(S0, "~t", S1), N1 is N-1, tabs(N1, S1, S).
"""

# (id, goal, comment); the goal binds R. A goal that fails has no answer line; an error E is R = raised(E).
CASES = [
 # text directives
 ("f01", r'''format(atom(R), "hello", [])''', "plain text"),
 ("f02", r'''format(atom(R), "~a|~w|~q", ['a b', 'c d', 'e f'])''', "a, w, q"),
 ("f03", r'''format(atom(R), "~p", ['a b'])''', "print"),
 ("f04", r'''format(atom(R), "~s", [[104,105]])''', "codes"),
 ("f05", r'''format(atom(R), "~s", ["hi"])''', "string"),
 ("f06", r'''format(atom(R), "~i~w", [skip, shown])''', "ignore"),
 ("f07", r'''format(atom(R), "~k", [f('A b', [1,2], "s")])''', "write_canonical"),
 ("f08", r'''format(atom(R), "~c~3c~*c", [65, 0'x, 3, 0'y])''', "chars"),
 ("f09", r'''format(atom(R), "~w", x)''', "non-list argument"),
 ("f10", r'''format(atom(R), "~w ~w", "ab")''', "string argument is one argument"),
 ("f11", r'''format(atom(R), '~w', [1.5])''', "atom format text"),
 ("f12", r'''format(atom(R), [0'a, 0'~, 0'w], [b])''', "code list format text"),
 ("f13", r'''format(string(R), "~w~a", [x, y])''', "string sink"),
 ("f14", r'''format(codes(R), "ab", [])''', "codes sink"),
 ("f15", r'''format(chars(R), "ab", [])''', "chars sink"),
 ("f16", r'''format(atom(R), "~~ ~n~2n~N", [])''', "tilde and newlines"),
 ("f17", r'''format(atom(R), "ab~Ncd~N~N", [])''', "~N only at column 0"),
 ("f18", r'''format(atom(R), "~a", [1])''', "a with a number"),
 ("f19", r'''format(atom(R), "~a~a", ["s", 'é'])''', "a with a string and a non-ASCII atom"),
 # integers
 ("f20", r'''format(atom(R), "~d|~2d|~0d", [1234567, 1234567, 12])''', "d"),
 ("f21", r'''format(atom(R), "~D|~2D", [1234567, 1234567])''', "D"),
 ("f22", r'''format(atom(R), "~d|~D", [-5, -1234567])''', "negative"),
 ("f23", r'''format(atom(R), "~d|~2d", [1+2, -5])''', "an expression, small negative with a point"),
 ("f24", r'''format(atom(R), "~8r|~16r|~16R|~2r", [64, 255, 255, 5])''', "radix"),
 ("f25", r'''format(atom(R), "~I|~3I|~I", [1234567, 1234567, 12])''', "I"),
 ("f26", r'''format(atom(R), "~*d", [2, 1234])''', "star argument"),
 ("f27", r'''format(atom(R), "~d|~D|~2d", [123456789012345678901234567890, 123456789012345678901234567890, 123456789012345678901234567890])''', "bignum d"),
 ("f28", r'''format(atom(R), "~19d|~2d", [18446744073709551616, 18446744073709551616])''', "fraction digits just below and at the digit count (more digits than that reads past the buffer in swipl: its answer varies, no row)"),
 ("f29", r'''format(atom(R), "~36r|~16r", [1295, -255])''', "radix limits and a negative"),
 # floats
 ("f30", r'''format(atom(R), "~e|~3e|~0e", [1.5, 1.5, 1.5])''', "e"),
 ("f31", r'''format(atom(R), "~f|~2f|~0f|~0f", [2.5, 3.14159, 2.5, 0.5])''', "f, ties to even"),
 ("f32", r'''format(atom(R), "~g|~3g|~g|~g", [0.1, 1234.5678, 1.0e10, 1.0e-5])''', "g"),
 ("f33", r'''format(atom(R), "~h|~3h|~H|~0h", [0.1, 1.0e10, 1.0e-10, 1.5e20])''', "h and H"),
 ("f34", r'''format(atom(R), "~E|~G|~F", [1.5, 1.0e-10, 2.5])''', "capitals"),
 ("f35", r'''format(atom(R), "~2f|~2f|~f", [5, -5, 7])''', "small integers go through the float path"),
 ("f36", r'''format(atom(R), "~e|~f|~g", [1r3, 1r3, 1r3])''', "rational default digits"),
 ("f37", r'''format(atom(R), "~3g|~g|~G|~0g", [1r3, 1r30000000, 1r30000000, 1r4])''', "rational g"),
 ("f38", r'''format(atom(R), "~2g|~2g|~g|~g", [199r200, 199r2, 1r100000, 1r10000])''', "rational g ties and exponent bounds"),
 ("f39", r'''format(atom(R), "~e|~0e|~2E|~e", [1r3, 1r3, 1r300, -1r10])''', "rational e"),
 ("f40", r'''format(atom(R), "~0e|~2e|~e|~3e", [19r2, -999r1000, 1r1000000000000000000000000000000, 9999r1000])''', "rational e rounding"),
 ("f41", r'''format(atom(R), "~2f|~2f|~2f|~0f", [1r3, -1r300, -5r3, -4r3])''', "rational f"),
 ("f42", r'''format(atom(R), "~0f|~0f|~0f|~3f|~1f", [1r2, -1r2, 3r2, -1r2000, 199r2000])''', "rational f ties away from zero"),
 ("f43", r'''format(atom(R), "~2f|~0f", [1000000000000000000000000000000, -1000000000000000000000000000000])''', "bignum f"),
 ("f44", r'''format(atom(R), "~25f|~30f|~3f", [18446744073709551616, 18446744073709551616, 18446744073709551616])''', "bignum f padding"),
 ("f45", r'''X is 10**30, format(atom(R), "~e|~0e|~g|~3G|~h", [X, X, X, X, X])''', "bignum e g h"),
 ("f46", r'''X is -12345678901234567890123, format(atom(R), "~3e|~2g|~f", [X, X, X])''', "negative bignum"),
 ("f47", r'''X is 10**30+10**24, format(atom(R), "~7g|~g|~2g", [X, X, 123456789012345678901234567890])''', "bignum g digits"),
 ("f48", r'''format(atom(R), "~h|~h|~h", [1r3, 100, 1.0Inf])''', "h of a rational and an integer"),
 ("f49", r'''format(atom(R), "~f", [1.5NaN])''', "NaN"),
 # columns
 ("f50", r'''format(atom(R), "~a~t~10|~a", [ab, cd])''', "pad right"),
 ("f51", r'''format(atom(R), "~t~a~10|~a", [ab, cd])''', "pad left"),
 ("f52", r'''format(atom(R), "~t~a~t~10|~a", [ab, cd])''', "centre"),
 ("f53", r'''format(atom(R), "~`-t~30|", [])''', "fill character"),
 ("f54", r'''format(atom(R), "~a~t~a~20|~a", [left, right, end])''', "two columns"),
 ("f55", r'''format(atom(R), "~t~d~6|~t~d~12|", [1, 22])''', "numbers right aligned"),
 ("f56", r'''format(atom(R), "~a~t~10+~a~t~10+~a", [ab, cd, ef])''', "relative columns"),
 ("f57", r'''format(atom(R), "~`xt~a~`yt~12|", [mid])''', "two rubbers"),
 ("f58", r'''format(atom(R), "ab~nc~t~5|d", [])''', "column after a newline"),
 ("f59", r'''format(atom(R), "~a~t~3|~a", [abcdef, x])''', "text longer than the column"),
 ("f60", r'''format(atom(R), "~t~w~10|", ['é'])''', "non-ASCII width"),
 ("f61", r'''format(atom(R), "~a~t~a~t~a~21|", [a, b, c])''', "three parts, two rubbers, remainder spread"),
 ("f62", r'''format(atom(R), "~t~a~8|~t~a~8+", [ab, cd])''', "column then relative column"),
 ("f63", r'''format(atom(R), "~*c~t~w~12|", [3, 0'., x])''', "star char before a column"),
 ("f64", r'''format(atom(R), "~w~30|~w", [a, b])''', "column without rubber pads on the right"),
 # ~@ and the output stack (tellString / toldString)
 ("f65", r'''format(atom(R), "[~@]", [hello_out])''', "call-back output"),
 ("f66", r'''format(atom(R), "a~@b~@c", [hello_out, nested_out])''', "two call-backs, one with a nested format"),
 ("f67", r'''format(atom(R), "~@~t~12|x", [hello_out])''', "call-back output counts in the column"),
 ("f68", r'''format(atom(R), "ab~@~t~8|x", [nl_out])''', "call-back with a newline resets the column"),
 ("f69", r'''format(atom(R), "~a~@~a", [x, failer, y])''', "failing call-back fails format"),
 ("f70", r'''catch(format(atom(R0), "~a~@~a", [x, thrower, y]), B, R = caught(B))''', "throwing call-back"),
 ("f71", r'''format(atom(R), "~@", [col_out])''', "call-back with its own column"),
 ("f72", r'''with_output_to(atom(R), format("a~tb~10|c~@", [hello_out]))''', "format/2 inside with_output_to"),
 ("f73", r'''with_output_to(string(R), (write(x), format("~t~w~6|", [y]), write(z)))''', "column continues the stream's position"),
 ("f74", r'''format(atom(R), "~a~@~t~a~12|", [xx, hello_out, end])''', "call-back and a rubber"),
 # errors
 ("e01", r'''format(atom(R), "~a", [])''', "not enough arguments"),
 ("e02", r'''format(atom(R), "~a", [x, y])''', "too many arguments"),
 ("e03", r'''format(atom(R), "~d", [a])''', "d of an atom"),
 ("e04", r'''format(atom(R), "~d", [1.0])''', "d of a float"),
 ("e05", r'''format(atom(R), "~c", [-1])''', "c of a negative"),
 ("e06", r'''format(atom(R), "~1r", [10])''', "radix 1"),
 ("e07", r'''format(atom(R), "~r", [10])''', "r without radix"),
 ("e08", r'''format(atom(R), "~z", [x])''', "unknown directive"),
 ("e09", r'''format(atom(R), "~s", [a])''', "s of an atom"),
 ("e10", r'''format(atom(R), "~-1f", [1])''', "negative digits"),
 ("e11", r'''format(atom(R), "~e", [a])''', "e of an atom"),
 ("e12", r'''format(atom(R), "~a", [f(x)])''', "a of a compound"),
 ("e13", r'''format(atom(R), "~*c", [a, 0'x])''', "star with an atom"),
 ("e14", r'''format(atom(R), X, [])''', "unbound format text"),
 ("e15", r'''format(atom(R), "~w", [_|_])''', "partial list"),
 ("e16", r'''format(atom(R), "~I", [a])''', "I of an atom"),
 ("e17", r'''format(atom(R), "~37r", [10])''', "radix 37"),
 ("e18", r'''format(atom(R), "~`", [])''', "fill character without text"),
 ("e19", r'''format(atom(R), "~12", [])''', "column argument without a directive"),
 # added for the mutant list (tools/mutants/O1A.py): rubber before a call-back, tab stop after a newline, ~N:|, ~Ns, ~W, bignum radix
 ("f75", r'''format(atom(R), "~t~@~12|x", [hello_out])''', "rubber pending before a call-back"),
 ("f76", r'''format(atom(R), "a~t~6|~nb~t~4+c", [])''', "relative column after a newline starts at 0"),
 ("f77", r'''format(atom(R), "abcdef~3:|x", [])''', "colon column stop left of the column: newline and re-indent"),
 ("f78", r'''format(atom(R), "abcdef~`-t~3:|x", [])''', "colon column stop with a fill character: re-indent with it"),
 ("f79", r'''format(atom(R), "~2s|~5s|~s", ["hello", "hi", [104,105]])''', "s with a count: cut and padded"),
 ("f80", r'''format(atom(R), "~2s|~4s", [[0'x, 256, 0'y], [0'x, 256]])''', "s of wide text with a count"),
 ("f81", r'''format(atom(R), "~W|~W", [f(1,'a b'), [quoted(true)], 'c d', [quoted(true)]])''', "W: write_term options"),
 ("f82", r'''format(atom(R), "~-1h", [1.0])''', "minus sign before the digits of h"),
 ("f83", r'''X is 2**70+255, format(atom(R), "~16r|~16R|~8r|~2d", [X, X, X, X])''', "bignum radix (letters) and fraction digits"),
 ("f84", r'''X is -(2**70), format(atom(R), "~d|~D|~2D", [X, X, X])''', "negative bignum d and D"),
 ("f85", r'''format(atom(R), "a~t~+b~t~+c", [])''', "relative column default 8"),
 ("e20", r'''tabs(101, "", F), format(atom(R), F, [])''', "more fill points than MAXRUBBER"),
 ("e21", r'''format(atom(R), "~-d", [1])''', "minus sign without digits"),
 ("f86", r'''format(atom(R0), "x~@y", [Z = 1]), ( var(Z) -> R = [R0, unbound] ; R = [R0, bound] )''', "call-back bindings are undone"),
 ("f87", r'''format(atom(R), "abc~|def~t~|g", [])''', "column stop without an argument is the current column"),
 ("f88", r'''format(atom(R), "abcdef~t~3|y~t~6|z", [])''', "the column after an overflowing stop is the stop"),
 ("f89", r'''format(atom(R), "ab~tcd", [])''', "fill point never closed by a column stop"),
 ("f90", r'''format(atom(R), "ab~t~3|c", [])''', "one column of padding"),
 ("f91", r'''format(atom(R), "~D|~D|~D", [123456, 999, -123456])''', "D with digit counts that are multiples of 3"),
 ("f92", r'''X is -(10**20), format(atom(R), "~D|~2D", [X, X])''', "negative bignum with a digit count that is a multiple of 3"),
 ("f93", r'''format(atom(R), "~d|~2d|~D", [0, 0, 0])''', "zero with and without fraction digits"),
 ("f94", r'''X is 10**30-1, format(atom(R), "~e|~3e|~29e|~30e", [X, X, X, X])''', "bignum e: exponent guess one too big, digits equal to the exponent"),
 ("f95", r'''format(atom(R), "~e|~e|~2e", [1r9, 1r8, 1r1000])''', "rational e: exponent guess corrections"),
 ("f96", r'''format(atom(R), "~F|~E|~G|~f|~0g", [1.5NaN, 1.5NaN, 1.5NaN, 1.0Inf, 123.456])''', "capital NaN, infinity, g with 0 digits"),
 ("f97", r'''format(atom(R), "ab~t~@~t~12|x", [hello_out])''', "call-back through a string at column 2"),
 ("f98", r'''format(atom(R), "~d~t~8|~e~t~20|x", [12, 1.5])''', "numbers advance the column when no fill point is pending"),
 ("e22", r'''format(atom(R), f(x), [])''', "format text of the wrong type"),
 ("e23", r'''format(atom(R), "~W", [x])''', "W with one argument"),
 ("e24", r'''format(atom(R), "~@", [])''', "@ without an argument"),
]

DRIVER = r'''
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
fz_pred(N) :-
    format("~w", [N]), functor(G, N, 1),
    catch(findnsols(50, G, G, Gs), _, Gs = [exception]),
    forall(member(S, Gs), ( S == exception -> write(' exception') ; write(' '), enc(S) )), nl.
fz_run(File, Ns) :-
    catch(( consult(File), S = ok ), E, S = exc(E)),
    ( S == ok -> writeln(ok) ; S = exc(B), write('exc '), enc(B), nl ),
    forall(member(N, Ns), fz_pred(N)).
'''

def program_file():
    t = PROGRAM
    for (i, g, _) in CASES:
        t += "t_%s(R) :- catch((%s), error(SsuE, _), R = raised(SsuE)).\n" % (i, g)
    return t

names = ["t_" + c[0] for c in CASES]
open(os.path.join(EV, "o1a_rows.pl"), "w").write(program_file())
drv = DRIVER + ":- initialization((fz_run('%s', [%s]), halt)).\n" % (os.path.join(EV, "o1a_rows.pl"), ",".join(names))
open(os.path.join(EV, "driver.pl"), "w").write(drv)

def run():
    return subprocess.run(["swipl", "-q", os.path.join(EV, "driver.pl")], stdin=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL, capture_output=False, stdout=subprocess.PIPE, check=False).stdout.decode()
a, b = run(), run()
assert a == b, "two swipl runs differ"
open(os.path.join(EV, "o1a_rows.out"), "w").write(a)
print(len(a.splitlines()), "lines;", len(CASES), "cases")

# ---- the Julia test file ------------------------------------------------------------------------------------------
import re
SRC = open(os.path.join(WT, "test", "core_lang", "test_at_body_swipl.jl")).read().split("\n")
def lines(a, b):  # 1-based inclusive
    return "\n".join(SRC[a - 1:b])
def rename(t):
    return t.replace("_AB", "_FM").replace("_ab", "_fm").replace("mod3b.pl", "o1a.pl")

i_k = next(i for i, l in enumerate(SRC) if l.startswith('"The kernel\'s lines for'))
j_k = next(i for i in range(i_k, len(SRC)) if SRC[i] == "end")
KERNEL = lines(i_k + 1, j_k + 1)
i_d = next(i for i, l in enumerate(SRC) if l.startswith("using Test"))
j_d = next(i for i, l in enumerate(SRC) if l.startswith("function _ab_swipl_lines"))
k_d = next(i for i in range(j_d, len(SRC)) if SRC[i] == "end")
HEAD = lines(i_d + 1, k_d + 1)

pins = a.split("\n")[:-1]
case_src = "\n".join('    ("%s", raw"""%s"""),  # %s' % (i, g, c) for (i, g, c) in CASES)
pin_src = "\n".join('    "%s",' % p for p in pins)
prog_src = PROGRAM

KNOWN = [
 ("k01", 'format(atom(R), "~:d|~2:d|~:D", [1234567, 1234567, 1234567])', "1234567|12345.67|1_234_567", "1,234,567|12,345.67|1_234_567"),
 ("k02", 'format(atom(R), "~:f|~2:e", [1234567.5, 1234567.5])', "1234567.500000|1.23e+06", "1,234,567.500000|1.23e+06"),
]
known_src = "\n".join('    ("%s", raw"""%s""", "%s", "%s"),' % k for k in KNOWN)

TEST = '''# ORIGINAL: O1A's gate (lk-channel evidence/R2 design for O1) — format/2,3 (pl-fmt.c do_format, formatInteger, formatFloat,
# the column machinery, `~@` through the output redirect) against swipl 10.1.19; generated by evidence/O1A/gen_rows.py.
# test/core_lang/test_format_swipl.jl — every `~` directive family and the errors, as clauses of a consulted program (the loader):
#   * cases `t_<id>(R)` run IN ORDER in one database, each wrapped in `catch(Goal, error(SsuE, _), R = raised(SsuE))`; R is the text
#     format/3 wrote to an atom, string, codes or chars sink (the output redirect: tellString / toldString), or the error formal.
#   * Every answer line is swipl's, PINNED (swipl 10.1.19, evidence/O1A/o1a_rows.out, two byte-identical runs); with `swipl` on PATH
#     the live answers are compared with the pins too. UNVERIFIED on the kernel: gate decides (a mismatch is traced, not re-pinned).
#   * `~:d` and `~:f` print the C locale on the kernel (a stream has no locale, D9): their rows pin the kernel's answer, swipl's in the row.
''' + rename(HEAD) + '''

# the program the cases call (the `~@` call-backs)
const _FM_PROGRAM = raw"""''' + prog_src + '''"""

# (id, goal), run IN ORDER
const _FM_CASES = [
''' + case_src + '''
]

# swipl 10.1.19's answer to each case, in order (the driver's whole output)
const _FM_PINNED = [
''' + pin_src + '''
]

# rows whose swipl answer is locale grouped: (id, goal, kernel's answer, swipl's answer); the kernel prints the C locale (D9)
const _FM_KNOWN = [
''' + known_src + '''
]

"The program and cases as one file; the case predicates' names."
function _fm_file(cases)::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in cases]
    text =
        _FM_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\\n" for
            (id, g) in cases
        ])
    f = joinpath(mktempdir(), "o1a.pl")
    write(f, text)
    return f, names
end

''' + rename(KERNEL) + '''

"The driver's line for the case `id` answering the atom `s`."
_fm_atomline(id::String, s::String)::String = "t_$id c" * _fm_codes("t_$id") * "/1(a" * _fm_codes(s) * ")"

@testset "format/2,3 as swipl's (f01-f74, e01-e19)" begin
    f, names = _fm_file(_FM_CASES)
    kl, _, _ = _fm_kernel(f, names)
    @test length(kl) == length(_FM_PINNED)
    for (k, p) in zip(kl, _FM_PINNED)
        k == p || println(stderr, "  ours  ", k, "\\n  swipl ", p)
        @test k == p
    end
    # not vacuous: both sides hold answers, the error rows raised, the column rows pad with spaces (code 32), the call-back
    # rows hold the call-backs' output (hello: 104,101,108,108,111), the failing call-back row has no answer
    @test length(kl) > 80 && !any(isempty, kl)
    @test count(l -> occursin("c[114,97,105,115,101,100]", l), _FM_PINNED) >= 15           # raised(…)
    @test count(l -> occursin("32,32,32", l), _FM_PINNED) >= 12                              # column padding
    @test count(l -> occursin("104,101,108,108,111", l), _FM_PINNED) >= 6                   # hello_out through ~@
    @test _FM_PINNED[findfirst(l -> startswith(l, "t_f69"), _FM_PINNED)] == "t_f69"        # the failing call-back
    @test any(l -> startswith(l, "t_f70 ") && occursin("c[99,97,117,103,104,116]/1(a[98,111,111,109])", l), _FM_PINNED)  # caught(boom)
end

@testset "~:d and ~:f on the kernel: the C locale (D9), swipl's grouping noted per row" begin
    f, names = _fm_file([(id, g) for (id, g, _, _) in _FM_KNOWN])
    kl, _, _ = _fm_kernel(f, names)
    @test length(kl) == length(_FM_KNOWN) + 1
    for ((id, g, ours, swipl_says), k) in zip(_FM_KNOWN, kl[2:end])
        @test k == _fm_atomline(id, ours)
        @test ours != swipl_says                                                        # the row records a known difference
    end
    # swipl's own answers, live: grouped by the locale
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl !== nothing
        f, names = _fm_file([(id, g) for (id, g, _, _) in _FM_KNOWN])
        @test _fm_swipl_lines(f, names)[2:end] == [_fm_atomline(id, sw) for (id, _, _, sw) in _FM_KNOWN]
    end
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    @test length(_FM_PINNED) == length(_FM_CASES) + 1
    if swipl === nothing
        @info "O1A LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        f, names = _fm_file(_FM_CASES)
        @test _fm_swipl_lines(f, names) == _FM_PINNED
    end
end
'''
open(os.path.join(WT, "test", "core_lang", "test_format_swipl.jl"), "w").write(TEST)
print("test file written")
