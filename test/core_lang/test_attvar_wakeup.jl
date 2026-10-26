# ORIGINAL: AV3 — binding an attributed variable and waking its hooks (design §5 row AV3; audit D-0122, D-0150).
# Upstream tests attributed variables in Prolog (src/Tests/attvar/*.pl), which need freeze/2 (AV7) and the full
# wakeup (AV4); the rows of this file are the hook-order rows of evidence/av/rows.tsv, under the hooks fixture.
# test/core_lang/test_attvar_wakeup.jl — on every term type:
#   * WHITE-BOX: `assignAttVar` binds an attributed variable and `registerWakeup` puts `wakeup(Att, Value, [])`
#     on the wakeup list — the first onto the empty list (head, tail, `ALERT_WAKEUP`), the next appended through
#     the old closing cell — each with its trail entries (address entry, value entry, pairwise: head, tail,
#     the attvar) and undone by `Undo!`; two attributed variables: the NEWER is bound to the older (risk 4); the
#     same one: nothing; `bind_attvar_const` and `bindConst`; `updateAlerted`'s wakeup bit; `saveWakeup` /
#     `restoreWakeup` set the list aside and put it back (with a pending exception too: the slot after it);
#     `can_unify` (`\=/2`'s full check) and `findCatcher` run a wakeup pending after their unification
#     (`foreignWakeup`, AV4: test_attvar_wakeup.jl (the AV4 rows at its end)) — until AV4 a NotPortedError naming AV4;
#   * THE ROWS hk01-hk04, hk06-hk09, hk12, hk15-hk19b, hk21 of evidence/av/rows.tsv (swipl 10.1.18; re-probed
#     with 10.1.19, the local swipl) and the VM-site rows — one per place the run loop wakes a hook (B_UNIFY_VC,
#     B_UNIFY_VV, B_UNIFY_EXIT, I_ENTER, a fact's and a foreign predicate's exit) — whose goal is followed by a
#     FOREIGN call (assertz/1) so that a hook run late shows in the log's order; the NON-WAKING rows (D-0122
#     condition 4: `==`, `?=`, unifiable/3, compare/3, `=@=`, `\==` never wake, and unifiable/3's and `?=`'s
#     undone unification leaves no wakeup behind); the occurs-check rows (the trail walk skips an attvar
#     assignment's wakeup entries); hooks that fail, throw, are undone on backtracking;
#   * B_UNIFY_VC's second path (AV3-W4): a small integer without a word, on a payload without `Int64`;
#   * hk14 (a hook module inheriting from `user`, made by MOD1's `lookupModule`) and two rows beside it, live;
#     hk14s / hk14t (two attributed variables, both modules `user`) answer for its hooks' order.
# NOT AV3 ROWS: hk05, hk05b, hk22, hk23 (a module that inherits from `user`: R2; freeze/2: AV7); hk10, hk11, hk13
# (`\=`, catch/3's catcher: foreignWakeup, AV4 — their rows here, more in test_attvar_wakeup.jl (the AV4 rows at its end)); hk20 (numbervars/4's
# `attvar(bind)`: pl-prims.jl numberVars reads no attributed variable — AV5).
# Every expected answer is swipl's: the tables were produced by running the programs under swipl 10.1.19 (the
# local one) with the driver below, and the rows re-run LIVE when swipl is on PATH. Mutation-tested by
# tools/mutants/AV3.py.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

"A fresh engine (`_rdb`'s) with a foreign frame open."
function _wk_engine()
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    LK.PL_open_foreign_frame(db.ld)
    return db.ld, db
end

"The atom word of `s` in the engine's table."
_wk_atom(ld, s::String) = LK._atom_word!(ld, _rs(s))

"A small integer as a dereferenced location's value `(DU_VALUE, word, 0)` (a slot's tagged integer)."
_wk_int(n::Int) = (LK.DU_VALUE, LK.consInt(Int64(n)), 0)

"""
A new term reference whose cell `put_new_attvar` makes attributed with `name` = `n`: `(t, av)` — the term
reference and the new attvar cell (the link cell is `av - 1`).
"""
function _wk_attvar!(ld, name::String="a", n::Int=1)
    t = LK.PL_new_term_ref(ld)
    x = LK.unRef(ld.slots[t + 1])
    g0 = ld.gTop
    LK.put_new_attvar(ld, x, _wk_atom(ld, name), _wk_int(n))
    return t, g0 + 2
end

"The attvar `av` as a dereferenced location."
_wk_loc(ld, av::Int) = (LK.DU_ATTVAR, ld.gstack[av], av)

"The trail entries pushed since `n0`: their cells (address entries 1, 3, 5, …) and whether 2, 4, 6, … are value entries."
function _wk_trail_since(ld, n0::Int)
    es = ld.trail[(n0 + 1):end]
    cells = [LK._trail_pos(es[i]) for i in 1:2:length(es)]
    vals = all(i -> LK.isTrailVal(es[i]), 2:2:length(es))
    return cells, vals
end

@testset "assignAttVar: attvar = constant — the cell assigned, wakeup(Att, Value, []) on the empty list, ALERT_WAKEUP, 6 trail entries" begin
    ld, _ = _wk_engine()
    _, av = _wk_attvar!(ld)
    h = LK._attvar_head_cell(ld)
    @test ld.gstack[h] == 0 && ld.gstack[h + 1] == 0 && ld.alerted == 0      # the empty list
    five = LK.consInt(Int64(5))
    m = LK.Mark(ld)                                         # the attvar and the list lie below the mark: trailed
    n0 = length(ld.trail)
    LK.assignAttVar(ld, av, _wk_int(5))
    @test ld.gstack[av] == five                             # *av = *value
    wake = LK.valPtr(ld.gstack[h])
    @test ld.gstack[h] == LK.consPtr(wake, LK.TAG_COMPOUND | LK.STG_GLOBAL)   # *head = consPtr(wake, …)
    @test ld.gstack[wake] == LK._functor_wakeup3(ld)
    @test ld.gstack[wake + 1] == ld.gstack[av + 1]          # *name: the attribute list att(a, 1, []) (a compound pointer, no reference)
    @test ld.gstack[wake + 2] == five                       # the value
    @test ld.gstack[wake + 3] == ld.atom_nil_w              # the closing []
    @test ld.gstack[h + 1] == LK.makeRefG(wake + 3)         # *tail = makeRefG(wake+3)
    @test (ld.alerted & LK.ALERT_WAKEUP) != 0
    cells, vals = _wk_trail_since(ld, n0)
    @test cells == [h, h + 1, av] && vals                    # head, tail, the attvar; each an address + a value entry
    @test length(ld.trail) - n0 == 6
    LK.Undo!(ld, m)
    @test ld.gstack[av] == LK.consPtr(av + 1, LK.TAG_ATTVAR | LK.STG_GLOBAL)   # the attvar again
    @test ld.gstack[h] == 0 && ld.gstack[h + 1] == 0        # the list empty again
    LK.updateAlerted(ld)
    @test ld.alerted == 0
end

@testset "registerWakeup: the next wakeup is APPENDED through the old closing cell; the bit is set by the empty branch only" begin
    ld, _ = _wk_engine()
    _, av1 = _wk_attvar!(ld, "a", 1)
    _, av2 = _wk_attvar!(ld, "b", 2)
    h = LK._attvar_head_cell(ld)
    a = _wk_atom(ld, "x")
    LK.assignAttVar(ld, av1, _wk_int(5))
    w1 = LK.valPtr(ld.gstack[h])
    m2 = LK.Mark(ld)                                        # the first wakeup's cells lie below this mark now
    n1 = length(ld.trail)
    ld.alerted = Int32(0)                                   # the second registration must NOT set it again
    LK.assignAttVar(ld, av2, (LK.DU_WORD, a, 0))
    @test ld.alerted == 0                                   # `LD->alerted |= ALERT_WAKEUP` is the empty branch's
    w2 = LK.valPtr(ld.gstack[w1 + 3])
    @test ld.gstack[w1 + 3] == LK.consPtr(w2, LK.TAG_COMPOUND | LK.STG_GLOBAL)   # *t = consPtr(wake, …)
    @test ld.gstack[h] == LK.consPtr(w1, LK.TAG_COMPOUND | LK.STG_GLOBAL)         # the head is the first one
    @test ld.gstack[h + 1] == LK.makeRefG(w2 + 3)           # *tail = makeRefG(wake+3)
    @test ld.gstack[w2] == LK._functor_wakeup3(ld) && ld.gstack[w2 + 2] == a
    @test ld.gstack[w2 + 1] == ld.gstack[av2 + 1] && ld.gstack[w2 + 3] == ld.atom_nil_w
    cells, vals = _wk_trail_since(ld, n1)
    @test cells == [w1 + 3, h + 1, av2] && vals             # the old closing cell, the tail, the attvar
    LK.Undo!(ld, m2)
    @test ld.gstack[w1 + 3] == ld.atom_nil_w && ld.gstack[h + 1] == LK.makeRefG(w1 + 3)
    @test ld.gstack[av2] == LK.consPtr(av2 + 1, LK.TAG_ATTVAR | LK.STG_GLOBAL)
    @test ld.gstack[h] == LK.consPtr(w1, LK.TAG_COMPOUND | LK.STG_GLOBAL)         # the first wakeup stays
end

@testset "assignAttVar: two attributed variables — the NEWER is bound to the older (risk 4); the same one: nothing" begin
    for swap in (false, true)
        ld, _ = _wk_engine()
        _, a1 = _wk_attvar!(ld, "a", 1)
        _, a2 = _wk_attvar!(ld, "b", 2)
        h = LK._attvar_head_cell(ld)
        m = LK.Mark(ld)
        if swap
            LK.assignAttVar(ld, a2, _wk_loc(ld, a1))
        else
            LK.assignAttVar(ld, a1, _wk_loc(ld, a2))
        end
        @test ld.gstack[a2] == LK.makeRefG(a1)              # the newer, a reference to the older
        @test ld.gstack[a1] == LK.consPtr(a1 + 1, LK.TAG_ATTVAR | LK.STG_GLOBAL)   # the older untouched
        wake = LK.valPtr(ld.gstack[h])
        @test ld.gstack[wake + 1] == ld.gstack[a2 + 1]      # the bound variable's attributes: its hook runs
        @test ld.gstack[wake + 2] == LK.makeRefG(a1)        # the value: a reference to the older attvar
        LK.Undo!(ld, m)
        @test ld.gstack[a2] == LK.consPtr(a2 + 1, LK.TAG_ATTVAR | LK.STG_GLOBAL) &&
            ld.gstack[h] == 0
    end
    ld, _ = _wk_engine()
    _, a1 = _wk_attvar!(ld)
    n0 = length(ld.trail)
    LK.assignAttVar(ld, a1, _wk_loc(ld, a1))                # av == value: return
    @test ld.gstack[LK._attvar_head_cell(ld)] == 0 && length(ld.trail) == n0 &&
        ld.alerted == 0
end

@testset "bind_attvar_const, bindConst: an attributed variable is assigned with a wakeup; an unbound cell is not" begin
    ld, _ = _wk_engine()
    t, av = _wk_attvar!(ld)
    h = LK._attvar_head_cell(ld)
    a = _wk_atom(ld, "k")
    @test LK.bind_attvar_const(ld, av, a) === true
    @test ld.gstack[av] == a
    wake = LK.valPtr(ld.gstack[h])
    @test ld.gstack[wake + 2] == a && (ld.alerted & LK.ALERT_WAKEUP) != 0
    # bindConst takes the same road for an attributed variable (the cell `isVar` is false)
    ld, _ = _wk_engine()
    _, av = _wk_attvar!(ld)
    LK.bindConst(ld, av, a)
    @test ld.gstack[av] == a && ld.gstack[LK._attvar_head_cell(ld)] != 0
    # … and an unbound cell is varBindConst: no wakeup, no bit
    ld, _ = _wk_engine()
    x = LK.unRef(ld.slots[LK.PL_new_term_ref(ld) + 1])
    LK.bindConst(ld, x, a)
    @test ld.gstack[x] == a && ld.gstack[LK._attvar_head_cell(ld)] == 0 && ld.alerted == 0
end

@testset "updateAlerted: ALERT_WAKEUP while the list is not empty, and nothing else" begin
    ld, _ = _wk_engine()
    h = LK._attvar_head_cell(ld)
    LK.updateAlerted(ld)
    @test ld.alerted == 0
    ld.alerted = LK.ALERT_WAKEUP                            # a stale bit with an empty list: cleared
    LK.updateAlerted(ld)
    @test ld.alerted == 0
    _, av = _wk_attvar!(ld)
    LK.assignAttVar(ld, av, _wk_int(1))
    ld.alerted = Int32(0)                                   # a list without the bit: set
    LK.updateAlerted(ld)
    @test ld.alerted == LK.ALERT_WAKEUP
    LK.updateAlerted(ld)
    @test ld.alerted == LK.ALERT_WAKEUP                     # idempotent
    ld.gstack[h] = LK.word(0)
    LK.updateAlerted(ld)
    @test ld.alerted == 0
end

@testset "saveWakeup / restoreWakeup: the wakeup list set aside, cleared, and put back (with an exception: the slot after it)" begin
    # nothing pending, no forced frame: no frame; forced: a frame, no flags
    ld, _ = _wk_engine()
    st = LK.saveWakeup(ld, false)
    @test st !== nothing && st.fid == 0 && st.flags == 0
    st = LK.saveWakeup(ld, true)
    @test st !== nothing && st.fid != 0 && st.flags == 0
    LK.restoreWakeup(ld, st)
    # a pending wakeup
    ld, _ = _wk_engine()
    _, av = _wk_attvar!(ld)
    h = LK._attvar_head_cell(ld)
    LK.assignAttVar(ld, av, _wk_int(5))
    w1, w2 = ld.gstack[h], ld.gstack[h + 1]
    st = LK.saveWakeup(ld, false)
    @test st !== nothing && st.fid != 0 && st.flags == LK.WAKEUP_STATE_WAKEUP
    @test ld.gstack[h] == 0 && ld.gstack[h + 1] == 0        # setVar on both
    p = ld.fliframes[LK.fliFrameOfFid(ld, st.fid)].base + LK.SIZEOF_FLIFRAME
    @test ld.slots[p + 1] == w1 && ld.slots[p + 2] == w2    # the head's and the tail's words, in the frame
    LK.updateAlerted(ld)
    @test ld.alerted == 0                                   # nothing pending while it is aside
    LK.restoreWakeup(ld, st)
    @test ld.gstack[h] == w1 && ld.gstack[h + 1] == w2
    @test (ld.alerted & LK.ALERT_WAKEUP) != 0               # updateAlerted after the discard
    # a pending exception AND a pending wakeup
    ex = LK.PL_new_term_ref(ld)
    @test LK.PL_unify_atomic(ld, ex, _rs("boom"))
    @test !LK.PL_raise_exception(ld, ex)                    # false, as upstream (pl-fli.c: `return false`)
    st = LK.saveWakeup(ld, false)
    @test st.flags == (LK.WAKEUP_STATE_EXCEPTION | LK.WAKEUP_STATE_WAKEUP)
    @test ld.exception_term == 0 && ld.gstack[h] == 0
    LK.restoreWakeup(ld, st)
    @test ld.exception_term != 0                            # the ball is back …
    @test ld.gstack[h] == w1 && ld.gstack[h + 1] == w2      # … and the list, from the slots after it
    LK.PL_clear_exception(ld)
end

# D-0083 (AV4): until AV4 this asserted the refusal — `err isa LK.NotPortedError && err.step == "AV4"`
# (`&& occursin("foreignWakeup", err.what)`) for a wakeup pending here; it now runs (foreignWakeup), which
# needs a query — the pending case is the rows hk10/hk13 below and test_attvar_wakeup.jl (the AV4 rows at its end).
@testset "can_unify (\\=/2's full check): no wakeup pending — foreignWakeup returns true, no query (AV4)" begin
    # none pending: two plain variables unify, no refusal
    ld, _ = _wk_engine()
    u1, u2 = LK.PL_new_term_ref(ld), LK.PL_new_term_ref(ld)
    @test LK.can_unify_cells(ld, -(u1 + 1), -(u2 + 1), 0) === true
    # a stale bit with an empty list (unifiable/3 and ?=/2 leave one): no refusal
    ld.alerted |= LK.ALERT_WAKEUP
    v1, v2 = LK.PL_new_term_ref(ld), LK.PL_new_term_ref(ld)
    @test LK.can_unify_cells(ld, -(v1 + 1), -(v2 + 1), 0) === true
    # a list without the bit: no refusal either (upstream's foreignWakeup tests the bit first)
    ld, _ = _wk_engine()
    _, av = _wk_attvar!(ld)
    LK.assignAttVar(ld, av, _wk_int(5))
    ld.alerted = Int32(0)
    w1, w2 = LK.PL_new_term_ref(ld), LK.PL_new_term_ref(ld)
    @test LK.can_unify_cells(ld, -(w1 + 1), -(w2 + 1), 0) === true
end

# ── the differential harness: test_attvar_store.jl's (AV2), unchanged ───────────────────────────────────────
_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
function enc(t::T, seen::Vector{UInt64}=UInt64[])::String where {T}  # any term type (AV3-W4's too)
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _codes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _codes(String(v))
        v isa Integer && return "i$v"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _codes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

function kernel_lines(path::String, names::Vector{String})::Vector{String}
    gd = LK.PL_global_data{_R}()
    ld = LK.PL_local_data{_R}(gd)
    st, ball, _ = LK.load_file!(gd, ld, path)
    out = [st === :ok ? "ok" : "exc " * enc(ball::_R)]
    for name in names
        proc = LK.isCurrentProcedure(sym_key(_rs(name)), 1, LK.MODULE_user(gd))
        if proc === nothing || !LK.isDefinedProcedure(gd, proc)
            push!(out, "$name undefined")
            continue
        end
        sols = String[]
        fid = LK.PL_open_foreign_frame(ld)
        a = LK.PL_new_term_refs(ld, 1)
        LK.putSlotValue!(ld, a + 1, mk_var(_R, LK.fresh_var_keys!(1)), LK.PutVarMap())
        qid = LK.PL_open_query(
            gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
        )
        n = 0
        while (n += 1) <= 50
            rc = LK.PL_next_solution(gd, ld, qid)
            if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
                push!(sols, enc(mk_expr(_R, _R[_rs(name), lk_answers(ld, (a:a)...)...])))
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
    return out
end

const DRIVER = raw"""
enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- T == [], !, write(nil).
enc(T, S, S) :- atom(T), !, atom_codes(T, Cs), format("a~w", [Cs]).
enc(T, S, S) :- string(T), !, string_codes(T, Cs), format("s~w", [Cs]).
enc(T, S, S) :- integer(T), !, format("i~w", [T]).
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
function swipl_lines(path::String, names::Vector{String})::Vector{String}
    out = mktempdir() do d
        f = joinpath(d, "drv.pl")
        write(
            f,
            DRIVER * ":- initialization((fz_run('$path', [" * join(names, ",") *
            "]), halt)).\n"
        )
        read(pipeline(`swipl -q $f`; stderr=devnull), String)
    end
    return String.(split(chomp(out), '\n'; keepempty=false))
end


# the expected answers' encoding (the harness's `enc`): an atom, an integer, a compound; `nil` is []
_ea(s::String) = "a" * _codes(s)
_ei(n::Int) = "i$n"
_ec(f::String, xs::String...) = "c" * _codes(f) * "/$(length(xs))(" * join(xs, ",") * ")"
_ctx(pi::String, msg::String) = _ec("context", pi, msg)
_pi(n::String, a::Int) = _ec("/", _ea(n), _ei(a))
_sys(pi::String) = _ec(":", _ea("system"), pi)


# ── the hooks fixture (evidence/av/av_probe.pl lines 1-12 minus `attribute_goals//1`, which needs DCG) ──────
# `no` fails, `yes` succeeds, `throw(E)` throws, `log(Tag)` logs `Tag-Value` (`attvar`/`var` for such a value);
# p2/1, p5/1 are facts (a fact's and a nondeterministic predicate's exit), q3/1, q4/1, q5/1 rules whose body
# READS the log (a wakeup that runs only at the body's first goal, or later, makes them fail).
const _WK_FIXTURE = raw"""
:- dynamic hooklog/2.
attr_unify_hook(no, _) :- fail.
attr_unify_hook(yes, _).
attr_unify_hook(throw(E), _) :- throw(E).
attr_unify_hook(log(Tag), V) :- ( attvar(V) -> K = attvar ; var(V) -> K = var ; K = V ), assertz(hooklog(Tag, K)).
p2(2).
p5(1).
p5(2).
q3(1) :- hooklog(h, 1).
q4(f(1)) :- hooklog(h4, f(1)).
q5(a) :- hooklog(h5, a).
log(L) :- findall(T-K, hooklog(T, K), L), retractall(hooklog(_, _)).
"""

"The program: the fixture and `tN(R) :- retractall(hooklog(_, _)), (Goal).` for each goal; its path and the names."
function _wk_program(goals::Vector{String})
    names = ["t$(i - 1)" for i in eachindex(goals)]
    f = joinpath(mktempdir(), "p.pl")
    write(
        f,
        _WK_FIXTURE *
        join([
            "t$(i - 1)(R) :- retractall(hooklog(_, _)), ($g).\n" for
            (i, g) in enumerate(goals)
        ])
    )
    return f, names
end

"The line the harness prints for answer `r` of row `name` (`nothing`: no solution)."
_wk_line(name::String, r::Union{Nothing, String}) =
    r === nothing ? name : name * " " * _ec(name, r)

"The list `[x1, …]` as the harness encodes it."
_wk_list(xs::String...) = isempty(xs) ? "nil" : _ec("[|]", xs[1], _wk_list(xs[2:end]...))

# (id, goal, R) — the goal, and swipl's answer: rows.tsv's (swipl 10.1.18) for the hk rows, re-probed with
# swipl 10.1.19 under THIS fixture (the log is cleared before every row, as rows.tsv's). hk14s / hk14t are
# written as the substitutes of hk14 (two attributed variables, both modules `user`): they answer for
# the hooks of hk14's first half.
const _WK_HK = [
    (
        "hk01",
        "put_attr(X,user,log(t1)), X = 2, log(R)",
        _ec("[|]", _ec("-", _ea("t1"), _ei(2)), "nil")
    ),
    ("hk02", "put_attr(X,user,no), (X = 2 -> R = unified ; R = failed)", _ea("failed")),
    ("hk03", "put_attr(X,user,yes), X = 2, R = X", _ei(2)),
    ("hk04", "put_attr(X,user,throw(boom)), catch(X = 2, R, true)", _ea("boom")),
    (
        "hk06",
        "put_attr(X,user,log(x)), put_attr(Y,user,log(y)), X = Y, log(R)",
        _ec("[|]", _ec("-", _ea("y"), _ea("attvar")), "nil")
    ),
    (
        "hk07",
        "put_attr(X,user,log(t)), X = Y, log(L), (attvar(Y) -> R = L/attvar ; R = L/plain)",
        _ec("/", "nil", _ea("attvar"))
    ),
    (
        "hk08",
        "put_attr(X,user,log(h)), p2(X), log(R)",
        _ec("[|]", _ec("-", _ea("h"), _ei(2)), "nil")
    ),
    (
        "hk09",
        "put_attr(X,user,log(u)), X =.. [a], log(R)",
        _ec("[|]", _ec("-", _ea("u"), _ea("a")), "nil")
    ),
    (
        "hk12",
        "put_attr(X,user,log(is)), X is 1+1, log(R)",
        _ec("[|]", _ec("-", _ea("is"), _ei(2)), "nil")
    ),
    (
        "hk15",
        "put_attr(X,user,log(f)), f(X,a) = f(1,a), log(R)",
        _ec("[|]", _ec("-", _ea("f"), _ei(1)), "nil")
    ),
    (
        "hk16",
        "put_attr(X,user,log(two)), put_attr(Y,user,log(two_y)), f(X,Y) = f(1,2), log(R)",
        _ec(
            "[|]",
            _ec("-", _ea("two"), _ei(1)),
            _ec("[|]", _ec("-", _ea("two_y"), _ei(2)), "nil")
        )
    ),
    ("hk17", "put_attr(X,user,no), (X == 2 -> R = eq ; R = neq)", _ea("neq")),
    (
        "hk18",
        "put_attr(X,user,no), (?=(X,2) -> R = decided ; R = undecided)",
        _ea("undecided")
    ),
    (
        "hk19",
        "put_attr(X,user,no), (unifiable(X, 2, U) -> R = U ; R = no)",
        _ec("[|]", _ec("=", "V0", _ei(2)), "nil")
    ),
    (
        "hk19b",
        "put_attr(X,user,no), (unifiable(f(X), f(2), U) -> R = U ; R = no)",
        _ec("[|]", _ec("=", "V0", _ei(2)), "nil")
    ),
    (
        "hk21",
        "put_attr(X,user,log(s)), (X = 1, fail ; true), log(R)",
        _ec("[|]", _ec("-", _ea("s"), _ei(1)), "nil")
    ),
    (
        "hk14s",
        "put_attr(X,user,log(a)), put_attr(Y,user,no), (f(X,Y) = f(1,2) -> R = yes ; log(R))",
        _ec("[|]", _ec("-", _ea("a"), _ei(1)), "nil")
    ),
    (
        "hk14t",
        "put_attr(X,user,log(a)), put_attr(Y,user,log(b)), (f(X,Y) = f(1,2) -> log(R) ; R = no)",
        _ec(
            "[|]", _ec("-", _ea("a"), _ei(1)), _ec("[|]", _ec("-", _ea("b"), _ei(2)), "nil")
        )
    )
]

# the VM-site rows and the rest, answers by swipl 10.1.19: `o_*` follow the goal by a FOREIGN call, assertz/1
# (`z-0` in the log), so that a hook run late — after it — shows in the order; vc/vv/ex/ie/fe/nd rows are the
# same sites without it; nw* never wake; oc* are the occurs-check rows; sw* attvar = attvar; th*, fl*, ud*
# hooks that throw / fail / are undone
const _WK_VM = [
    (
        "vc01",
        "put_attr(X,user,log(c)), X = a, log(R)",
        _ec("[|]", _ec("-", _ea("c"), _ea("a")), "nil")
    ),
    ("vc02", "put_attr(X,user,no), (X = a -> R = unified ; R = failed)", _ea("failed")),
    (
        "vv01",
        "put_attr(X,user,log(vv)), Y = 3, X = Y, log(R)",
        _ec("[|]", _ec("-", _ea("vv"), _ei(3)), "nil")
    ),
    (
        "vv02",
        "put_attr(X,user,no), Y = 3, (X = Y -> R = unified ; R = failed)",
        _ea("failed")
    ),
    (
        "ex01",
        "put_attr(X,user,log(e)), X = f(Y), log(R)",
        _ec("[|]", _ec("-", _ea("e"), _ec("f", "V0")), "nil")
    ),
    ("ex02", "put_attr(X,user,no), (X = f(_) -> R = unified ; R = failed)", _ea("failed")),
    (
        "ie01",
        "put_attr(X,user,log(h)), q3(X), log(R)",
        _ec("[|]", _ec("-", _ea("h"), _ei(1)), "nil")
    ),
    (
        "ie02",
        "put_attr(X,user,log(h4)), q4(X), log(R)",
        _ec("[|]", _ec("-", _ea("h4"), _ec("f", _ei(1))), "nil")
    ),
    (
        "ie03",
        "put_attr(X,user,log(h5)), q5(X), log(R)",
        _ec("[|]", _ec("-", _ea("h5"), _ea("a")), "nil")
    ),
    ("ie04", "put_attr(X,user,no), (p2(X) -> R = yes ; R = no)", _ea("no")),
    (
        "nd01",
        "put_attr(X,user,log(n)), findall(X, p5(X), Xs), log(L), R = Xs/L",
        _ec(
            "/",
            _ec("[|]", _ei(1), _ec("[|]", _ei(2), "nil")),
            _ec(
                "[|]",
                _ec("-", _ea("n"), _ei(1)),
                _ec("[|]", _ec("-", _ea("n"), _ei(2)), "nil")
            )
        )
    ),
    ("nd02", "put_attr(X,user,no), findall(X, p5(X), Xs), R = Xs", "nil"),
    ("fe01", "put_attr(X,user,no), (X is 1+1 -> R = yes ; R = no)", _ea("no")),
    ("fe02", "put_attr(X,user,no), (X =.. [a] -> R = yes ; R = no)", _ea("no")),
    ("nw01", "T = f(X,Y), put_attr(X,user,no), compare(R, X, Y), T = T", _ea(">")),
    (
        "nw02",
        "put_attr(X,user,no), put_attr(Y,user,no), (X =@= Y -> R = variant ; R = not_variant)",
        _ea("variant")
    ),
    # nw02b-nw02d, nw07b (added in AV3's first run; swipl 10.1.19): an attributed variable is a variant of
    # one with variant attributes (pl-variant.c `goto attvar`), inside a compound too; compare/3 orders a
    # variable and an attributed one by address
    (
        "nw02b",
        "put_attr(X,user,no), put_attr(Y,user,no), (f(X) =@= f(Y) -> R = variant ; R = not_variant)",
        _ea("variant")
    ),
    (
        "nw02c",
        "put_attr(X,user,no), put_attr(Y,user,yes), (f(X) =@= f(Y) -> R = variant ; R = not_variant)",
        _ea("not_variant")
    ),
    (
        "nw02d",
        "put_attr(X,user,no), put_attr(Y,user,yes), (X =@= Y -> R = variant ; R = not_variant)",
        _ea("not_variant")
    ),
    ("nw03", "put_attr(X,user,no), (X \\== 2 -> R = neq ; R = eq)", _ea("neq")),
    (
        "nw04",
        "put_attr(X,user,log(u)), unifiable(f(X), f(2), _), log(L0), X = 3, log(L1), R = L0/L1",
        _ec("/", "nil", _ec("[|]", _ec("-", _ea("u"), _ei(3)), "nil"))
    ),
    (
        "nw05",
        "put_attr(X,user,log(u)), (?=(X,2) -> D = decided ; D = undecided), log(L0), X = 3, log(L1), R = D/L0/L1",
        _ec(
            "/",
            _ec("/", _ea("undecided"), "nil"),
            _ec("[|]", _ec("-", _ea("u"), _ei(3)), "nil")
        )
    ),
    (
        "nw06",
        "put_attr(X,user,log(u)), unifiable(X, 2, U), log(L0), X = 3, log(L1), R = U/L0/L1",
        _ec(
            "/",
            _ec("/", _ec("[|]", _ec("=", _ei(3), _ei(2)), "nil"), "nil"),
            _ec("[|]", _ec("-", _ea("u"), _ei(3)), "nil")
        )
    ),
    ("nw07", "put_attr(X,user,no), put_attr(Y,user,no), compare(R, X, Y)", _ea("<")),
    ("nw07b", "put_attr(X,user,no), compare(R, Y, X)", _ea(">")),
    (
        "sw01",
        "put_attr(X,user,log(x)), put_attr(Y,user,log(y)), Y = X, log(R)",
        _ec("[|]", _ec("-", _ea("y"), _ea("attvar")), "nil")
    ),
    (
        "sw02",
        "put_attr(X,user,log(x)), put_attr(Y,user,log(y)), X = Y, put_attr(Y,user,yes), (attvar(X) -> A = attvar ; A = plain), R = A",
        _ea("attvar")
    ),
    (
        "sw03",
        "put_attr(X,user,log(x)), put_attr(Y,user,log(y)), X = Y, get_attr(X, user, R)",
        _ec("log", _ea("x"))
    ),
    ("sw04", "put_attr(X,user,log(x)), X = X, log(R)", "nil"),
    (
        "ch01",
        "put_attr(X,user,log(c)), put_attr(Y,user,log(d)), X = Y, Y = 5, log(R)",
        _ec(
            "[|]",
            _ec("-", _ea("d"), _ea("attvar")),
            _ec("[|]", _ec("-", _ea("c"), _ei(5)), "nil")
        )
    ),
    ("fl01", "put_attr(X,user,no), (X = 1 ; R = alt), R = alt", _ea("alt")),
    ("fl02", "put_attr(X,user,no), (X = 1, R = unified ; R = alt)", _ea("alt")),
    ("th01", "put_attr(X,user,throw(boom)), catch(p2(X), E, true), R = E", _ea("boom")),
    (
        "th02",
        "put_attr(X,user,throw(boom)), (catch(X = 2, _, fail) ; R = recovered)",
        _ea("recovered")
    ),
    (
        "th03",
        "put_attr(X,user,throw(boom)), catch(p2(X), E, R = caught(E))",
        _ec("caught", _ea("boom"))
    ),
    (
        "mk02",
        "put_attr(X,user,yes), put_attr(X,user,no), (X = 1 -> R = yes ; R = no)",
        _ea("no")
    ),
    (
        "ud01",
        "put_attr(X,user,log(a)), (X = 1, fail ; true), (X = 2 -> true ; true), log(R)",
        _ec(
            "[|]", _ec("-", _ea("a"), _ei(1)), _ec("[|]", _ec("-", _ea("a"), _ei(2)), "nil")
        )
    ),
    (
        "o_vc",
        "put_attr(X,user,log(c)), X = a, assertz(hooklog(z,0)), log(R)",
        _ec(
            "[|]",
            _ec("-", _ea("c"), _ea("a")),
            _ec("[|]", _ec("-", _ea("z"), _ei(0)), "nil")
        )
    ),
    (
        "o_vv",
        "put_attr(X,user,log(vv)), Y = 3, X = Y, assertz(hooklog(z,0)), log(R)",
        _ec(
            "[|]",
            _ec("-", _ea("vv"), _ei(3)),
            _ec("[|]", _ec("-", _ea("z"), _ei(0)), "nil")
        )
    ),
    (
        "o_ex",
        "put_attr(X,user,log(e)), X = f(_), assertz(hooklog(z,0)), log(R)",
        _ec(
            "[|]",
            _ec("-", _ea("e"), _ec("f", "V0")),
            _ec("[|]", _ec("-", _ea("z"), _ei(0)), "nil")
        )
    ),
    (
        "o_fact",
        "put_attr(X,user,log(h)), p2(X), assertz(hooklog(z,0)), log(R)",
        _ec(
            "[|]", _ec("-", _ea("h"), _ei(2)), _ec("[|]", _ec("-", _ea("z"), _ei(0)), "nil")
        )
    ),
    (
        "o_is",
        "put_attr(X,user,log(is)), X is 1+1, assertz(hooklog(z,0)), log(R)",
        _ec(
            "[|]",
            _ec("-", _ea("is"), _ei(2)),
            _ec("[|]", _ec("-", _ea("z"), _ei(0)), "nil")
        )
    ),
    (
        "o_univ",
        "put_attr(X,user,log(u)), X =.. [a], assertz(hooklog(z,0)), log(R)",
        _ec(
            "[|]",
            _ec("-", _ea("u"), _ea("a")),
            _ec("[|]", _ec("-", _ea("z"), _ei(0)), "nil")
        )
    ),
    (
        "o_seq",
        "put_attr(X,user,log(x)), put_attr(Y,user,log(y)), X = 1, Y = 2, log(R)",
        _ec(
            "[|]", _ec("-", _ea("x"), _ei(1)), _ec("[|]", _ec("-", _ea("y"), _ei(2)), "nil")
        )
    ),
    (
        "o_seq2",
        "put_attr(X,user,log(x)), put_attr(Y,user,log(y)), X = 1, p2(Y), log(R)",
        _ec(
            "[|]", _ec("-", _ea("x"), _ei(1)), _ec("[|]", _ec("-", _ea("y"), _ei(2)), "nil")
        )
    ),
    (
        "o_rule",
        "put_attr(X,user,log(h)), q3(X), assertz(hooklog(z,0)), log(R)",
        _ec(
            "[|]", _ec("-", _ea("h"), _ei(1)), _ec("[|]", _ec("-", _ea("z"), _ei(0)), "nil")
        )
    ),
    (
        "oc01",
        "put_attr(X,user,log(o)), (unify_with_occurs_check(f(Y,X), f(g(Y),1)) -> R0 = yes ; R0 = no), log(L), R = R0/L",
        _ec("/", _ea("no"), "nil")
    ),
    (
        "oc02",
        "put_attr(X,user,log(o)), unify_with_occurs_check(f(X,a), f(1,a)), log(R)",
        _ec("[|]", _ec("-", _ea("o"), _ei(1)), "nil")
    ),
    (
        "oc03",
        "put_attr(X,user,log(o)), (unify_with_occurs_check(f(Y,X), f(g(X),g(Y))) -> R0 = yes ; R0 = no), log(L), R = R0/L",
        _ec("/", _ea("no"), "nil")
    ),
    (
        "oc04",
        "put_attr(X,user,log(o)), put_attr(Z,user,log(p)), unify_with_occurs_check(f(X,Z), f(Z,2)), log(R)",
        _ec(
            "[|]", _ec("-", _ea("p"), _ei(2)), _ec("[|]", _ec("-", _ea("o"), _ei(2)), "nil")
        )
    ),
    (
        "oc05",
        "put_attr(X,user,log(o)), (unify_with_occurs_check(f(X,Y), f(1,g(Y))) -> R0 = yes ; R0 = no), log(L), R = R0/L",
        _ec("/", _ea("no"), "nil")
    ),
    (
        "o_vcf",
        "put_attr(X,user,log(c)), X = 1.5, assertz(hooklog(z,0)), log(R)",
        _wk_list(_ec("-", _ea("c"), "f1.5"), _ec("-", _ea("z"), _ei(0)))
    ),
    (
        "o_vcs",
        "put_attr(X,user,log(c)), X = \"s\", assertz(hooklog(z,0)), log(R)",
        _wk_list(_ec("-", _ea("c"), "s" * _codes("s")), _ec("-", _ea("z"), _ei(0)))
    ),
    (
        "nw08",
        "put_attr(X,user,log(x)), put_attr(Y,user,log(y)), unifiable(f(X,Y), f(1,2), U), log(L0), X = 7, Y = 8, log(L1), R = U/L0/L1",
        _ec(
            "/",
            _ec("/", _wk_list(_ec("=", _ei(8), _ei(2)), _ec("=", _ei(7), _ei(1))), "nil"),
            _wk_list(_ec("-", _ea("x"), _ei(7)), _ec("-", _ea("y"), _ei(8)))
        )
    )
]

function _wk_check_rows(rows, label::String)
    f, names = _wk_program([g for (_, g, _) in rows])
    expected = vcat(["ok"], [_wk_line(n, r) for (n, (_, _, r)) in zip(names, rows)])
    kl = kernel_lines(f, names)
    @test length(kl) == length(expected) && kl[1] == "ok"
    for (i, (id, _, _)) in enumerate(rows)
        @test (id, get(kl, i + 1, "missing")) == (id, expected[i + 1])
    end
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "AV3 $label: the transcription not re-checked — `swipl` is not on PATH here (tools/run_tests.sh and CI have it)."
        @test true
    else
        @test swipl_lines(f, names) == expected             # the transcription is swipl's own answer
    end
    return nothing
end

@testset "rows hk01-hk19b, hk21 (evidence/av/rows.tsv): the kernel runs the hooks as swipl" begin
    @test length(_WK_HK) == 18
    _wk_check_rows(_WK_HK, "HK ROWS")
end

@testset "the run loop's check points and the non-waking rows: the hooks run where swipl runs them" begin
    @test length(_WK_VM) >= 45
    _wk_check_rows(_WK_VM, "VM ROWS")
end

# AV3-W4 (AV3's battery, CI run 40257336728): B_UNIFY_VC's second success path — `_unify_const_loc`
# (src/pl-wam.jl) — binds an attributed variable only for a constant WITHOUT a word. A float or a string never
# gets there (the compiler emits B_UNIFY_VC for an atom or a small integer only: `is_portable_constant`,
# src/pl-comp.jl; o_vcf/o_vcs go through B_UNIFY_EXIT) and an atom always has its word: it is a small integer
# in a term type whose payload holds no `Int64` (`_tagged_int_word` is 0). Such a type reads no integer
# (`put_number`'s `mk_gnd(T, ::Int64)`), so the program is built as terms and compiled. swipl 10.1.19 runs the
# same clause from text (its vm_list shows b_unify_vc(1,1) too): R = [c-1, z-zz] — the hook runs at the
# unification, before the assertz/1 after it (with the check dropped it ran after: [z-zz, c-1]).
@testset "B_UNIFY_VC wakes an attributed variable bound to a constant without a word (AV3-W4)" begin
    TB = LK.Term{Union{BigInt, Float64, String}}
    @test !LK._holds_payload(TB, Int64)
    gd = LK.PL_global_data{TB}()
    ld = LK.PL_local_data{TB}(gd)
    user = LK.MODULE_user(gd)
    s(x::String) = mk_sym(TB, Symbol(x))
    c(f::String, xs::TB...) = mk_expr(TB, TB[s(f), xs...])
    k = LK.fresh_var_keys!(9)
    v(i::Int) = mk_var(TB, k + UInt64(i))
    function add!(h::TB, b::TB)
        pr = LK.lookupProcedure(child(h, 1), nchildren(h) - 1, user)
        cl = LK.compileClause(gd, ld, h, b, pr, user)
        LK.assertDefinition!(gd, pr.definition, cl, LK.CL_END)
        return pr, cl
    end
    # the fixture's hook and log/1 on a value that is not a variable; `:- dynamic hooklog/2`
    LK.setDynamicDefinition!(LK.lookupProcedure(s("hooklog"), 2, user).definition, true)
    add!(c("attr_unify_hook", c("log", v(0)), v(1)), c("assertz", c("hooklog", v(0), v(1))))
    add!(
        c("log", v(2)),
        c(
            ",", c("findall", c("-", v(3), v(4)), c("hooklog", v(3), v(4)), v(2)),
            c("retractall", c("hooklog", v(5), v(6)))
        )
    )
    goal = "put_attr(X,user,log(c)), X = 1, assertz(hooklog(z,zz)), log(R)"
    X, R = v(7), v(8)
    one = LK.mk_gnd(TB, big(1))
    pr, cl = add!(
        c("t0", R),
        c(
            ",", c("put_attr", X, s("user"), c("log", s("c"))),
            c(
                ",",
                c("=", X, one),
                c(",", c("assertz", c("hooklog", s("z"), s("zz"))), c("log", R))
            )
        )
    )
    @test :B_UNIFY_VC in [LK.codeTable(o).name for o in _rops(cl)]
    @test LK.isTaggedInt(one) && LK._tagged_int_word(TB, one) == 0     # a small integer without a word
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(TB, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, pr, a
    )
    rc = LK.PL_next_solution(gd, ld, qid)
    @test rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
    ans = enc(LK.export_cells(ld, LK.cell_export{TB}(), -(a + 1)))
    LK.PL_close_query(ld, qid)
    LK.PL_close_foreign_frame(ld, fid)
    expected = _wk_list(_ec("-", _ea("c"), _ei(1)), _ec("-", _ea("z"), _ea("zz")))
    @test ans == expected
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "AV3-W4: the transcription not re-checked — `swipl` is not on PATH here (tools/run_tests.sh and CI have it)."
        @test true
    else
        f, names = _wk_program([goal])
        @test swipl_lines(f, names) == ["ok", _wk_line(names[1], expected)]   # swipl's own answer
    end
end

# hk14 (rows.tsv): a hook module that is not `user` (`b_mod_absent`, made on first use, inheriting from
# `user`): its hook resolves to user's attr_unify_hook/2. swipl 10.1.18 (rows.tsv) and 10.1.19: hk14 no
# solution (user's attr_unify_hook(1, 1) has no clause); the two rows after it answer which hooks ran.
# D-0083 (changed in AV3's first run, 2026-10-26): written as a KNOWN DIFFERENCE pinned on the kernel's
# refusal — old expectation `err isa LK.NotPortedError && err.step == "R2" && occursin("module", err.what)`
# (`stripModule_cells` took `user` and `system` only) — but MOD1 (d796f3d, on main before AV3) ported
# `lookupModule`, which makes the module with `user` as its default import, so the kernel answers as
# swipl. The expected answers are swipl's (re-run live below).
@testset "hk14: a hook module that inherits from `user` — the kernel answers as swipl" begin
    f, names = _wk_program([
        "put_attr(X,user,log(a)), put_attr(X,b_mod_absent,1), catch(X = 1, E, true), log(L), R = L/E",
        "put_attr(X,user,log(a)), put_attr(X,b_mod_absent,1), (X = 1 -> R = yes ; log(R))",
        "put_attr(X,user,log(a)), put_attr(X,b_mod_absent,log(b)), (X = 1 -> log(R) ; R = no)"
    ])
    expected = [
        "ok",
        "t0",                                                # no solution
        _wk_line("t1", _wk_list(_ec("-", _ea("a"), _ei(1)))),
        _wk_line("t2", _wk_list(_ec("-", _ea("a"), _ei(1)), _ec("-", _ea("b"), _ei(1))))
    ]
    @test kernel_lines(f, names) == expected
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "AV3 HK14: swipl's answer not re-checked — `swipl` is not on PATH here."
        @test true
    else
        @test swipl_lines(f, names) == expected             # the transcription is swipl's own answer
    end
end

# hk11 (rows.tsv): swipl answers outer(2) — catch/3's catcher unification wakes the hook (`no`), which fails
# the catcher's match. findCatcher's wakeup (`foreignWakeup`) runs it since AV4.
# D-0083 (AV4): until AV4 this asserted the refusal — `err isa LK.NotPortedError && err.step == "AV4"`.
@testset "findCatcher: the catcher's wakeup runs and decides the match — AV4 (hk11)" begin
    f, names = _wk_program([
        "put_attr(X,user,no), catch(catch(throw(2), X, R = inner), E, R = outer(E))"
    ])
    @test kernel_lines(f, names) == ["ok", _wk_line("t0", _ec("outer", _ei(2)))]   # swipl: outer(2)
    # a plain catcher is unaffected
    f, names = _wk_program(["catch(throw(2), Y, R = caught(Y))"])
    @test kernel_lines(f, names) == ["ok", _wk_line("t0", _ec("caught", _ei(2)))]
end

# hk10 / hk13 (rows.tsv): swipl answers not_unifiable / boom — `\=/2` unifies in can_unify and runs the hooks
# (`foreignWakeup`, since AV4). pl_not_unify2_va must send an attributed variable to the
# full check (pl-prims.c:468-469, `if ( isAttVar(w1) || isAttVar(w2) ) goto full_check;`) — see the
# report, "pl_not_unify2_va".
@testset "\\=/2 with an attributed variable: the full check runs the hooks — AV4 (hk10, hk13)" begin
    # D-0083 (AV4): until AV4 this asserted the refusal — `err isa LK.NotPortedError && err.step == "AV4"`
    # for each of the three goals; swipl 10.1.19's answers below.
    f, names = _wk_program([
        "put_attr(X,user,no), (X \\= 2 -> R = not_unifiable ; R = unifiable)",           # hk10
        "put_attr(X,user,yes), (X \\= 2 -> R = not_unifiable ; R = unifiable)",          # hk10y: a hook that succeeds
        "put_attr(X,user,throw(boom)), catch(X \\= 2, R, true)"                          # hk13
    ])
    @test kernel_lines(f, names) == [
        "ok", _wk_line("t0", _ea("not_unifiable")), _wk_line("t1", _ea("unifiable")),
        _wk_line("t2", _ea("boom"))
    ]
    # the rows without an attributed variable: unchanged
    f, names = _wk_program([
        "(X \\= 2 -> R = yes ; R = no)",
        "(f(X) \\= f(2) -> R = yes ; R = no)",
        "(a \\= b -> R = yes ; R = no)"
    ])
    @test kernel_lines(f, names) ==
        [
        "ok",
        _wk_line("t0", _ea("no")),
        _wk_line("t1", _ea("no")),
        _wk_line("t2", _ea("yes"))
    ]
end

# FIXED (found by AV4's run, evidence/av/av4_run.md Part 2): an attributed variable that is a direct ARGUMENT of a
# sub-goal of a control construct called by call/1 (a goal clause, `islocal`) is an argvar whose cell is a
# REFERENCE to it (pl-comp.c:1116-1119, :3178-3179 `*k = makeRefG(arg)`); in GOAL position it is not callable
# (:901, :3557-3558: type_error(callable, Goal)). `localGoal`/`_local_subgoal` (src/pl-comp.jl) had no DU_ATTVAR
# case: every row below threw (BoundsError, or "atom word … has no recorded symbol") on 3a4072d. Answers: swipl
# 10.1.19 under this file's fixture (re-checked by `_wk_check_rows`).
const _WK_LOCAL = [
    (
        "lg01",
        "put_attr(X,user,throw(inner)), catch((X = 1, true), E, true), R = E",
        _ea("inner")
    ),
    ("lg02", "put_attr(X,user,yes), catch((X = 1, true), E, true), R = X", _ei(1)),
    ("lg03", "put_attr(X,user,no), catch((X = 1, true), E, true), R = X", nothing),
    ("lg04", "put_attr(X,a,1), G = (Y = X, true), call(G), get_attr(Y,a,R)", _ei(1)),
    (
        "lg05",
        "put_attr(X,a,1), catch(call((X,true)), E, true), R = E",
        _ec(
            "error",
            _ec("type_error", _ea("callable"), _ec(",", "V0", _ea("true"))),
            _ctx(_sys(_pi("call", 1)), "V1")
        )
    ),
    (
        "lg06",
        "put_attr(X,user,log(h)), call((X = 1, true)), log(R)",
        _wk_list(_ec("-", _ea("h"), _ei(1)))
    ),
    (
        "lg07",
        "put_attr(X,a,1), call(((var(X) -> A = v ; A = nv), (nonvar(X) -> B = nv ; B = v), (attvar(X) -> C = av ; C = nav))), R = A/B/C",
        _ec("/", _ec("/", _ea("v"), _ea("v")), _ea("av"))
    )
]

@testset "an attributed variable as a sub-goal argument of a control construct (call/1, catch/3): an argvar — FIXED" begin
    @test length(_WK_LOCAL) == 7
    _wk_check_rows(_WK_LOCAL, "LOCAL ROWS")
end

# ── AV4: foreignWakeup (pl-wam.c) at can_unify (\=/2) and findCatcher (catch/3's catcher) ─────────────
# Rows transcribed from evidence/av/rows.tsv (hk10, hk11, hk13, hk18, hk19 there and above) and probed on
# swipl 10.1.19 (2026-10-26, ~/code/lk-av4-probes/av4.pl); `_wk_check_rows` re-checks each live. ex04/ex05
# need freeze/2 (AV7): ex04u/ex05u are their shape with a `user` hook that throws (the same wakeup, the
# same ball). hk05: a module made by the hook call inherits from `user` (MOD1), so `nomod:attr_unify_hook/2`
# is user's, whose clauses do not match `1`: false. hk05b's answer names `'$attvar':uhook/3` (R2);
# hk22/hk23 need freeze/2 (AV7).
const _WK_AV4_ROWS = [
    (
        "hk10y",
        "put_attr(X,user,yes), (X \\= 2 -> R = not_unifiable ; R = unifiable)",
        _ea("unifiable")
    ),
    (
        "hk11y",
        "put_attr(X,user,yes), catch(catch(throw(2), X, R = inner), E, R = outer(E))",
        _ea("inner")
    ),
    ("hk11t",
        "put_attr(X,user,throw(boom)), catch(catch(throw(2), X, R = inner), E, R = outer(E))",
        _ec("outer", _ea("boom"))),
    # the hook runs twice: in findCatcher's foreignWakeup, then at b_throw_resume's unification (the VM)
    ("hk11l", "put_attr(X,user,log(c)), catch(throw(2), X, true), log(R)",
        _wk_list(_ec("-", _ea("c"), _ei(2)), _ec("-", _ea("c"), _ei(2)))),
    # \= leaves no binding: the hook saw 2, X is still attributed
    ("hk13l",
        "put_attr(X,user,log(n)), (X \\= 2 -> true ; true), log(L), (attvar(X) -> R = L/attvar ; R = L/bound)",
        _ec("/", _wk_list(_ec("-", _ea("n"), _ei(2))), _ea("attvar"))),
    (
        "hk18",
        "put_attr(X,user,no), (?=(X,2) -> R = decided ; R = undecided)",
        _ea("undecided")
    ),
    ("hk19c", "put_attr(X,user,log(u)), unifiable(f(X), f(2), U), X = 3, log(L), R = U/L",
        _ec("/", _wk_list(_ec("=", _ei(3), _ei(2))), _wk_list(_ec("-", _ea("u"), _ei(3))))),
    ("hk05", "put_attr(X,nomod,1), catch(X = 2, R, true)", nothing),
    (
        "ex04u",
        "put_attr(X,user,throw(inner)), catch((X = 1, R = not_reached), R, true)",
        _ea("inner")
    ),
    ("ex05u",
        "put_attr(X,user,throw(inner)), catch(catch(X = 1, outer, R = wrong), E, R = caught(E))",
        _ec("caught", _ea("inner"))),
    # the hook throws inside findCatcher's foreignWakeup: `ex2`, raised as the new ball
    ("ex05c",
        "put_attr(X,user,throw(inner)), catch(catch(throw(b), X, R = wrong), E, R = caught(E))",
        _ec("caught", _ea("inner"))),
    # fw_nohook: `a` has no hook of its own; it inherits from `user` (MOD1), whose attr_unify_hook/2 (this file's
    # fixture, `_wk_program`) has no clause for `1`: the wakeup fails, `X \= 2` succeeds, E stays unbound —
    # swipl 10.1.19 through this driver. A bare toplevel (no user:attr_unify_hook/2) raises existence_error.
    # D-0083 (AV4 run 2): the row was `…, E = error(R, _)` expecting
    # `existence_error(procedure, a:attr_unify_hook/2)` — taken outside the driver (evidence/av/av4_run.md part 2).
    ("fw_nohook", "put_attr(X,a,1), catch(X \\= 2, E, true), R = E", "V0")
]

@testset "AV4: foreignWakeup at \\\\=/2 and catch/3's catcher — rows, re-checked on swipl" begin
    _wk_check_rows(_WK_AV4_ROWS, "AV4 rows")
end

# hk11b = upstream's `failing_catchers` (swipl-devel 7b9d8ba, tests/core_lang/test_exception.pl:81-84, `R == outer(2)`;
# its module's hook `attr_unify_hook(no, _) :- fail` is this fixture's `user` one): two attributed catchers whose
# hooks fail. findCatcher ports upstream's fix 7b9d8ba (each catcher in a foreign frame of its own). Kernel only:
# the oracle (cbf4e189 = 10.1.19) predates 7b9d8ba and gives no answer; the expected value is upstream's test row
# (D-0083 (AV4 run 2): until now a known difference, kernel's own `ex2` re-allocation, same answer outer(2)).
@testset "AV4: hk11b — upstream's failing_catchers (7b9d8ba): two attributed catchers whose hooks fail" begin
    f, names = _wk_program([
        "put_attr(X,user,no), put_attr(Y,user,no), catch(catch(catch(throw(2), X, R = inner), Y, R = mid), E, R = outer(E))"
    ])
    @test kernel_lines(f, names) == ["ok", _wk_line("t0", _ec("outer", _ei(2)))]
end

# hk11c = hk11b's discard (findCatcher's PL_discard_foreign_frame of a failed catcher, 7b9d8ba), seen through a binding:
# catcher 1 `f(B,A)` binds the plain B to 1 before A's hook fails; catcher 2 `f(_,B)` shares B and matches the ball f(1,2)
# only if that binding was undone with the frame (B = 2). Mutant AV4-K4 (the discard dropped) leaves B = 1: catcher 2
# fails and the ball goes uncaught. Kernel only (the oracle predates 7b9d8ba); the expected value follows upstream's
# frame-per-catcher semantics.
@testset "AV4: hk11c — a failed catcher's bindings are undone with its frame (7b9d8ba)" begin
    f, names = _wk_program([
        "put_attr(A,user,no), catch(catch(throw(f(1,2)), f(B,A), R = inner), f(_,B), R = outer(B))"
    ])
    @test kernel_lines(f, names) == ["ok", _wk_line("t0", _ec("outer", _ei(2)))]
end

# foreignWakeup white-box: no wakeup pending (the bit clear, or set over an empty list) — true, no query,
# the bit cleared; `ex` untouched.
@testset "AV4: foreignWakeup with nothing pending returns true and clears the bit" begin
    ld, _ = _wk_engine()
    ex = LK.PL_new_term_ref(ld)
    @test LK.foreignWakeup(ld, ex) === true && LK.PL_is_variable(ld, ex)
    ld.alerted |= LK.ALERT_WAKEUP
    @test LK.foreignWakeup(ld, ex) === true && (ld.alerted & LK.ALERT_WAKEUP) == 0
    @test LK.PL_is_variable(ld, ex)
end
