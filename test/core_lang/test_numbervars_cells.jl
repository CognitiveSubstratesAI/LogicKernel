# ORIGINAL: L1d step 7a — numberVars on CELLS (pl-prims.c do_number_vars, numberVars as their `_cells` port,
# src/pl-prims.jl) and the predicates numbervars/4 (pl-prims.c PRED_IMPL) and numbervars/3 (boot/syspred.pl);
# the workspace's L1_plan/stageL1d_design.md §3g, audit D-0016. Upstream binds each variable cell to a
# `'$VAR'(N)` laid out at gTop (`bindConst`), rewrites the ones it made — above the mark's globaltop — in place in
# singletons mode, and marks a visited compound on its functor cell; ours does the same on the cells.
# test/core_lang/test_numbervars_cells.jl — on every term type:
#   * numbervars/3,4 against swipl through clause bodies (the rules differential): the bindings and End, a
#     start offset, singletons(true) giving `'$VAR'('_')`, functor_name(F), attvar(skip|bind|error) accepted and
#     attvar(foo) a domain_error, a non-integer, unbound or out-of-range Start, the tagged range overflowing,
#     an existing `'$VAR'(N)` (numbered_check off), a DAG (visited: numbered once), a cyclic term with
#     singletons(true) (singletons dropped), a 2000-variable list, the bindings kept after the call and undone
#     on backtracking;
#   * write_canonical/1,2 against swipl on terms built by clause bodies (the cells): the text written —
#     variables numbered left to right, a variable met twice one name, singletons `_`, an existing `'$VAR'(N)`
#     and `'$VAR'(Atom)` written as terms (older than the numbering), `'$VAR'(V)` with a variable argument, a
#     DAG through a binding, a 2000-variable list, the `'$VAR'`s of an earlier numbervars/3 (older: terms to
#     write_canonical, names to writeq/print), the bindings undone after the write;
#   * white-box: numberVars binds each variable cell to a `'$VAR'` laid out above the mark, trailed (Undo
#     frees it and unbinds the cell); no MARK left on a functor cell, `ld.cycle_vstack` empty; write_canonical
#     leaves the global stack, the trail and the variables as it found them; a cyclic term refused as today
#     (decision 4a), nothing left marked or bound; writeNumberVar's older test at the frame mark's globaltop
#     (a '$VAR' AT it older, one above it newer — the `>=` on positions);
#   * the meter: a numbervars/3 loop and a write_canonical loop make no cold import (until L1f f3 also no
#     cold export, variable read or boundary pair, and the boundary — a keyed variable in the term,
#     numbered on terms, counted in `cold_pairs`: those went with the keyed variables).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

_ki(i) = _rg(Int64(i))

# ── numbervars/3,4: the rules differential ──────────────────────────────────────────────────────
_nv_clauses() = Tuple{_R, Union{Nothing, _R}}[
    (_rf("nv", _rv(1), _rv(2), _rv(3)), _rf("numbervars", _rv(1), _rv(2), _rv(3))),
    (
        _rf("nv4", _rv(1), _rv(2), _rv(3), _rv(4)),
        _rf("numbervars", _rv(1), _rv(2), _rv(3), _rv(4))
    ),
    # the bindings stay after the call
    (
        _rf("kept", _rv(1), _rv(2)),
        _rconj(
            _rf("=", _rv(1), _rf("f", _rv(2))),
            _rf("numbervars", _rv(1), _ki(0), _rv(3))
        )
    ),
    # ... and are undone on backtracking
    (
        _rf("undo", _rv(9)),
        _rconj(
            _rf("=", _rv(1), _rf("f", _rv(2), _rv(3))),
            _rf(
                ";",
                _rconj(_rf("numbervars", _rv(1), _ki(0), _rv(4)), _rs("fail")),
                _rs("true")
            ),
            _rf(";",
                _rf("->", _rconj(_rf("var", _rv(2)), _rf("var", _rv(3))),
                    _rf("=", _rv(9), _rs("unbound"))), _rf("=", _rv(9), _rs("bound")))
        )
    ),
    # a DAG built by the program: S = s(X, Y) met twice and its X once more — each variable numbered once
    (
        _rf("dag", _rv(9), _rv(8)),
        _rconj(_rf("=", _rv(1), _rf("s", _rv(2), _rv(3))),
            _rf("=", _rv(9), _rf("d", _rv(1), _rv(1), _rv(2))),
            _rf("numbervars", _rv(9), _ki(0), _rv(8)))
    ),
    # cyclic: X = f(X, Y), numbered with singletons(true) — upstream drops singletons for a cyclic term
    (
        _rf("cyc", _rv(8), _rv(3)),
        _rconj(_rf("=", _rv(1), _rf("f", _rv(1), _rv(3))),
            _rf("numbervars", _rv(1), _ki(0), _rv(8),
                _rlist(_rf("singletons", _rs("true")))))
    ),
    (
        _rf("long", _rv(1), _rv(9), _rv(8)),
        _rconj(_rf("length", _rv(9), _rv(1)), _rf("numbervars", _rv(9), _ki(0), _rv(8)))
    )
]

@testset "numbervars/3,4 on cells, as swipl" begin
    db = _rdb(_nv_clauses())
    A, B, C, E, X = _rv(50), _rv(51), _rv(52), _rv(53), _rv(54)
    st = _rf("singletons", _rs("true"))
    goals = _R[
        _rf("nv", _rf("f", A, B, A), _ki(0), E), _rf("nv", _rf("f", A, B), _ki(23), E),
        _rf("nv", _rf("g", A, _rf("h", B, A), _rlist(C, B)), _ki(0), E),
        _rf("nv", _rs("a"), _ki(0), E), _rf("nv", A, _ki(3), E),
        _rf("nv", _rf("f", _rf("\$VAR", _ki(0)), A), _ki(0), E),       # numbered_check off
        _rf("nv", _rf("f", _rf("\$VAR", B), A), _ki(0), E),
        _rf("nv", _rf("f", A, B), _ki(0), _ki(2)),
        _rf("nv", _rf("f", A, B), _ki(0), _ki(3)),
        _rf("nv", _rf("f", A), _rs("a"), E), _rf("nv", _rf("f", A), _rg(1.0), E),
        _rf("nv", _rf("f", A), B, E),
        _rf("nv", _rf("f", A), _ki(4611686018427387904), E),           # past the tagged range
        _rf("nv", _rf("f", A, B), _ki(72057594037927935), E),          # the second overflows
        _rf("nv4", _rf("f", A, B, A), _ki(0), E, _rlist(st)),
        _rf("nv4", _rf("f", _rf("\$VAR", B), B, A), _ki(0), E, _rlist(st)),
        _rf("nv4", _rf("f", _rf("\$VAR", B), A), _ki(0), E, _rlist(st)),
        _rf("nv4", _rf("f", _rf("\$VAR", _rs("_")), A, A), _ki(0), E, _rlist(st)),
        _rf("nv4", _rf("k", A, B), _ki(5), E, _rlist(_rf("functor_name", _rs("foo")))),
        _rf("nv4", _rf("k", A, B, A), _ki(0), E,
            _rlist(_rf("functor_name", _rs("v")), st)),
        _rf("nv4", _rf("f", A), _ki(0), E, _rlist(_rf("attvar", _rs("skip")))),
        _rf("nv4", _rf("f", A), _ki(0), E, _rlist(_rf("attvar", _rs("bind")))),
        _rf("nv4", _rf("f", A), _ki(0), E, _rlist(_rf("attvar", _rs("error")))),
        _rf("nv4", _rf("f", A), _ki(0), E, _rlist(_rf("attvar", _rs("foo")))),
        _rf("nv4", _rf("f", A), _ki(0), E, _rs("foo")),
        _rf("nv4", _rf("f", A), _ki(0), E, _rlist(_rf("bad", _ki(1)))),
        _rf("nv4", _rf("f", A), _ki(0), E, _rlist(_rf("singletons", _rs("maybe")))),
        _rf("kept", C, X), _rf("undo", C), _rf("dag", C, E), _rf("cyc", E, X),
        _rf("long", _ki(2000), C, E)
    ]
    ours = _rlines(db, goals)
    # the kernel's side alone (also where swipl is absent: Pkg.test)
    @test count(==("end"), ours) == length(goals)
    @test "nv(f('\$VAR'(0),'\$VAR'(1),'\$VAR'(0)),0,2) det" in ours
    @test "nv4(f('\$VAR'(0),'\$VAR'('_'),'\$VAR'(0)),0,1,[singletons(true)]) det" in ours
    @test "nv4(k(foo(5),foo(6)),5,7,[functor_name(foo)]) det" in ours
    @test "exception(domain_error(numbervar_option,[attvar(foo)])) det" in ours
    @test "undo(unbound) det" in ours
    @test "cyc(1,'\$VAR'(0)) det" in ours
    if _R_SWIPL
        theirs = _rswipl(_nv_clauses(), goals)
        @test ours == theirs
        if ours != theirs
            for i in eachindex(ours)
                if i > length(theirs) || ours[i] != theirs[i]
                    @info "first difference" i ours[i] get(theirs, i, "—")
                    break
                end
            end
        end
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

# ── write_canonical/1,2: the text, as swipl writes it ───────────────────────────────────────────
# Each `wN/0` builds its term in the clause body (on the cells) and writes it; the kernel and swipl run the
# same text, the output and the verdict compared per goal.
const _NV_WC_PROGRAM = raw"""
w1 :- T = f(X, Y, Z), write_canonical(T), nl.
w2 :- T = f(X, Y, X), write_canonical(T), nl.
w3 :- T = g(Z, h(X, Z), X, Y, Y), write_canonical(T), nl.
w4 :- T = f('$VAR'(1), X, X), write_canonical(T), nl.
w5 :- T = f('$VAR'(V), W), write_canonical(T), nl.
w6 :- T = f('$VAR'(V), V), write_canonical(T), nl.
w7 :- T = f('$VAR'('Foo'), X, '$VAR'(x)), write_canonical(T), nl.
w8 :- T = f('$VAR'('_'), X, X), write_canonical(T), nl.
w9 :- S = s(X, Y), T = d(S, S, e(Y, S)), write_canonical(T), nl.
w10 :- length(L, 2000), write_canonical(f(L, L)), nl.
w11 :- length(L, 2000), write_canonical(L), nl.
w12 :- T = f(X, Y, X), write_canonical(T), nl, ( var(X), var(Y) -> write(unbound) ; write(bound) ), nl.
w13 :- T = f(X, Y), X = g(Z, Z), write_canonical(T), nl.
w14 :- T = f(X, Y), numbervars(T, 0, E), write_canonical(T-E), nl, writeq(T), nl, print(T), nl.
w15 :- T = f(X, Y, X), numbervars(T, 0, E, [singletons(true)]), write_canonical(T-E), nl, writeq(T), nl.
w16 :- write_canonical(a), nl, write_canonical(1), nl, write_canonical("s"), nl, write_canonical([]), nl.
w17 :- X = f(Y), write_canonical(X), nl, write_canonical(X), nl, write_canonical(Y), nl.
w18 :- write_canonical(user_output, f(X, X, Y)), nl.
w19 :- T = f(X, Y), write_canonical('$VAR'(T)), nl.
w20 :- T = f(X, Y), numbervars(T, 0, _, [functor_name(v)]), write_canonical(T), nl, print(T), nl.
w21 :- T = f(X, [Y, Z|W], 'hello world', 1 - 2, Z), write_canonical(T), nl.
"""
const _NV_WC_GOALS = ["w$i" for i in 1:21]
const _NV_WC_DRIVER = raw"""
:- style_check(-singleton).
run(G) :- ( catch(G, E, true) -> ( var(E) -> true ; ex(E) ) ; write('FAIL') ), nl, write('---'), nl.
ex(error(F, _)) :- !, write('EX '), write_canonical(F).
ex(E) :- write('EX '), write_canonical(E).
"""

"The kernel's text for `name/0` loaded in `db`: its output, then the verdict and `---`, as `_NV_WC_DRIVER`'s `run/1`."
function _nv_wc_run(db::_RDB, name::String)::String
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
function _nv_load(text::String)::_RDB
    db = _RDB()
    f = joinpath(mktempdir(), "nv.pl")
    write(f, text)
    st, ball, msgs = LK.load_file!(db.gd, db.ld, f)
    @test st === :ok && all(m -> m[1] === :warning, msgs)     # (the singleton warnings)
    return db
end

@testset "write_canonical/1,2 on cells, as swipl writes it" begin
    db = _nv_load(_NV_WC_PROGRAM)
    ours = [_nv_wc_run(db, g) for g in _NV_WC_GOALS]
    # the kernel's side alone (also where swipl is absent: Pkg.test)
    @test ours[2] == "f(A,_,A)\n\n---\n"
    @test ours[3] == "g(A,h(B,A),B,C,C)\n\n---\n"
    @test ours[8] == "f('\$VAR'('_'),A,A)\n\n---\n"
    @test ours[12] == "f(A,_,A)\nunbound\n\n---\n"
    @test ours[14] == "-(f('\$VAR'(0),'\$VAR'(1)),2)\nf(A,B)\nf(A,B)\n\n---\n"
    if _R_SWIPL
        theirs = mktempdir() do d
            f = joinpath(d, "w.pl")
            write(
                f,
                _NV_WC_DRIVER * _NV_WC_PROGRAM * "main :- " *
                join(("run($g)" for g in _NV_WC_GOALS), ", ") * ".\n"
            )
            read(
                pipeline(
                    ignorestatus(`swipl -q -g main -t halt $f`);
                    stdin=devnull,
                    stderr=devnull
                ),
                String
            )
        end
        @test join(ours) == theirs
        if join(ours) != theirs
            ts = split(theirs, "---\n")
            for i in eachindex(ours)
                if i > length(ts) || ours[i] != ts[i] * "---\n"
                    @info "first difference" _NV_WC_GOALS[i] ours[i] get(ts, i, "—")
                    break
                end
            end
        end
    elseif _R_SWIPL_REQUIRED
        @test false
    end
end

# ── white-box ───────────────────────────────────────────────────────────────────────────────────
"An engine with the values of `vs` put into term references; `(ld, t)` (reference `t + i - 1` is slot `t + i`)."
function _nv_engine(vs::Vector{_R}; pvm=LK.PutVarMap())
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    ld = db.ld
    LK.PL_open_foreign_frame(ld)
    t = LK.PL_new_term_refs(ld, length(vs))
    for (i, v) in enumerate(vs)
        LK.putSlotValue!(ld, t + i, v, pvm)
    end
    return ld, t
end
_nv_counts(ld) = ld.cold_imports        # (the export/variable/pair meters went with the keyed variables, f3)
"No functor cell marked, the visited stack empty."
_nv_clean(ld) =
    !any(
        p -> LK.isFunctor(ld.gstack[p]) && (ld.gstack[p] & LK.MARK_MASK) != 0, 1:(ld.gTop)
    ) && isempty(ld.cycle_vstack)
"The global position of the compound term reference `t` holds."
_nv_pos(ld, t) = LK.valPtr(LK._deref_loc(ld, -(t + 1))[2])
_nv_opts(singletons) = LK.nv_options{_R}(_rs("\$VAR"), 0, LK.AV_SKIP, singletons, false)

@testset "white-box: each variable cell bound to a '\$VAR' laid out above the mark, trailed" begin
    X, Y, Z = _rv(1), _rv(2), _rv(3)
    ld, t = _nv_engine(_R[_rf("f", X, _rf("g", Y, X), Z)])
    c = _nv_pos(ld, t)
    fw = LK.lookupFunctorDef(ld.functors, LK._atom_word!(ld, _rs("\$VAR")), 1)
    m = LK.Mark(ld)
    g0, c0 = ld.gTop, _nv_counts(ld)
    @test LK.numberVars(ld, t, _nv_opts(0), 0) == 3
    @test _nv_clean(ld)
    @test _nv_counts(ld) == c0                      # no import
    # X (argument 1, and g's argument 2): '$VAR'(0); Y: '$VAR'(1); Z: '$VAR'(2) — left to right
    gp = LK.valPtr(LK._deref_loc(ld, c + 2)[2])
    for (loc, i) in ((c + 1, 0), (gp + 1, 1), (gp + 2, 0), (c + 3, 2))
        k, w, _ = LK._deref_loc(ld, loc)
        @test k == LK.DU_WORD && LK._is_gcompound(w)
        a = LK.valPtr(w)
        @test a > g0 && ld.gstack[a] == fw && ld.gstack[a + 1] == LK.consInt(Int64(i))
    end
    LK.Undo!(ld, m)                                 # the bindings trailed, the '$VAR' cells freed
    LK.DiscardMark(ld, m)
    @test ld.gTop == g0
    @test all(l -> LK._deref_loc(ld, l)[1] == LK.DU_CELL, (c + 1, gp + 1, c + 3))
end

@testset "white-box: singletons — the '\$VAR's made rewritten in place, an older one left" begin
    X, Y = _rv(1), _rv(2)
    old = _rf("\$VAR", _rs("_"))
    ld, t = _nv_engine(_R[_rf("f", X, Y, X, old)])
    c = _nv_pos(ld, t)
    m = LK.Mark(ld)
    @test LK.numberVars(ld, t, _nv_opts(1), 0) == 1
    @test _nv_clean(ld)
    w1 = LK._deref_loc(ld, c + 1)[2]
    w2 = LK._deref_loc(ld, c + 2)[2]
    @test w1 == LK._deref_loc(ld, c + 3)[2]         # X: one '$VAR'
    @test ld.gstack[LK.valPtr(w1) + 1] == LK.consInt(Int64(0))
    @test ld.gstack[LK.valPtr(w2) + 1] == LK._atom_word!(ld, _rs("_"))
    ow = LK._deref_loc(ld, c + 4)[2]                # the older '$VAR'('_'): untouched
    @test LK.valPtr(ow) <= m.globaltop &&
        ld.gstack[LK.valPtr(ow) + 1] == LK._atom_word!(ld, _rs("_"))
    LK.Undo!(ld, m)
    LK.DiscardMark(ld, m)
end

@testset "white-box: write_canonical leaves the stacks and the variables as it found them" begin
    X, Y = _rv(1), _rv(2)
    ld, t = _nv_engine(_R[_rf("f", X, Y, X, _rf("g", Y))])
    c = _nv_pos(ld, t)
    out = IOBuffer()
    LK.set_standard_stream!(ld, LK.SNO_USER_OUTPUT, out)
    g0, tr0 = ld.gTop, length(ld.trail)
    @test LK.pl_write_canonical(ld, t) == LK.FTRUE
    LK.Sflush(LK.Suser_output(ld))
    @test String(take!(out)) == "f(A,B,A,g(B))"
    @test ld.gTop == g0 && length(ld.trail) == tr0
    @test all(l -> LK._deref_loc(ld, l)[1] == LK.DU_CELL, (c + 1, c + 2, c + 3))
    @test _nv_clean(ld) && ld.var_names_numbervars_frame == 0
end

@testset "a cyclic term: write_canonical refuses it as today; nothing left marked or bound" begin
    Y = _rv(2)
    ld, t = _nv_engine(_R[_rf("f", _rs("x"), Y)])
    c = _nv_pos(ld, t)
    ld.gstack[c + 1] = LK.consPtr(c, LK.TAG_COMPOUND | LK.STG_GLOBAL)   # X = f(X, Y)
    out = IOBuffer()
    LK.set_standard_stream!(ld, LK.SNO_USER_OUTPUT, out)
    @test_throws LK.NotPortedError LK.pl_write_canonical(ld, t)
    @test LK._deref_loc(ld, c + 2)[1] == LK.DU_CELL
    @test _nv_clean(ld) && ld.var_names_numbervars_frame == 0
end

# writeNumberVar's "older" test, with a numbervars frame open and numbervars off: upstream's
# `fr->mark.globaltop > f` on addresses (an exclusive top) is ours `mark.globaltop >= f` on positions (gTop
# is the LAST used cell, inclusive). A '$VAR' whose functor cell is AT the mark's globaltop is older (a
# term, written `'$VAR'(0)`); one at globaltop + 1 is newer (a variable name, `A`). No swipl differential
# reaches this boundary (its '$VAR's sit well below the mark), so both positions are asserted here.
"Write `'\$VAR'(0)` laid out with the numbervars frame opened `before` the functor cell or after it; `(text, f - globaltop)`."
function _nv_older_case(before::Bool)
    ld, t = _nv_engine(_R[_rs("x")])
    fw = LK.lookupFunctorDef(ld.functors, LK._atom_word!(ld, _rs("\$VAR")), 1)
    savedf = before ? LK.BEGIN_NUMBERVARS(ld, true) : 0
    c = LK.allocGlobalCells!(ld, 1)                 # the functor cell
    ld.gstack[c] = fw
    before || (savedf = LK.BEGIN_NUMBERVARS(ld, true))
    a = LK.allocGlobalCells!(ld, 1)                 # the argument cell
    ld.gstack[a] = LK.consInt(Int64(0))
    @test a == c + 1
    ld.slots[t + 1] = LK.consPtr(c, LK.TAG_COMPOUND | LK.STG_GLOBAL)
    fr = LK.fliFrameOfFid(ld, ld.var_names_numbervars_frame)
    gt = ld.fliframes[fr].mark.globaltop
    out = IOBuffer()
    LK.set_standard_stream!(ld, LK.SNO_USER_OUTPUT, out)
    # PL_write_term with PL_WRT_VARNAMES (writeTerm2 calls writeNumberVar only under NUMBERVARS or
    # VARNAMES) and numbervars off: it opens no frame of its own (write_term/2's variable_names would)
    @test LK.PL_write_term(
        LK._query_gd(ld), ld, LK.Suser_output(ld), t, 1200,
        LK.PL_WRT_QUOTED | LK.PL_WRT_VARNAMES
    )
    LK.Sflush(LK.Suser_output(ld))
    LK.END_NUMBERVARS(ld, true, savedf)
    return String(take!(out)), c - gt
end

@testset "white-box: writeNumberVar's older test — at the mark's globaltop older, above it newer" begin
    text, d = _nv_older_case(false)                 # OLDER: the functor cell, then the frame
    @test d == 0                                    # f == globaltop
    @test text == "'\$VAR'(0)"
    text, d = _nv_older_case(true)                  # NEW: the frame, then both cells
    @test d == 1                                    # f == globaltop + 1
    @test text == "A"
end

# ── the meter ───────────────────────────────────────────────────────────────────────────────────
const _NV_METER = """
nv_loop(0) :- !.
nv_loop(N) :- T = f(X, g(Y, X), [Z, a, 1]), numbervars(T, 0, E), E == 3, N1 is N - 1, nv_loop(N1).
nv_top :- nv_loop(50).
wc_loop(0) :- !.
wc_loop(N) :- T = f(X, g(Y, X), [Z, a, 1]), write_canonical(T), N1 is N - 1, wc_loop(N1).
wc_top :- wc_loop(50).
"""

"Run `name/0` once through the query API; the return code."
function _nv_meter_run(db::_RDB, name::Symbol)::Int
    proc = LK.lookupProcedure(_rs(name), 0, db.user)
    fid = LK.PL_open_foreign_frame(db.ld)
    qid = LK.PL_open_query(db.gd, db.ld, nothing, LK.PL_Q_NORMAL, proc, 0)
    rc = LK.PL_next_solution(db.gd, db.ld, qid)
    LK.PL_close_query(db.ld, qid)
    LK.PL_discard_foreign_frame(db.ld, fid)
    return rc
end

@testset "the meter: numbervars/3 makes no cold export, import, variable read or boundary pair" begin
    db = _nv_load(_NV_METER)
    LK.set_standard_stream!(db.ld, LK.SNO_USER_OUTPUT, IOBuffer())  # the null stream
    @test _nv_meter_run(db, :nv_top) == LK.PL_S_TRUE
    c1 = _nv_counts(db.ld)
    @test _nv_meter_run(db, :nv_top) == LK.PL_S_TRUE
    @test _nv_counts(db.ld) == c1
    # write_canonical: neither its numbering nor its writer imports (until L1f f3 the pin was the four
    # meters' `(0, 0, 0, 0)` — the writer on term references since L1d 7b; MEASURED (900, 0, 850, 0)
    # per call on 7a's tree)
    @test _nv_meter_run(db, :wc_top) == LK.PL_S_TRUE
    c2 = _nv_counts(db.ld)
    @test _nv_meter_run(db, :wc_top) == LK.PL_S_TRUE
    @test _nv_counts(db.ld) == c2
end
