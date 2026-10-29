# ORIGINAL: SSU2's gate (lk-channel evidence/r2/design/ssu.md §6-§7) — single sided unification RUN, against swipl 10.1.19; swipl-devel at the pin has no SSU test file (its documentation is man/ssu.plx), so the rows are the design's.
# test/core_lang/test_ssu_swipl.jl — the run loop's `I_CHP`, `I_SSU_CHOICE`, `I_SSU_COMMIT`, `S_SSU_DET` and the matching-rule error
# (`ssu_or_det_failed`'s SSU branch, `put_frame_goal`):
#   * A PROGRAM of SSU predicates (the channel's evidence/r2/design/ssu_rows.pl, plus `lco/1` and the list helper `su_member/2`:
#     member/2 is library(lists), R2) consulted by the kernel's loader — the guard form goes through the consult stand-in's rewrite
#     (D7) — and cases `t_<id>(R)` run IN ORDER in one database: the s-rows (the match, the commit, `?=>`, guards, the errors'
#     goal and context; s54/s55 need library(lists), so s58/s59 ask the same of a module `ssu_m` asserted here), the d-rows
#     (determinism after `=>`: call_cleanup/2 sees no choice point) and a01/a04/a09 (an asserted SSU predicate runs). Each case
#     is wrapped in `catch(Goal, error(SsuE, _), R = raised(SsuE))`, so an error is an answer (after the answers before it).
#     Every answer line is swipl's, PINNED (swipl 10.1.19-1-gcbf4e189, this program and the driver below, 2026-10-29, stable over
#     two runs); with `swipl` on PATH the live answers are compared with the pins too.
#     Why the redo error (design §2.5) shows in s48/s49/d03 but not in s26/d05: catch/3's `I_EXITCATCH` and call_cleanup/2's
#     `I_EXITCLEANUP` step over `CHP_DEBUG` choice points (pl-vmi.c), so a `?=>` clause that exits inside them leaves none —
#     swipl answers s26 `yes` once and d05 `det` (probed outside the driver too).
#     s65-s67 (`gf/1`, `gb/2`, added at the gate: mutant SSU2-K1 survived s16/s50/d04): the guard form's cut clears
#     FR_SSU_DET (`I_CUT`), so a body that fails after it fails the call — swipl answers `no`, not the matching-rule error.
#   * The four ways to the matching-rule error (design §2.5), each a row: the index finds no clause (`S_STATIC` pushes `CHP_DEBUG`:
#     s04, s11, s46, s53); every head fails without binding (shallow_backtrack, then `I_CHP`'s `CHP_DEBUG`: s62); every trail
#     test fails (s03, s12, s34); a frame fails with no choice point of its own (`S_LIST` FRAME_FAILED, `frameFailed`: s60, s61).
#   * White-box (design H1): a head instruction that binds a cell of the goal under a choice point of the frame TRAILS it — the
#     test `I_SSU_*` makes is only as good as that; one plain two-clause predicate per head instruction kind.
#   * White-box (design D2/H2): at the query API, `=>` exits deterministically (`PL_S_LAST`: its choice point popped, whether
#     `I_CHP`'s or `S_STATIC`'s), `?=>` does not (`PL_S_TRUE`), and the redo raises the matching-rule error.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _SS = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_sss(x) = lk_sym(_SS, Symbol(x))

_ss_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _ss_enc(t::_SS, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _ss_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _ss_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _ss_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_ss_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

# the swipl side (test/compile/test_ssu_compile_swipl.jl's driver): consult, then every answer of each t_<id>/1, `enc`oded
const _SS_DRIVER = raw"""
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
"""
function _ss_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _SS_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stdin=devnull, stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

# the predicates under test (ssu_rows.pl's, `gmove`'s singleton spelled `_`; `lco/1` and `su_member/2` added)
const _SS_PROGRAM = raw"""
m(f(X), R) => R = X.
m(a, R) => R = atom_a.
eq(X, X) => true.
first(1, R) => R = one.
first(2, R) => R = two.
dup(a) => true.
dup(a) => fail.
'?=>'(nd(X), X = 1).
'?=>'(nd(X), X = 2).
bodyfail(_) => fail.
sign(X, S), X > 0 => S = pos.
sign(X, S), X < 0 => S = neg.
sign(0, S) => S = zero.
gmove(X), X = f(_) => true.
gcall(X), su_member(X, [1, 2]) => true.
bmove(X) => X = f(_).
'?=>'(cmove(X), (X = f(_), true)).
'?=>'(choicefail(_), fail).
zero => true.
'?=>'(zfail, fail).
gtrue(X), true => X = t.
cutbody(X) => X = 1, !.
lists([H|T], R) => R = H-T.
lists([], R) => R = nil.
deep(g(h(X), [Y]), R) => R = X-Y.
str("abc", R) => R = string.
big(123456789012345678901234567890, R) => R = big.
flt(1.5, R) => R = float.
voidh(_, _, R) => R = void.
'?=>'(ndcut(X), (X = 1, !)).
'?=>'(ndcut(X), X = 2).
'?=>'(ht(X), (X = f(Y), ht2(X, Y))).
ht2(_, _).
lco(X) => m(X, _).
'?=>'(pd(X), X = 1).
gf(X), X > 0 => fail.
gf(_) => true.
gb(X, Y), X > 0 => su_member(Y, [a, b]), Y == c.
gb(_, _) => true.
su_member(X, [X|_]).
su_member(X, [_|T]) :- su_member(X, T).
"""

# (id, goal), run IN ORDER (s52 uses the hook module s45 asserts; s59 the module s58 asserts; a09 adds to a01's d1/1)
const _SS_CASES = [
    # s01: a compound matches (H_FUNCTOR in read mode)
    ("s01", raw"m(f(1), R)"),
    # s02: an atom matches
    ("s02", raw"m(a, R)"),
    # s03: an unbound argument: every clause's trail test fails (S_STATIC + CHP_CLAUSE, then I_CHP's CHP_DEBUG)
    ("s03", raw"m(_, R)"),
    # s04: no clause at all: the index misses (S_STATIC pushes CHP_DEBUG)
    ("s04", raw"m(g, R)"),
    # s05: an unbound variable inside the argument: X = Y binds the clause's X, not Y
    ("s05", raw"m(f(Y), R), R == Y"),
    # s06: a repeated head variable: equal arguments match
    ("s06", raw"( eq(a, a) -> R = yes ; R = no )"),
    # s07: a repeated head variable would bind A = B: raises
    ("s07", raw"eq(A, B), R = A-B"),
    ("s08", raw"eq(A, A), R = same"),
    # s09: a binding inside compounds
    ("s09", raw"eq(f(A), f(B)), R = A-B"),
    # s10: the first-argument index selects clause 2
    ("s10", raw"first(2, R)"),
    # s11: an index miss raises, it does not fail
    ("s11", raw"first(3, R)"),
    # s12: an unbound first argument
    ("s12", raw"first(_, R)"),
    # s13: => commits: the second dup/1 clause never runs
    ("s13", raw"findall(x, dup(a), R)"),
    # s14: ?=> moved X = 1 into the head: the caller's X would be bound
    ("s14", raw"findall(X, nd(X), R)"),
    # s15: a body that fails after the commit: plain failure
    ("s15", raw"( bodyfail(x) -> R = yes ; R = no )"),
    # s16: the guard form (the consult stand-in's rewrite, D7)
    ("s16", raw"sign(5, R)"),
    ("s17", raw"sign(-5, R)"),
    ("s18", raw"sign(0, R)"),
    # s19: the guard raises
    ("s19", raw"sign(a, R)"),
    # s20: the guard raises: instantiation
    ("s20", raw"sign(_, R)"),
    # s21: a guard unification moved into the head matches
    ("s21", raw"( gmove(f(1)) -> R = yes ; R = no )"),
    # s22: the moved X = f(_) would bind Z: raises
    ("s22", raw"gmove(Z), R = Z"),
    # s23: a guard that is a call may bind (it runs after the match), then ! commits
    ("s23", raw"findall(Z, gcall(Z), R)"),
    # s24: => does not move: the body binds the caller's variable
    ("s24", raw"bmove(Z), R = Z"),
    # s25: ?=> moves a leading body unification: raises
    ("s25", raw"cmove(Z), R = Z"),
    # s26: the ?=> clause matched (an answer), then the redo of I_CHP's CHP_DEBUG raises
    ("s26", raw"cmove(f(a)), R = yes"),
    # s27: a ?=> body that fails without a cut: FR_SSU_DET still set, the error
    ("s27", raw"choicefail(x), R = no"),
    # s28: arity 0
    ("s28", raw"( zero -> R = yes ; R = no )"),
    # s29: arity 0, ?=> body fails
    ("s29", raw"zfail, R = no"),
    # s30: guard true (optimise off): ?=>(H, (true, !, B))
    ("s30", raw"gtrue(R)"),
    # s31: a cut in a => body
    ("s31", raw"findall(X, cutbody(X), R)"),
    # s32: S_LIST, the list clause
    ("s32", raw"lists([1,2], R)"),
    # s33: S_LIST, the nil clause
    ("s33", raw"lists([], R)"),
    # s34: S_LIST, unbound: S_STATIC, both trail tests fail
    ("s34", raw"lists(_, R)"),
    # s35: nested compounds
    ("s35", raw"deep(g(h(1), [2]), R)"),
    # s36: the tail would be bound to []: raises with the caller's arguments in the goal
    ("s36", raw"deep(g(h(1), [_|_]), R)"),
    # s37: a string constant (H_STRING)
    ("s37", raw"""str("abc", R)"""),
    # s38: a big integer (H_MPZ)
    ("s38", raw"big(123456789012345678901234567890, R)"),
    # s39: a float (H_FLOAT)
    ("s39", raw"flt(1.5, R)"),
    # s40: 3r2 is not 1.5 (SWI's identity): raises
    ("s40", raw"flt(3r2, R)"),
    # s41: voids merged before I_SSU_COMMIT
    ("s41", raw"voidh(a, _, R)"),
    # s42: ?=> with a moved X = 1 and a cut: both clauses would bind X
    ("s42", raw"findall(X, ndcut(X), R)"),
    # s43: \+ does not hide the error
    ("s43", raw"( \+ m(g, _) -> R = negated ; R = no )"),
    # s44: the goal in the error
    ("s44", raw"catch(m(g, _), error(existence_error(matching_rule, G), _), true), R = G"),
    # s45: binding an attributed variable is a binding: no hook runs, V stays an attvar (H8)
    (
        "s45",
        raw"assertz(ssu_rows_m:(attr_unify_hook(_, _) :- throw(hook_ran))), put_attr(V, ssu_rows_m, 1), catch(m(V, _), error(E, _), true), functor(E, F, _), ( attvar(V) -> R = F-attvar ; R = F-other )"
    ),
    # s46: the context: the frame's predicate (S_STATIC's CHP_DEBUG)
    ("s46", raw"catch(first(3, _), error(_, C), true), R = C"),
    # s47: the first answer only: the ?=> clause matched
    ("s47", raw"( cmove(f(a)) -> R = once ; R = no )"),
    # s48: backtracking INTO a ?=> that did not cut raises
    ("s48", raw"findall(x, cmove(f(a)), R)"),
    # s49: nd(1): one answer, then the same error on backtracking
    ("s49", raw"findall(x, nd(1), R)"),
    # s50: the guard form's (G, !, B): the cut clears FR_SSU_DET, no redo error
    ("s50", raw"findall(S, sign(5, S), R)"),
    # s51: the error, caught, then go on
    (
        "s51",
        raw"findall(x, (su_member(V, [f(a), g]), catch(m(V, _), error(_, _), true)), R)"
    ),
    # s52: an attributed variable repeated: no binding, a match
    ("s52", raw"put_attr(V, ssu_rows_m, 1), ( eq(V, V) -> R = same ; R = no )"),
    # s53: the context after an index miss
    ("s53", raw"catch(m(g, _), error(_, C), true), R = C"),
    # s56: a moved unification whose term the body uses again (CL_HEAD_TERMS)
    ("s56", raw"( ht(f(1)) -> R = yes ; R = no )"),
    ("s57", raw"catch(ht(_), error(E, _), true), R = E"),
    # s58: a predicate of a module other than user: the goal is Module:Goal (s54's case, without library(lists))
    (
        "s58",
        raw"assertz(ssu_m:(sp(a) => true)), catch(ssu_m:sp(b), error(E, _), true), R = E"
    ),
    # s59: its context names ssu_m:sp/1 (s55's case)
    ("s59", raw"catch(ssu_m:sp(c), error(_, C), true), R = C"),
    # s60: S_LIST with neither a list nor []: FRAME_FAILED with no choice point of the frame, so frameFailed raises
    ("s60", raw"lists(foo, R)"),
    # s61: frameFailed's context: environment_frame is the frame
    ("s61", raw"catch(lists(foo, _), error(_, C), true), R = C"),
    # s62: every head fails (H_NIL against [3]), no binding: shallow_backtrack, then I_CHP's CHP_DEBUG
    ("s62", raw"deep(g(h(1), [2,3]), R)"),
    # s63: a => call under a caller's choice point: one answer each
    ("s63", raw"findall(X-Y, (su_member(X, [1,2]), first(X, Y)), R)"),
    # s64: a => body's last call (I_DEPART reuses the frame) to an SSU predicate that does not match: the callee's goal and context
    ("s64", raw"catch(lco(g), error(E, C), true), R = E-C"),
    # s65: the guard form's cut clears FR_SSU_DET (I_CUT): a body that fails after it fails the call, no matching-rule error
    ("s65", raw"(gf(1) -> R = yes ; R = no)"),
    # s66: the same with a choice point left in the body, then failing
    ("s66", raw"(gb(1, _) -> R = yes ; R = no)"),
    # s67: the guard fails before the cut, the next clause matches
    ("s67", raw"(gf(0) -> R = yes ; R = no)"),
    # s68: a ?=> body that binds a goal variable, under call_cleanup/2: the matching-rule error on the FIRST call (swipl 10.1.19)
    ("s68", raw"(call_cleanup(pd(_), true), R = done)"),
    # d01: determinism: => pops its choice point (I_CHP's CHP_DEBUG)
    (
        "d01",
        raw"call_cleanup(first(1, _), Det = true), ( Det == true -> R = det ; R = nondet )"
    ),
    # d02: => pops S_STATIC's CHP_CLAUSE (dup/1 has two candidates)
    ("d02", raw"call_cleanup(dup(a), Det = true), ( Det == true -> R = det ; R = nondet )"),
    (
        "d03",
        raw"call_cleanup(nd(_), Det = true), !, ( Det == true -> R = det ; R = nondet )"
    ),
    # d04: the guard form's cut
    (
        "d04",
        raw"call_cleanup(sign(5, _), Det = true), ( Det == true -> R = det ; R = nondet )"
    ),
    # d05: a ?=> that exits inside call_cleanup/2: I_EXITCLEANUP steps over its CHP_DEBUG, so det (the redo error never comes)
    (
        "d05",
        raw"call_cleanup(cmove(f(a)), Det = true), ( Det == true -> R = det ; R = nondet )"
    ),
    # a01: an asserted (dynamic) SSU predicate runs: S_SSU_DET before S_DYNAMIC
    ("a01", raw"assertz((d1(X) => X = one)), d1(R)"),
    ("a04", raw"assertz((d4(a) => true)), catch(d4(b), error(E, _), true), R = E"),
    # a09: the => clause commits first: [one]
    ("a09", raw"assertz('?=>'(d1(X), X = two)), findall(X, d1(X), R)")
]

# swipl 10.1.19-1-gcbf4e189's answers to the program and cases above (the driver's lines)
const _SS_PINNED = [
    "ok",
    "t_s01 c[116,95,115,48,49]/1(i1)",
    "t_s02 c[116,95,115,48,50]/1(a[97,116,111,109,95,97])",
    "t_s03 c[116,95,115,48,51]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[109]/2(V0,V1))))",
    "t_s04 c[116,95,115,48,52]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[109]/2(a[103],V0))))",
    "t_s05 c[116,95,115,48,53]/1(V0)",
    "t_s06 c[116,95,115,48,54]/1(a[121,101,115])",
    "t_s07 c[116,95,115,48,55]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[101,113]/2(V0,V1))))",
    "t_s08 c[116,95,115,48,56]/1(a[115,97,109,101])",
    "t_s09 c[116,95,115,48,57]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[101,113]/2(c[102]/1(V0),c[102]/1(V1)))))",
    "t_s10 c[116,95,115,49,48]/1(a[116,119,111])",
    "t_s11 c[116,95,115,49,49]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[102,105,114,115,116]/2(i3,V0))))",
    "t_s12 c[116,95,115,49,50]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[102,105,114,115,116]/2(V0,V1))))",
    "t_s13 c[116,95,115,49,51]/1(c[91,124,93]/2(a[120],nil))",
    "t_s14 c[116,95,115,49,52]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[110,100]/1(V0))))",
    "t_s15 c[116,95,115,49,53]/1(a[110,111])",
    "t_s16 c[116,95,115,49,54]/1(a[112,111,115])",
    "t_s17 c[116,95,115,49,55]/1(a[110,101,103])",
    "t_s18 c[116,95,115,49,56]/1(a[122,101,114,111])",
    "t_s19 c[116,95,115,49,57]/1(c[114,97,105,115,101,100]/1(c[116,121,112,101,95,101,114,114,111,114]/2(a[101,118,97,108,117,97,98,108,101],c[47]/2(a[97],i0))))",
    "t_s20 c[116,95,115,50,48]/1(c[114,97,105,115,101,100]/1(a[105,110,115,116,97,110,116,105,97,116,105,111,110,95,101,114,114,111,114]))",
    "t_s21 c[116,95,115,50,49]/1(a[121,101,115])",
    "t_s22 c[116,95,115,50,50]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[103,109,111,118,101]/1(V0))))",
    "t_s23 c[116,95,115,50,51]/1(c[91,124,93]/2(i1,nil))",
    "t_s24 c[116,95,115,50,52]/1(c[102]/1(V0))",
    "t_s25 c[116,95,115,50,53]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[99,109,111,118,101]/1(V0))))",
    "t_s26 c[116,95,115,50,54]/1(a[121,101,115])",
    "t_s27 c[116,95,115,50,55]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[99,104,111,105,99,101,102,97,105,108]/1(a[120]))))",
    "t_s28 c[116,95,115,50,56]/1(a[121,101,115])",
    "t_s29 c[116,95,115,50,57]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],a[122,102,97,105,108])))",
    "t_s30 c[116,95,115,51,48]/1(a[116])",
    "t_s31 c[116,95,115,51,49]/1(c[91,124,93]/2(i1,nil))",
    "t_s32 c[116,95,115,51,50]/1(c[45]/2(i1,c[91,124,93]/2(i2,nil)))",
    "t_s33 c[116,95,115,51,51]/1(a[110,105,108])",
    "t_s34 c[116,95,115,51,52]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[108,105,115,116,115]/2(V0,V1))))",
    "t_s35 c[116,95,115,51,53]/1(c[45]/2(i1,i2))",
    "t_s36 c[116,95,115,51,54]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[100,101,101,112]/2(c[103]/2(c[104]/1(i1),c[91,124,93]/2(V0,V1)),V2))))",
    "t_s37 c[116,95,115,51,55]/1(a[115,116,114,105,110,103])",
    "t_s38 c[116,95,115,51,56]/1(a[98,105,103])",
    "t_s39 c[116,95,115,51,57]/1(a[102,108,111,97,116])",
    "t_s40 c[116,95,115,52,48]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[102,108,116]/2(q3r2,V0))))",
    "t_s41 c[116,95,115,52,49]/1(a[118,111,105,100])",
    "t_s42 c[116,95,115,52,50]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[110,100,99,117,116]/1(V0))))",
    "t_s43 c[116,95,115,52,51]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[109]/2(a[103],V0))))",
    "t_s44 c[116,95,115,52,52]/1(c[109]/2(a[103],V0))",
    "t_s45 c[116,95,115,52,53]/1(c[45]/2(a[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114],a[97,116,116,118,97,114]))",
    "t_s46 c[116,95,115,52,54]/1(c[99,111,110,116,101,120,116]/2(c[47]/2(a[102,105,114,115,116],i2),V0))",
    "t_s47 c[116,95,115,52,55]/1(a[111,110,99,101])",
    "t_s48 c[116,95,115,52,56]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[99,109,111,118,101]/1(c[102]/1(a[97])))))",
    "t_s49 c[116,95,115,52,57]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[110,100]/1(i1))))",
    "t_s50 c[116,95,115,53,48]/1(c[91,124,93]/2(a[112,111,115],nil))",
    "t_s51 c[116,95,115,53,49]/1(c[91,124,93]/2(a[120],c[91,124,93]/2(a[120],nil)))",
    "t_s52 c[116,95,115,53,50]/1(a[115,97,109,101])",
    "t_s53 c[116,95,115,53,51]/1(c[99,111,110,116,101,120,116]/2(c[47]/2(a[109],i2),V0))",
    "t_s56 c[116,95,115,53,54]/1(a[121,101,115])",
    "t_s57 c[116,95,115,53,55]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[104,116]/1(V0)))",
    "t_s58 c[116,95,115,53,56]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[58]/2(a[115,115,117,95,109],c[115,112]/1(a[98]))))",
    "t_s59 c[116,95,115,53,57]/1(c[99,111,110,116,101,120,116]/2(c[58]/2(a[115,115,117,95,109],c[47]/2(a[115,112],i1)),V0))",
    "t_s60 c[116,95,115,54,48]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[108,105,115,116,115]/2(a[102,111,111],V0))))",
    "t_s61 c[116,95,115,54,49]/1(c[99,111,110,116,101,120,116]/2(c[47]/2(a[108,105,115,116,115],i2),V0))",
    "t_s62 c[116,95,115,54,50]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[100,101,101,112]/2(c[103]/2(c[104]/1(i1),c[91,124,93]/2(i2,c[91,124,93]/2(i3,nil))),V0))))",
    "t_s63 c[116,95,115,54,51]/1(c[91,124,93]/2(c[45]/2(i1,a[111,110,101]),c[91,124,93]/2(c[45]/2(i2,a[116,119,111]),nil)))",
    "t_s64 c[116,95,115,54,52]/1(c[45]/2(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[109]/2(a[103],V0)),c[99,111,110,116,101,120,116]/2(c[47]/2(a[109],i2),V1)))",
    "t_s65 c[116,95,115,54,53]/1(a[110,111])",
    "t_s66 c[116,95,115,54,54]/1(a[110,111])",
    "t_s67 c[116,95,115,54,55]/1(a[121,101,115])",
    "t_s68 c[116,95,115,54,56]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[112,100]/1(V0))))",
    "t_d01 c[116,95,100,48,49]/1(a[100,101,116])",
    "t_d02 c[116,95,100,48,50]/1(a[100,101,116])",
    "t_d03 c[116,95,100,48,51]/1(c[114,97,105,115,101,100]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[110,100]/1(V0))))",
    "t_d04 c[116,95,100,48,52]/1(a[100,101,116])",
    "t_d05 c[116,95,100,48,53]/1(a[100,101,116])",
    "t_a01 c[116,95,97,48,49]/1(a[111,110,101])",
    "t_a04 c[116,95,97,48,52]/1(c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[100,52]/1(a[98])))",
    "t_a09 c[116,95,97,48,57]/1(c[91,124,93]/2(a[111,110,101],nil))"
]

"The program and cases as one file; the case predicates' names."
function _ss_file()::Tuple{String, Vector{String}}
    names = ["t_$(id)" for (id, _) in _SS_CASES]
    text =
        _SS_PROGRAM * join([
            "t_$(id)(R) :- catch(($g), error(SsuE, _), R = raised(SsuE)).\n" for
            (id, g) in _SS_CASES
        ])
    f = joinpath(mktempdir(), "ssu2.pl")
    write(f, text)
    return f, names
end

"The kernel's lines for `names` after consulting `path`, as the driver writes swipl's; the database, for the white-box tests."
function _ss_kernel(path::String, names::Vector{String})
    gd = LK.PL_global_data{_SS}()
    ld = LK.PL_local_data{_SS}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * _ss_enc(ball::_SS)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_sss(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_SS, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(
                    sols,
                    _ss_enc(mk_expr(_SS, _SS[_sss(name), lk_answers(ld, (a:a)...)...]))
                )
                rc == LK.PL_S_LAST && break
            elseif rc == LK.PL_S_EXCEPTION
                push!(sols, "exception")
                break
            else
                break
            end
        end
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
        push!(out, "$name" * join(" " .* sols))
    end
    return out, gd, ld
end

@testset "SSU clauses run as swipl's (s01-s68, d01-d05, a01/a04/a09)" begin
    f, names = _ss_file()
    kl, _, _ = _ss_kernel(f, names)
    @test length(kl) == length(_SS_PINNED)
    for (k, p) in zip(kl, _SS_PINNED)
        @test k == p
    end
    # not vacuous: the rows hold matches, matching-rule errors, both determinism answers and the redo error
    @test count(l -> occursin("c[114,97,105,115,101,100]", l), _SS_PINNED) >= 20     # raised(…)
    @test count(l -> endswith(l, "/1(a[100,101,116])"), _SS_PINNED) >= 4             # det
    @test any(
        l -> startswith(l, "t_s48 ") && occursin("c[99,109,111,118,101]", l), _SS_PINNED
    )
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "SSU2 LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        @test length(_SS_PINNED) == length(_SS_CASES) + 1   # the pins still cover every case ("ok" + one line each)
    else
        f, names = _ss_file()
        @test _ss_swipl_lines(f, names) == _SS_PINNED
    end
end

# ---- white-box (design H1): a binding of a goal cell under a choice point of the frame is TRAILED. Each predicate has two
# clauses and is called with unbound arguments, so `S_STATIC` pushes a `CHP_CLAUSE` (its mark sets `mark_bar` at `gTop`, above
# the argument's cell) before clause 1's head binds the argument with the instruction named.
const _SS_WB_PROGRAM = raw"""
wb_atom(a).
wb_atom(b).
wb_int(1).
wb_int(2).
wb_nil([]).
wb_nil(x).
wb_float(1.5).
wb_float(x).
wb_mpz(123456789012345678901234567890).
wb_mpz(x).
wb_mpq(3r2).
wb_mpq(x).
wb_string("abc").
wb_string(x).
wb_functor(f(_)).
wb_functor(x).
wb_list([_|_]).
wb_list(x).
wb_var(X, X).
wb_var(x, y).
"""
const _SS_WB = [
    ("wb_atom", 1, "H_ATOM"), ("wb_int", 1, "H_SMALLINT"), ("wb_nil", 1, "H_NIL"),
    ("wb_float", 1, "H_FLOAT"), ("wb_mpz", 1, "H_MPZ"), ("wb_mpq", 1, "H_MPQ"),
    ("wb_string", 1, "H_STRING"), ("wb_functor", 1, "H_FUNCTOR"), ("wb_list", 1, "H_LIST"),
    ("wb_var", 2, "H_VAR")
]

@testset "H1 white-box: each head instruction that binds a goal cell trails the binding" begin
    f = joinpath(mktempdir(), "wb.pl")
    write(f, _SS_WB_PROGRAM)
    _, gd, ld = _ss_kernel(f, String[])
    for (name, arity, instr) in _SS_WB
        proc = LK.isCurrentProcedure(
            sym_key(_sss(name)), arity, LK.MODULE_user(gd)
        )::LK.Procedure{_SS}
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, arity)
        for i in 1:arity
            LK.putSlotValue!(ld, a + i, mk_var(_SS, LK.fresh_var_keys!(1)), LK.PutVarMap())
        end
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        t0 = length(ld.trail)
        rc = LK.PL_next_solution(gd, ld, qid)
        @test (instr, rc) == (instr, LK.PL_S_TRUE)           # clause 2 is left: the CHP_CLAUSE
        @test (instr, length(ld.trail) > t0) == (instr, true)
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
    end
end

# ---- white-box (design D2, H2): the determinism the query API reports. swipl's answers: d01, d02, d04 (det), d05's `?=>`
# outside call_cleanup/2 (a choice point left), s48 (the redo error), and the redo error's formal and context, probed
# (`catch((cmove(f(a)), fail), error(F, C), true)`, swipl 10.1.19, 2026-10-29).
const _SS_REDO_FORMAL = "c[101,120,105,115,116,101,110,99,101,95,101,114,114,111,114]/2(a[109,97,116,99,104,105,110,103,95,114,117,108,101],c[99,109,111,118,101]/1(c[102]/1(a[97])))"
const _SS_REDO_CONTEXT = "c[99,111,110,116,101,120,116]/2(c[47]/2(a[99,109,111,118,101],i1),V0)"

"Open a query on `name(args…)` (`args` terms; a `nothing` is a fresh variable) with the extended status."
function _ss_open(gd, ld, name::String, args::Vector)
    proc = LK.isCurrentProcedure(
        sym_key(_sss(name)), length(args), LK.MODULE_user(gd)
    )::LK.Procedure{_SS}
    a = isempty(args) ? 0 : LK.PL_new_term_refs(ld, length(args))
    for (i, x) in enumerate(args)
        v = x === nothing ? mk_var(_SS, LK.fresh_var_keys!(1)) : x
        LK.putSlotValue!(ld, a + i, v, LK.PutVarMap())
    end
    return LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
end

@testset "D2/H2 white-box: => exits deterministically, ?=> leaves its choice point and raises on redo" begin
    f, _ = _ss_file()
    _, gd, ld = _ss_kernel(f, String[])
    one = mk_gnd(_SS, Int64(1))
    for (name, args) in (
        ("first", [one, nothing]),          # I_CHP's CHP_DEBUG popped by I_SSU_COMMIT
        ("dup", [_sss("a")]),               # S_STATIC's CHP_CLAUSE popped by I_SSU_COMMIT
        ("m", [mk_expr(_SS, _SS[_sss("f"), one]), nothing]),
        ("zero", [])
    )
        fid = LK.PL_open_foreign_frame(ld)
        qid = _ss_open(gd, ld, name, args)
        @test (name, LK.PL_next_solution(gd, ld, qid)) == (name, LK.PL_S_LAST)
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
    end
    fid = LK.PL_open_foreign_frame(ld)
    qid = _ss_open(gd, ld, "cmove", [mk_expr(_SS, _SS[_sss("f"), _sss("a")])])
    @test LK.PL_next_solution(gd, ld, qid) == LK.PL_S_TRUE       # I_CHP's CHP_DEBUG is left
    @test LK.PL_next_solution(gd, ld, qid) == LK.PL_S_EXCEPTION  # backtracking into it: FR_SSU_DET is set
    ball = lk_answer(ld, LK.PL_exception(ld, qid))
    @test _ss_enc(child(ball, 2)) == _SS_REDO_FORMAL
    @test _ss_enc(child(ball, 3)) == _SS_REDO_CONTEXT
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
end

# ---- white-box (D-0213, D-0219, flag F1): `I_EXITCATCH` and `I_EXITCLEANUP` step over the `CHP_DEBUG` record `I_CHP` pushed
# for a `?=>` clause that exited without a cut (`pe/1`: one clause, so no `CHP_CLAUSE`; `I_SSU_CHOICE` leaves the record; its body
# binds no goal variable — one that does raises the matching-rule error under call_cleanup/2 in swipl, row s68). Upstream
# (pl-vmi.c:4908-4911, :4843-4844) only moves `BFR` past it, and so does the kernel: the record, in the pool, is released by
# `exit_continue`'s `lowerLTop!` (src/pl-wam.jl) before any reader of the pools' invariant (V9d) runs. A REGRESSION GUARD:
# the check of test/core_lang/rules_common.jl `_rpools_live` at EVERY answer, while the region is still in use (`su_member/2`
# after the catch/cleanup leaves a choice point) and bare. Answers as swipl's: f1c/f1u a-1, a-2; f1c0/f1u0 a (trivially).
const _SS_F1_PROGRAM = raw"""
'?=>'(pe(a), true).
f1c0(X) :- catch(pe(a), _, true), X = a.
f1u0(X) :- setup_call_cleanup(true, pe(a), true), X = a.
f1c(X, Y) :- catch(pe(a), _, true), X = a, su_member(Y, [1, 2]).
f1u(X, Y) :- setup_call_cleanup(true, pe(a), true), X = a, su_member(Y, [1, 2]).
su_member(X, [X|_]).
su_member(X, [_|T]) :- su_member(X, T).
"""

"`_rpools_live` (test/core_lang/rules_common.jl) for this file's term type: the pools hold exactly the live records."
function _ss_pools_live(ld::LK.PL_local_data{_SS})::Bool
    nch = 0
    c = ld.BFR
    fr = Set{Int}()
    chain = Set{Int}()
    while c != 0
        push!(chain, c)
        ld.choices[c].unlinked && return false              # on the chain: not unlinked
        c = ld.choices[c].parent
    end
    for i in 1:(ld.nchoices)                                # off the chain: unlinked, region in use
        i in chain && continue
        (ld.choices[i].unlinked && ld.choices[i].base < ld.lTop) || return false
        nch += 1
    end
    all(i -> i <= ld.nchoices, chain) || return false
    c = ld.BFR
    while c != 0
        nch += 1
        f = ld.choices[c].frame
        while f != 0 && !(f in fr)
            push!(fr, f)
            f = ld.frames[f].parent
        end
        c = ld.choices[c].parent
    end
    f = ld.environment_frame
    while f != 0 && !(f in fr)
        push!(fr, f)
        f = ld.frames[f].parent
    end
    return nch == ld.nchoices && length(fr) == ld.nframes &&
           (isempty(fr) || maximum(fr) == ld.nframes)
end

@testset "F1 white-box: the CHP_DEBUG records I_EXITCATCH / I_EXITCLEANUP step over leave the pools exact" begin
    f = joinpath(mktempdir(), "ssu2_f1.pl")
    write(f, _SS_F1_PROGRAM)
    out, gd, ld = _ss_kernel(f, String[])
    @test out == ["ok"]
    for (name, arity, nanswers) in
        (("f1c0", 1, 1), ("f1u0", 1, 1), ("f1c", 2, 2), ("f1u", 2, 2))
        fid = LK.PL_open_foreign_frame(ld)
        qid = _ss_open(gd, ld, name, Any[nothing for _ in 1:arity])
        live = Bool[]
        while true
            rc = LK.PL_next_solution(gd, ld, qid)
            (rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST) || break
            push!(live, _ss_pools_live(ld))
            rc == LK.PL_S_LAST && break
        end
        @test (name, length(live)) == (name, nanswers)
        @test (name, live) == (name, fill(true, nanswers))
        LK.PL_close_query(ld, qid)
        LK.PL_close_foreign_frame(ld, fid)
    end
end
