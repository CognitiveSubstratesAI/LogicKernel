# ORIGINAL: tests of the frame clearing and the body-mode lTop of the stack collector (G1-GC G1-A: src/pl-gcdriver.jl `clearLocalVariablesFrame`, `setLTopInBody`,
# and the field `trim_stack_requested`; upstream's pl-gc.c at the pin 18168e62), and the rows of the UPSTREAM tests/GC/test_ch_shift.pl (2 tests) and
# tests/GC/test_cleanup_shift.pl (12 tests) as kernel rows (the TABTEST style: unit text verbatim in a module, one pinned row per test).
# allow-new-artifact: G1-A, the test of the frame helpers (src/pl-gcdriver.jl), after test/core_lang/test_gc_vmi_state.jl
# test/core_lang/test_gc_frames.jl:
#   * `clearLocalVariablesFrame` (pl-gc.c:1427-1437): on the frame of a clause with variables, the slots from `arity` up to `clause->prolog_vars` become the
#     never-written word 0 and nothing else is written (the arguments, the cell above); the three arms that write nothing: no clause (:1428 `fr->clause`),
#     a foreign predicate (:1428 `isoff(fr->predicate, P_FOREIGN)`), a clause with no variable beyond the arguments (the `for` of :1433 does not run);
#   * `setLTopInBody` (pl-gc.c:3812-3817): `get_vmi_state` for its side effect only: in the body of a clause, `lTop` is raised over the argument frame under
#     construction and NOT put back (`restore_vmi_state` is not called), never lowered; in a head, outside a VM query and with no query it is unchanged;
#   * `trim_stack_requested` (pl-alloc.c:695, pl-setup.c:1715, pl-gc.c:4549): set by an overflow, cleared by `trimStacks!`, read by the driver, where a
#     set flag shrinks a grown local stack and a clear one leaves it;
#   * the upstream rows (below): `t_<id>(R)`, R = ok / failed / raised(E), each pinned on the pinned swipl AND equal to the plunit expectation.
# Every comparison reads both sides through ONE extractor, both non-empty; every must-fail arm is a corrupted pin or a changed premise.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

# ---- the frames of an open query ----
# `bd(X) :- n(X), X = p(_, _)`: bd/1's frame has arity 1 and three clause variables (two beyond its argument); n/1's clauses have none.
const _GF_CLAUSES = Tuple{_R, Union{Nothing, _R}}[
    (_rf("n", _rf("p", _rg(Int64(1)), _rg(2.25))), nothing),
    (_rf("n", _rf("p", _rg(Int64(2)), _rg(3.25))), nothing),
    (_rf("n", _rf("p", _rg(Int64(3)), _rg(4.25))), nothing),
    (
        _rf("bd", _rv(1)),
        _rconj(_rf("n", _rv(1)), _rf("=", _rv(1), _rf("p", _rv(2), _rv(3))))
    )
]

"Run `bd(V)` and call `f(db)` at the first answer (the query open): `(ld, answers, f's result)`."
function _gf_live(f)
    db = _rdb(copy(_GF_CLAUSES))
    res = Ref{Any}(nothing)
    ans = _rcall(
        db, _rf("bd", _rv(90)); at=(qid, k) -> (k == 1 && (res[] = f(db)); nothing)
    )
    return db.ld, ans, res[]
end

"The frame of the innermost clause choicepoint (n/1's frame)."
function _gf_clause_frame(ld)::Int
    cl = 0
    ch = ld.BFR
    while ch != 0
        c = ld.choices[ch]
        (c.type == LK.CHP_CLAUSE && cl == 0) && (cl = ch)
        ch = c.parent
    end
    cl == 0 && error("_gf_clause_frame: no clause choicepoint")
    return ld.choices[cl].frame
end

"The start index of every instruction of clause `cl` (the clause's own `stepPC`)."
function _gf_starts(cl)::Vector{Int}
    out = Int[]
    pc = LK.Code(cl, 1)
    while pc.pc <= length(cl.codes)
        push!(out, pc.pc)
        pc = LK.stepPC(pc)
    end
    return out
end

"""
One `clearLocalVariablesFrame(ld, fr)` on a frame whose cells hold distinct sentinels: `(result, before, after, nvars, arity)`, the cells being
the frame's arguments, its clause variables and ONE cell above them (index `j`: slot `argFrameP(base, j)`, `j = 0 .. max(nvars, arity)`); the cells are put back.
"""
function _gf_trial!(ld, fr::Int)
    f = ld.frames[fr]
    nv = f.clause === nothing ? 0 : Int((f.clause::LK.ClauseRef{_R}).clause.prolog_vars)
    ar = (f.predicate::LK.Definition{_R}).arity
    span = max(nv, ar)
    lo = LK.argFrameP(f.base, 0) + 1
    w = lo:(lo + span)
    saved = copy(ld.slots[w])
    try
        for (k, i) in enumerate(w)
            ld.slots[i] = LK.consInt(1000 + k)
        end
        before = copy(ld.slots[w])
        r = LK.clearLocalVariablesFrame(ld, fr)
        return r, before, copy(ld.slots[w]), nv, ar
    finally
        ld.slots[w] = saved
    end
end

"The checks of the frame helpers on an open query: a vector of `(name, ok)`; everything touched is put back."
function _gf_rows(db)
    ld = db.ld
    q = ld.queries[ld.query]
    nfr = _gf_clause_frame(ld)
    bfr = ld.frames[nfr].parent
    bdef = _rproc(db, _rf("bd", _rv(1))).definition
    fdef = _rproc(db, _rf("atom_length", _rv(1), _rv(2))).definition
    ph = ld.placeholder
    rows = Tuple{String, Bool}[]
    chk!(name, ok) = push!(rows, (name, ok === true))
    saved = (q.registers_fr, q.registers_argp, q.registers_pc, q.next_environment, q.aSave)
    ltop0 = ld.lTop
    bclause = ld.frames[bfr].clause
    bpred = ld.frames[bfr].predicate
    try
        chk!(
            "premise: bd's frame has a clause, arity 1 and two variables beyond its argument",
            bclause !== nothing && ld.frames[bfr].predicate === bdef && bdef.arity == 1 &&
                Int((bclause::LK.ClauseRef{_R}).clause.prolog_vars) == 3)

        # (a) clearLocalVariablesFrame on the frame of a clause with variables: pl-gc.c:1427-1437
        r, before, after, nv, ar = _gf_trial!(ld, bfr)
        chk!("clear: returns nothing", r === nothing)
        chk!(
            "clear: the frame has non-argument slots to clear (premise)",
            nv > ar && ar == 1 && nv - ar == 2
        )
        chk!(
            "clear: the arguments are untouched (`i` starts at the arity)",
            after[1:ar] == before[1:ar]
        )
        chk!("clear: every slot from the arity to prolog_vars - 1 is the word 0",
            all(==(0), after[(ar + 1):nv]) && length(after[(ar + 1):nv]) == 2)
        chk!(
            "clear: the cell above prolog_vars is untouched (`i<slots` stops)",
            after[nv + 1] == before[nv + 1]
        )
        chk!(
            "clear: the sentinels were not zero before (the zeros are written)",
            all(!=(0), before)
        )
        chk!("clear: lTop is untouched", ld.lTop == ltop0)

        # (b) the arms that write nothing
        ld.frames[bfr].clause = nothing                  # `fr->clause` is NULL
        r1, b1, a1, _, _ = _gf_trial!(ld, bfr)
        ld.frames[bfr].clause = bclause
        chk!("no clause: nothing is written", r1 === nothing && a1 == b1 && !isempty(b1))
        ld.frames[bfr].predicate = fdef                  # P_FOREIGN: atom_length/2 (arity 2 < the clause's 3 variables, so a write would show)
        r2, b2, a2, _, _ = _gf_trial!(ld, bfr)
        ld.frames[bfr].predicate = bpred
        chk!(
            "a foreign predicate: nothing is written",
            r2 === nothing && a2 == b2 && !isempty(b2)
        )
        chk!(
            "premise: atom_length/2 is foreign",
            (fdef.flags & LK.P_FOREIGN) != 0 && (bdef.flags & LK.P_FOREIGN) == 0
        )
        r3, b3, a3, nv3, ar3 = _gf_trial!(ld, nfr)       # n/1: arity 1, no variable beyond the argument
        chk!("a clause with no variable beyond the arguments: nothing is written",
            r3 === nothing && nv3 <= ar3 && a3 == b3 && !isempty(b3))

        # (c) twice: the second clearing finds the zeros and writes the same
        f = ld.frames[bfr]
        lo = LK.argFrameP(f.base, 0) + 1
        saved_w = copy(ld.slots[lo:(lo + 3)])
        try
            for k in 1:4
                ld.slots[lo + k - 1] = LK.consInt(500 + k)
            end
            LK.clearLocalVariablesFrame(ld, bfr)
            once = copy(ld.slots[lo:(lo + 3)])
            LK.clearLocalVariablesFrame(ld, bfr)
            chk!(
                "clear twice: the same cells",
                copy(ld.slots[lo:(lo + 3)]) == once && once[2] == 0 && once[3] == 0 &&
                    once[1] != 0
            )
        finally
            ld.slots[lo:(lo + 3)] = saved_w
        end

        # (d) setLTopInBody in the body of bd/1 (just inside the first I_CALL), as the provider's `lTop` raise
        bcl = (bclause::LK.ClauseRef{_R}).clause
        starts = _gf_starts(bcl)
        ie = findfirst(s -> bcl.codes[s] == LK.I_ENTER, starts)
        ic = findfirst(s -> bcl.codes[s] == LK.I_CALL, starts)
        chk!(
            "premise: bd's code has I_ENTER before I_CALL",
            ie !== nothing && ic !== nothing && ie < ic
        )
        pc = starts[ic] + 1
        q.registers_fr = bfr
        q.registers_pc = LK.Code(bcl, pc)
        q.next_environment = 0
        lt = ld.lTop
        newbase = LK.argFrameP(lt, 0)
        slot(p) = LK.argp_t{_R}(LK.ARGP_SLOT, p, ph)
        q.registers_argp = slot(newbase + 2)
        rb = LK.setLTopInBody(ld)
        chk!("setLTopInBody: returns nothing, lTop is raised to the argument pointer",
            rb === nothing && ld.lTop == newbase + 2 && lt < ld.lTop)
        LK.setLTopInBody(ld)
        chk!("setLTopInBody: twice, the same lTop", ld.lTop == newbase + 2)
        q.registers_argp = slot(newbase + 3)
        LK.setLTopInBody(ld)
        chk!(
            "setLTopInBody: a higher argument pointer raises it further",
            ld.lTop == newbase + 3
        )
        q.registers_argp = slot(newbase + 1)
        LK.setLTopInBody(ld)
        chk!(
            "setLTopInBody: a lower one never lowers it (restore_vmi_state is not called)",
            ld.lTop == newbase + 3
        )
        LK.lowerLTop!(ld, lt)
        chk!("premise: lTop is back for the next row", ld.lTop == lt)
        # the contrast: the provider and its restore put lTop back; setLTopInBody does not
        q.registers_argp = slot(newbase + 2)
        vm = LK.gc_get_vmi_state(ld, ld.query, LK.gc_vmi_state_of)::LK.vm_state
        raised = ld.lTop
        LK.gc_restore_vmi_state(ld, vm)
        chk!(
            "the provider raises lTop as setLTopInBody does and its restore lowers it again",
            raised == newbase + 2 && ld.lTop == lt)
        q.registers_argp = slot(newbase)
        LK.setLTopInBody(ld)
        chk!(
            "setLTopInBody: at the next frame's first argument nothing is raised",
            ld.lTop == lt
        )
        q.registers_argp = slot(newbase + 2)
        q.registers_pc = LK.Code(bcl, 2)                  # a pc in the head: not in the body
        LK.setLTopInBody(ld)
        chk!("setLTopInBody: in a head lTop is unchanged", ld.lTop == lt)
        q.registers_pc = LK.Code(bcl, pc)
        q.registers_fr = 0                                # the query holds no frame: the other arm of get_vmi_state
        LK.setLTopInBody(ld)
        chk!("setLTopInBody: a query outside the VM leaves lTop", ld.lTop == lt)
        q.registers_fr = bfr
    finally
        ld.frames[bfr].clause = bclause
        ld.frames[bfr].predicate = bpred
        q.registers_fr, q.registers_argp, q.registers_pc, q.next_environment, q.aSave =
            saved
        ld.lTop > ltop0 && LK.lowerLTop!(ld, ltop0)
    end
    return rows
end

@testset "clearLocalVariablesFrame and setLTopInBody on the frames of an open query" begin
    _, base, _ = _gf_live(db -> nothing)
    @test length(base) == 3 && all(a -> !isempty(a[1]), base)
    ld, ans, rows = _gf_live(_gf_rows)
    @test rows !== nothing && length(rows) >= 20
    for (nm, ok) in rows
        @testset "frames: $nm" begin
            @test ok
        end
    end
    @test ans == base                                       # the query was not disturbed by the helpers
end

@testset "setLTopInBody with no query is a no-op" begin
    db = _rdb(copy(_GF_CLAUSES))
    ld = db.ld
    @test ld.query == 0
    lt = ld.lTop
    @test LK.setLTopInBody(ld) === nothing
    @test ld.lTop == lt
end

@testset "trim_stack_requested: an overflow sets it, trimStacks! clears it, the driver reads it" begin
    db = _rdb(copy(_GF_CLAUSES))
    ld = db.ld
    @test !ld.trim_stack_requested
    LK.PL_open_foreign_frame(ld)
    # set by the overflow exception (pl-alloc.c:695), cleared by resumeAfterException -> trimStacks (pl-setup.c:1715)
    @test LK.outOfStack!(ld, LK.STACK_OVERFLOW_RAISE) === false
    @test ld.trim_stack_requested && ld.outofstack
    LK.resumeAfterException(ld, true, true)
    @test !ld.trim_stack_requested && !ld.outofstack
    LK.trimStacks!(ld, false)
    @test !ld.trim_stack_requested
    ld.trim_stack_requested = true
    LK.trimStacks!(ld, false)
    @test !ld.trim_stack_requested                           # trimStacks clears it whatever its argument
    # read by the driver (pl-gc.c:4549 `trimStacks(LD->trim_stack_requested)`): a set flag shrinks the grown local stack, a clear one leaves it
    lsize(ld) = ld.lMax + ld.local_spare
    LK.growStacks!(ld, 200_000)
    big = lsize(ld)
    @test big > 200_000
    ld.trim_stack_requested = false
    @test LK.garbageCollect(ld, Int(LK.GC_USER); vmi_state_of=LK.gc_vmi_state_of) ==
        LK.BOOLEX_TRUE
    @test lsize(ld) == big                                     # the flag is clear: the stack keeps its size
    ld.trim_stack_requested = true
    @test LK.garbageCollect(ld, Int(LK.GC_USER); vmi_state_of=LK.gc_vmi_state_of) ==
        LK.BOOLEX_TRUE
    @test lsize(ld) < big                                      # the flag is set: trimStacks(true) shrinks it
    @test !ld.trim_stack_requested                            # and clears it
end

# ---- the upstream rows: tests/GC/test_ch_shift.pl and tests/GC/test_cleanup_shift.pl (swipl-devel 18168e62) ----
# ORIGINAL: One row `t_<id>(R)` per upstream test, R = ok / failed / raised(E). The unit text is upstream's, verbatim, between `begin_tests` and `end_tests`, plus
# the file's own code after `end_tests` (cleanup_shift: t_true/1.., gshift/tshift/lshift) as the module's tail; each unit is its own module `pu_<unit>` (plunit
# gives each unit one) with `:- discontiguous test/1, test/2.` (plunit's term expansion makes the clauses of test/N its own). The licence blocks are not embedded.
#   * DIVERGES from the files: plunit is not used (`pu_<unit>:test(Name)` is called directly): the `true` / `fail` options of cleanup_shift's tests are folded by
#     hand: `test(N, true)` is `(pu:test(N, O), O == true)`, `test(N, fail)` is `\+ pu:test(N, _)`; ch_shift's tests have no option.
#   * D-0164 word scan of the embedded text (swipl-devel 18168e62, case-insensitive, non-comment lines and comments): no hit, so no unit is excluded and no
#     comment is elided; checked by evidence/G1/g1a_gen.py.
#   * Pins: swipl 10.1.20 (the pinned build), two identical runs of the driver below; the plunit runs of the two files at the pin pass 2/2 and 12/12 (every
#     `_UP_UPSTREAM` entry is `ok`). A row's pin is `ok` for every test: they pass or, for the fail-option tests, fail as expected.
#   * UNVERIFIED on the kernel (nothing was compiled when these rows were written): every kernel answer. `local_stack_expansion_many_chp` compiles a clause whose
#     body is a 10000-deep disjunction (the file's `or_dept`); it has its own testset (DEPTH STRESS): if the kernel's compiler cannot take that depth, only that one fails.

const _UP_TT = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})
_up_tts(x) = lk_sym(_UP_TT, Symbol(x))

_up_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
"A term as the driver's `enc/1` writes it: `V<i>` by first occurrence, atoms and functors by their codes."
function _up_enc(t::_UP_TT, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _up_codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _up_codes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _up_codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([_up_enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _UP_DRIVER = raw"""
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

"The units' text, verbatim between begin_tests and end_tests, and the file's code after end_tests: `(short name, text, tail)`."
const _UP_UNITS = [
    ("ch_shift", raw"""

% Compiling the clause generated by make_or/2 involves deep C-stack
% recursion.  Limit the stack on some platforms.
or_dept(Depth), current_prolog_flag(asan,true) => Depth = 1000.
or_dept(Depth), current_prolog_flag(emscripten,true) => Depth = 1000.
or_dept(Depth), current_prolog_flag(windows,true),
                current_prolog_flag(build_type,'Debug') => Depth = 1000.
or_dept(Depth), current_prolog_flag(windows,true) => Depth = 5000.
or_dept(Depth) => Depth = 10_000.

%       Tests expansion of the local stack due to a clause with many
%       choicepoints.

test(local_stack_expansion_many_chp) :-
    or_dept(Depth),
    trim_stacks,
    make_or(Depth, OR),
    asserta((t :- OR), Ref),
    once(t),
    erase(Ref).

make_or(0, a) :- !.
make_or(N, (G;a)) :-
    N2 is N - 1,
    make_or(N2, G).

a.

%       Tests local stack shifting when there are pending choicepoint frames.

test(local_stack_expansion_pending_chp) :-
    test2_1,
    !.

test2_1 :-
    test2_2, true.

test2_2 :-
    setup_call_cleanup(true, cp, lshift).

cp.
cp.

lshift :-
    statistics(local_shifts, S0),
    lshift(S0), !, garbage_collect.

lshift(S0) :-
    statistics(local_shifts, S0),
    lshift(S0).
lshift(_).

""", raw""""""),
    ("cleanup_shift", raw"""

test(gtrue, true) :- t_true(gshift).
test(ltrue, true) :- t_true(lshift).
test(ttrue, true) :- t_true(tshift).

test(gfalse, fail) :- t_false(gshift).
test(lfalse, fail) :- t_false(lshift).
test(tfalse, fail) :- t_false(tshift).

test(gcut, true) :- t_cut(gshift).
test(lcut, true) :- t_cut(lshift).
test(tcut, true) :- t_cut(tshift).

test(gexcept, true) :- t_except(gshift).
test(lexcept, true) :- t_except(lshift).
test(texcept, true) :- t_except(tshift).

""", raw"""t_true(Cleanup) :-
	garbage_collect,
	trim_stacks,
	setup_call_cleanup(true, true, Cleanup).
t_false(Cleanup) :-
	garbage_collect,
	trim_stacks,
	setup_call_cleanup(true, fail, Cleanup).
t_cut(Cleanup) :-
	garbage_collect,
	trim_stacks,
	setup_call_cleanup(true, (true;true), Cleanup), !.
t_except(Cleanup) :-
	garbage_collect,
	trim_stacks,
	catch(setup_call_cleanup(true, succ(_, -1), Cleanup), E, true),
	(   subsumes_term(error(domain_error(not_less_than_zero, -1), _), E)
	->  true
	;   format(user_error, 'Wrong error: ~p', [E]),
	    fail
	).

%%	gshift.
%%	tshift.
%%	lshift.
%
%	Force a stack-shift of the global, trail or local stack.

gshift :- shift_stack(global_shifts).
tshift :- shift_stack(trail_shifts).

shift_stack(Stat) :-
	statistics(Stat, S0),
	shift_stack(S0, Stat, X),
	nonvar(X).

shift_stack(S0, Stat, s(X)) :-
	statistics(Stat, S0), !,
	shift_stack(S0, Stat, X).
shift_stack(_, _, _).

lshift :-
	statistics(local_shifts, S0),
	lshift(S0), !.

lshift(S0) :-
	statistics(local_shifts, S0),
	lshift(S0).
lshift(_).""")
]

"The rows: `(id, goal)`; the goal is the plunit test with its options folded by hand."
const _UP_CASES = [
    ("gc01", raw"pu_ch_shift:test(local_stack_expansion_many_chp)"),
    ("gc02", raw"pu_ch_shift:test(local_stack_expansion_pending_chp)"),
    ("gc03", raw"(pu_cleanup_shift:test(gtrue, O), O == true)"),
    ("gc04", raw"(pu_cleanup_shift:test(ltrue, O), O == true)"),
    ("gc05", raw"(pu_cleanup_shift:test(ttrue, O), O == true)"),
    ("gc06", raw"\+ pu_cleanup_shift:test(gfalse, _)"),
    ("gc07", raw"\+ pu_cleanup_shift:test(lfalse, _)"),
    ("gc08", raw"\+ pu_cleanup_shift:test(tfalse, _)"),
    ("gc09", raw"(pu_cleanup_shift:test(gcut, O), O == true)"),
    ("gc10", raw"(pu_cleanup_shift:test(lcut, O), O == true)"),
    ("gc11", raw"(pu_cleanup_shift:test(tcut, O), O == true)"),
    ("gc12", raw"(pu_cleanup_shift:test(gexcept, O), O == true)"),
    ("gc13", raw"(pu_cleanup_shift:test(lexcept, O), O == true)"),
    ("gc14", raw"(pu_cleanup_shift:test(texcept, O), O == true)")
]

const _UP_PINNED = [
    "ok",
    "t_gc01 c[116,95,103,99,48,49]/1(a[111,107])",
    "t_gc02 c[116,95,103,99,48,50]/1(a[111,107])",
    "t_gc03 c[116,95,103,99,48,51]/1(a[111,107])",
    "t_gc04 c[116,95,103,99,48,52]/1(a[111,107])",
    "t_gc05 c[116,95,103,99,48,53]/1(a[111,107])",
    "t_gc06 c[116,95,103,99,48,54]/1(a[111,107])",
    "t_gc07 c[116,95,103,99,48,55]/1(a[111,107])",
    "t_gc08 c[116,95,103,99,48,56]/1(a[111,107])",
    "t_gc09 c[116,95,103,99,48,57]/1(a[111,107])",
    "t_gc10 c[116,95,103,99,49,48]/1(a[111,107])",
    "t_gc11 c[116,95,103,99,49,49]/1(a[111,107])",
    "t_gc12 c[116,95,103,99,49,50]/1(a[111,107])",
    "t_gc13 c[116,95,103,99,49,51]/1(a[111,107])",
    "t_gc14 c[116,95,103,99,49,52]/1(a[111,107])"
]

"The answer plunit expects of every row: the test passes (the fail-option tests fail as the file expects), so `R = ok`."
const _UP_UPSTREAM = [
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]",
    "a[111,107]"
]

"The files of the program in a fresh directory: one module file per unit, the main file with the rows; returns the main file."
function _up_materialize()::String
    d = realpath(mktempdir())
    for (short, text, tail) in _UP_UNITS
        write(
            joinpath(d, "pu_$short.pl"),
            ":- module(pu_$short, []).\n:- discontiguous test/1, test/2.\n" * text * "\n" *
            tail * "\n"
        )
    end
    main = join([":- use_module('$d/pu_$short').\n" for (short, _, _) in _UP_UNITS])
    main *= join([
        "t_$(id)(R) :- ( catch(($g, R = ok), error(E, _), R = raised(E)) -> true ; R = failed ).\n"
        for (id, g) in _UP_CASES
    ])
    write(joinpath(d, "main.pl"), main)
    return joinpath(d, "main.pl")
end

function _up_swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            _UP_DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end

"A kernel with the program consulted: `(gd, ld, first line of the driver's output)`."
function _up_load(main::String)
    gd = LK.PL_global_data{_UP_TT}()
    ld = LK.PL_local_data{_UP_TT}(gd)
    st, ball = LK.load_file!(gd, ld, main)
    return gd, ld, (st === :ok ? "ok" : "exc " * _up_enc(ball::_UP_TT))
end

"The driver's line for `pred/1` (every answer, at most 50)."
function _up_ask(gd, ld, pred::String)::String
    proc = LK.isCurrentProcedure(sym_key(_up_tts(pred)), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$pred undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(_UP_TT, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 50
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(
                sols,
                _up_enc(
                    mk_expr(_UP_TT, _UP_TT[_up_tts(pred), lk_answers(ld, (a:a)...)...])
                )
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
    return pred * join(" " .* sols)
end

"The part of a driver line after `t_<id> c[...]/1(`: the answer, as `_UP_UPSTREAM` holds it."
function _up_answer(line::String)::String
    k = findfirst("/1(", line)::UnitRange{Int}
    return line[(last(k) + 1):(end - 1)]
end

"A line the same length that must differ from `s` (the must-fail corruption)."
_up_corrupt(s::String) = s[1:(end - 2)] * (s[end - 1] == '0' ? "1" : "0") * s[end]

# DEPTH STRESS: the row gc01 compiles and runs a clause whose body is a 10000-deep disjunction (upstream's own depth); kept apart so a failure of the
# kernel's compiler at that depth shows as this testset alone and does not hide the 13 other rows.
@testset "DEPTH STRESS: upstream local_stack_expansion_many_chp (10000-deep disjunction)" begin
    gd, ld, st = _up_load(_up_materialize())
    @test st == "ok"
    id = _UP_CASES[1][1]
    @test id == "gc01"
    k = _up_ask(gd, ld, "t_$id")
    k == _UP_PINNED[2] || println(stderr, "  ours  ", k, "\n  swipl ", _UP_PINNED[2])
    @test k == _UP_PINNED[2]
    # must-fail: a corrupted pin is not the kernel's line
    @test k != _up_corrupt(_UP_PINNED[2])
end

@testset "upstream test_ch_shift.pl and test_cleanup_shift.pl: the kernel answers every other row as swipl does" begin
    gd, ld, st = _up_load(_up_materialize())
    @test st == "ok"
    kl = String[]
    for (id, _) in _UP_CASES[2:end]
        push!(kl, _up_ask(gd, ld, "t_$id"))
    end
    @test length(kl) == length(_UP_PINNED) - 2
    for (k, pn) in zip(kl, _UP_PINNED[3:end])
        k == pn || println(stderr, "  ours  ", k, "\n  swipl ", pn)
        @test k == pn
    end
    # must-fail: a corrupted pin is not the kernel's line
    @test length(kl) > 1
    @test kl[1] != _up_corrupt(_UP_PINNED[3])
end

@testset "the pins are the upstream (plunit) expectations (no swipl needed)" begin
    @test length(_UP_PINNED) == length(_UP_CASES) + 1
    @test length(_UP_UPSTREAM) == length(_UP_CASES) == 14
    @test !isempty(_UP_UPSTREAM) && all(!isempty, _UP_UPSTREAM)
    @test _UP_PINNED[1] == "ok"
    for (pn, up) in zip(_UP_PINNED[2:end], _UP_UPSTREAM)
        @test _up_answer(pn) == up
    end
    # must-fail: the corruption of a pin is not the upstream expectation
    @test _up_answer(_up_corrupt(_UP_PINNED[2])) != _UP_UPSTREAM[1]
end

@testset "the pins are swipl's (live, when swipl is on PATH)" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "LIVE CHECK NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
    else
        got = _up_swipl_lines(_up_materialize(), ["t_$id" for (id, _) in _UP_CASES])
        @test !isempty(got) && got == _UP_PINNED
        # must-fail: a corrupted pin is not swipl's line
        @test got[2] != _up_corrupt(_UP_PINNED[2])
    end
end
