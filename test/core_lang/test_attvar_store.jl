# ORIGINAL: AV2 — the attribute store of attributed variables (design §5 row AV2; audit D-0122); upstream tests
# attributed variables in Prolog (src/Tests/attvar/*.pl), which need the wakeup (AV3) and freeze/2 (AV7).
# test/core_lang/test_attvar_store.jl — on every term type:
#   * WHITE-BOX: `put_new_attvar` lays an attributed variable out as pl-attvar.c does (a link cell on the chain,
#     the attvar cell, the list cell, `att(Name, Value, [])`) and binds the variable to a reference to it — its
#     identity a NEW, higher cell (the design's risk 4); its binding is trailed and `Undo!` cuts the chain back;
#     `find_attr`, `put_attr` (replace, trailed below the mark; append), `get_attr`, `del_attr` and a bad
#     attribute list; the FLI's `PL_is_attvar` and `PL_get_attr`; unify_with_occurs_check takes an attributed
#     variable for `canBind` (its occurs test, raising under `OCCURS_CHECK_ERROR`);
#   * THE ROWS av01-av17 and av22 of evidence/av/rows.tsv, their goals and swipl's answers transcribed (swipl
#     10.1.18, probed 2026-10-23; fixture none), through a program: the kernel's answers equal them, and — swipl
#     on PATH — swipl's own live answers equal them too (the transcription checked);
#   * LIVE rows rows.tsv does not have (trailing of each store operation, `$attv_unify/2`, the error paths, a
#     bad attribute list): the kernel's answers equal swipl's, read live — no hand-written expectations.
# No row binds an attributed variable to a value through unification or wakes a hook: that is AV3's
# (test_attvar_wakeup.jl); only the unify_simple_cells testset's attvar = value case (its D-0083 note).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "..", "core_lang", "rules_common.jl"))

"A fresh engine (`_rdb`'s) with a foreign frame open."
function _as_engine()
    db = _rdb(Tuple{_R, Union{Nothing, _R}}[])
    LK.PL_open_foreign_frame(db.ld)
    return db.ld, db
end

"The atom word of `s` in the engine's table."
_as_atom(ld, s::String) = LK._atom_word!(ld, _rs(s))

"A small integer as a dereferenced location's value `(DU_VALUE, word, 0)` (a slot's tagged integer)."
_as_int(n::Int) = (LK.DU_VALUE, LK.consInt(Int64(n)), 0)

"""
A new term reference whose cell `put_new_attvar` makes attributed with `name` = `n`: `(t, x, av)` — the term
reference, the variable's own cell and the new attvar cell.
"""
function _as_put_new!(ld, name::String, n::Int)
    t = LK.PL_new_term_ref(ld)
    x = LK.unRef(ld.slots[t + 1])
    g0 = ld.gTop
    LK.put_new_attvar(ld, x, _as_atom(ld, name), _as_int(n))
    return t, x, g0 + 2                                     # the link cell is g0 + 1, the attvar cell after it
end

@testset "put_new_attvar: the layout, the chain, a NEW higher cell as the variable's identity" begin
    ld, _ = _as_engine()
    t = LK.PL_new_term_ref(ld)
    x = LK.unRef(ld.slots[t + 1])
    g0 = ld.gTop
    a = _as_atom(ld, "a")
    LK.put_new_attvar(ld, x, a, _as_int(1))
    link, av = g0 + 1, g0 + 2
    @test ld.gTop == g0 + 7                                 # 7 cells: link, attvar, list, att/3 and its 3 arguments
    @test ld.attvar_attvars == link                         # the newest link of the chain
    @test ld.gstack[link] == 0                              # the first link: no older one
    @test ld.gstack[x] == LK.makeRefG(av) && av > x         # bound to a reference to a NEW, higher cell
    k, _, p = LK._deref_loc(ld, -(t + 1))
    @test (k, p) == (LK.DU_ATTVAR, av)
    @test ld.gstack[av] == LK.consPtr(av + 1, LK.TAG_ATTVAR | LK.STG_GLOBAL)
    @test ld.gstack[av + 1] == LK.consPtr(av + 2, LK.TAG_COMPOUND | LK.STG_GLOBAL)
    @test ld.gstack[av + 2] == LK._functor_att3(ld)
    @test ld.gstack[av + 3] == a
    @test ld.gstack[av + 4] == LK.consInt(Int64(1))
    @test ld.gstack[av + 5] == ld.atom_nil_w
    # a second one chains to the first
    _, _, av2 = _as_put_new!(ld, "b", 2)
    @test ld.attvar_attvars == av2 - 1 && ld.gstack[av2 - 1] == LK.makeRefG(link)
    # a value that needs a reference — an unbound cell — is linked by reference, never copied
    tv = LK.PL_new_term_ref(ld)
    y = LK.unRef(ld.slots[tv + 1])
    _, _, av3 = _as_put_new!(ld, "c", 0)
    LK.put_attr(ld, av3, a, LK._deref_loc(ld, -(tv + 1)))
    q = LK.valPtr(ld.gstack[av3 + 5])                       # the appended att(a, Y, [])
    @test ld.gstack[q + 2] == LK.makeRefG(y)
end

@testset "put_new_attvar under a mark: Undo! unbinds the variable and cuts the chain back" begin
    ld, _ = _as_engine()
    t = LK.PL_new_term_ref(ld)
    x = LK.unRef(ld.slots[t + 1])
    m = LK.Mark(ld)
    g = ld.gTop
    LK.put_new_attvar(ld, x, _as_atom(ld, "a"), _as_int(1))
    @test ld.attvar_attvars == g + 1 && ld.gstack[x] != 0
    LK.Undo!(ld, m)
    @test ld.gstack[x] == 0                                 # the binding was trailed (x lies below the mark)
    @test ld.gTop == g
    @test ld.attvar_attvars == 0                            # reclaim_attvars: no link above the new top
    @test LK._deref_loc(ld, -(t + 1))[1] == LK.DU_CELL
end

@testset "find_attr, put_attr, get_attr, del_attr: found, appended, replaced (trailed), removed, a bad list" begin
    ld, _ = _as_engine()
    t, _, av = _as_put_new!(ld, "a", 1)
    a, b, c = _as_atom(ld, "a"), _as_atom(ld, "b"), _as_atom(ld, "c")
    @test LK.find_attr(ld, av, a) == (true, av + 4)          # the value cell
    @test LK.find_attr(ld, av, b) == (false, av + 5)         # the closing [] cell
    @test LK.put_attr(ld, av, b, _as_int(2))                 # appended at the []
    @test LK._is_gcompound(ld.gstack[av + 5])
    q = LK.valPtr(ld.gstack[av + 5])
    @test ld.gstack[q] == LK._functor_att3(ld) && ld.gstack[q + 1] == b
    @test ld.gstack[q + 2] == LK.consInt(Int64(2)) && ld.gstack[q + 3] == ld.atom_nil_w
    @test LK.find_attr(ld, av, b) == (true, q + 2)
    @test LK.find_attr(ld, av, c) == (false, q + 3)
    # get_attr unifies the value; an absent name fails
    v = LK.PL_new_term_ref(ld)
    @test LK.get_attr(ld, av + 1, b, v)
    k, w, _ = LK._deref_loc(ld, -(v + 1))
    @test (k, w) == (LK.DU_VALUE, LK.consInt(Int64(2)))
    @test !LK.get_attr(ld, av + 1, c, LK.PL_new_term_ref(ld))
    # replaced in place, a trailed assignment below the mark (row av14's mechanism)
    m = LK.Mark(ld)
    @test LK.put_attr(ld, av, a, _as_int(9))
    @test ld.gstack[av + 4] == LK.consInt(Int64(9))
    LK.Undo!(ld, m)
    @test ld.gstack[av + 4] == LK.consInt(Int64(1))
    # an appended attribute is undone too (put_att_value's trailed assignment of the [] cell)
    m = LK.Mark(ld)
    @test LK.put_attr(ld, av, c, _as_int(3))
    LK.Undo!(ld, m)
    @test ld.gstack[q + 3] == ld.atom_nil_w
    # del_attr: the first attribute — the list cell takes the rest; an absent one fails; undone
    m = LK.Mark(ld)
    @test LK.del_attr(ld, av, a)
    @test ld.gstack[av + 1] == ld.gstack[av + 5]            # *prev = f->arguments[2]: att(b, 2, [])
    @test LK.find_attr(ld, av, a) == (false, q + 3)
    @test !LK.del_attr(ld, av, c)
    LK.Undo!(ld, m)
    @test ld.gstack[av + 1] == LK.consPtr(av + 2, LK.TAG_COMPOUND | LK.STG_GLOBAL)
    # del_attr of the LAST attribute: its predecessor's tail cell takes []
    m = LK.Mark(ld)
    @test LK.del_attr(ld, av, b)
    @test ld.gstack[av + 5] == ld.atom_nil_w
    LK.Undo!(ld, m)
    # a bad attribute list: find_attr says NULL (0), put_attr refuses, get_attr and del_attr fail
    _, _, bv = _as_put_new!(ld, "a", 1)
    ld.gstack[bv + 1] = _as_atom(ld, "foo")
    @test LK.find_attr(ld, bv, a) == (false, 0)
    @test !LK.put_attr(ld, bv, a, _as_int(2))
    @test !LK.get_attr(ld, bv + 1, a, LK.PL_new_term_ref(ld))
    @test !LK.del_attr(ld, bv, a)
end

@testset "the FLI: PL_is_attvar and PL_get_attr" begin
    ld, _ = _as_engine()
    t, _, av = _as_put_new!(ld, "a", 1)
    u = LK.PL_new_term_ref(ld)                              # unbound
    @test LK.PL_is_attvar(ld, t) && !LK.PL_is_attvar(ld, u)
    @test LK.PL_is_variable(ld, t)                          # canBind (AV1b)
    al = LK.PL_new_term_ref(ld)
    @test LK.PL_get_attr(ld, t, al)
    @test ld.slots[al + 1] == LK.makeRefG(av + 1)           # a reference to the list cell, so it can be assigned
    @test !LK.PL_get_attr(ld, u, al)
    @test ld.slots[al + 1] == LK.makeRefG(av + 1)           # untouched on failure
end

@testset "unify_with_occurs_check: an attributed variable is canBind — its occurs test runs (row av22)" begin
    ld, _ = _as_engine()
    _, _, av = _as_put_new!(ld, "a", 1)
    q = LK.allocGlobalCells!(ld, 3)                         # f(X), X the attributed variable
    ld.gstack[q] = LK.lookupFunctorDef(ld.functors, _as_atom(ld, "f"), 1)
    ld.gstack[q + 1] = LK.makeRefG(av)
    ld.gstack[q + 2] = LK.consPtr(q, LK.TAG_COMPOUND | LK.STG_GLOBAL)
    @test LK.unify_with_occurs_check_cells(ld, av, q + 2, LK.OCCURS_CHECK_TRUE) ==
        LK.BOOLEX_FALSE
    @test ld.exception_term == 0
    # under `error` the occurs test RAISES — before AV2 the attributed variable skipped it and fell to plain
    # unification, which fails without an error
    @test LK.unify_with_occurs_check_cells(ld, av, q + 2, LK.OCCURS_CHECK_ERROR) ==
        LK.BOOLEX_FALSE
    @test ld.exception_term != 0
    LK.PL_clear_exception(ld)
    @test LK.unify_with_occurs_check_cells(ld, q + 2, av, LK.OCCURS_CHECK_ERROR) ==
        LK.BOOLEX_FALSE
    @test ld.exception_term != 0
    LK.PL_clear_exception(ld)
end

@testset "unify_simple_cells: a variable gets a REFERENCE to an attvar; attvar = value is assignAttVar (AV3)" begin
    ld, _ = _as_engine()
    _, _, av = _as_put_new!(ld, "a", 1)
    attv = (LK.DU_ATTVAR, ld.gstack[av], av)
    for swap in (false, true)                               # Var = Attvar (pl-prims.c:306-309), Attvar = Var (:316-319)
        y = LK.unRef(ld.slots[LK.PL_new_term_ref(ld) + 1])
        var = (LK.DU_CELL, LK.word(0), y)
        a1, a2 = swap ? (attv, var) : (var, attv)
        @test LK.unify_simple_cells(ld, a1..., a2...) == LK.BOOLEX_TRUE
        @test ld.gstack[y] == LK.makeRefG(av)               # makeRefG(t): a reference, not the attvar word
    end
    @test ld.gstack[av] == LK.consPtr(av + 1, LK.TAG_ATTVAR | LK.STG_GLOBAL)   # the attvar itself untouched
    @test LK.unify_simple_cells(ld, attv..., attv...) == LK.BOOLEX_TRUE        # t1 == t2: the same attvar
    # assignAttVar (pl-prims.c:322-336), since AV3: the attvar bound to the value, a wakeup registered.
    # D-0083: until AV3 this asserted the refusal — `err isa LK.NotPortedError && occursin("AV3",
    # sprint(showerror, err))` for both orders; upstream binds (rows hk01-hk03, test_attvar_wakeup.jl).
    for swap in (false, true)
        ld2, _ = _as_engine()
        _, _, av2 = _as_put_new!(ld2, "a", 1)
        attv2 = (LK.DU_ATTVAR, ld2.gstack[av2], av2)
        a1, a2 = swap ? (_as_int(5), attv2) : (attv2, _as_int(5))
        @test LK.unify_simple_cells(ld2, a1..., a2...) == LK.BOOLEX_TRUE
        @test ld2.gstack[av2] == LK.consInt(Int64(5))      # *av = *value
        @test ld2.gstack[LK._attvar_head_cell(ld2)] != 0   # wakeup(…) on the list
        @test (ld2.alerted & LK.ALERT_WAKEUP) != 0
    end
    # \=/2's quick test sends an attributed variable to the full check (pl-prims.c:468-469) — without it
    # `X \= 2` answered "cannot unify". Since AV3 the full check's unification is assignAttVar: X bound, a
    # wakeup registered, which can_unify's `foreignWakeup` (AV4) would run — REFUSED until AV4.
    # D-0083: until AV3 this asserted the AV3 refusal — `err isa LK.NotPortedError && occursin("AV3",
    # sprint(showerror, err))` (assignAttVar's). swipl 10.1.19 runs the hook: `put_attr(X,a,1), X \= 2`
    # raises error(existence_error(procedure,a:attr_unify_hook/2),context('$attvar':uhook/3,_)) — and
    # `put_attr(X,user,yes), X \= 2` raises the same for attr_unify_hook/2 (no hook defined); rows with
    # hooks: AV3's test_attvar_wakeup.jl (hk10, hk13).
    a = LK.PL_new_term_refs(ld, 2)
    LK.put_new_attvar(ld, LK.unRef(ld.slots[a + 1]), _as_atom(ld, "a"), _as_int(1))
    LK.PL_put_integer(ld, a + 1, 2)
    err = try
        LK.pl_not_unify2_va(
            ld, a, 2, LK.foreign_context{_R}(LK.FRG_FIRST_CALL, UInt(0), nothing)
        )
        nothing
    catch e
        e
    end
    @test err isa LK.NotPortedError && err.step == "AV4"
end

# ── the differential harness: test_attvar_words.jl's (AV1), unchanged ─────────────────────────────────────
_codes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
function enc(t::_R, seen::Vector{UInt64}=UInt64[])::String
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

# (id, goal, R) — the goal and swipl's answer from evidence/av/rows.tsv (swipl 10.1.18, fixture none); an
# exception row's goal is wrapped in `catch(…, error(E, C), R = E/C)` so its ball is an answer; `nothing` = no
# solution (rows.tsv `false`)
const _AS_ROWS = [
    ("av01", "put_attr(X,a,1), get_attr(X,a,R)", _ei(1)),
    ("av02", "put_attr(X,a,1), put_attr(X,a,2), get_attr(X,a,R)", _ei(2)),
    (
        "av03", "put_attr(X,a,1), put_attr(X,b,2), get_attrs(X,R)",
        _ec("att", _ea("a"), _ei(1), _ec("att", _ea("b"), _ei(2), "nil"))
    ),
    ("av04", "put_attr(X,a,1), del_attr(X,a), (attvar(X) -> R = yes ; R = no)", _ea("no")),
    (
        "av05", "put_attr(X,a,1), put_attr(X,b,2), del_attr(X,a), get_attrs(X,R)",
        _ec("att", _ea("b"), _ei(2), "nil")
    ),
    ("av06", "get_attr(_,a,_), R = yes", nothing),
    (
        "av07", "catch((put_attr(a,m,1), R = yes), error(E, C), R = E/C)",
        _ec(
            "/", _ec("uninstantiation_error", _ea("a")),
            _ctx(_pi("put_attr", 3), _ea("1-st argument"))
        )
    ),
    (
        "av08", "catch((put_attr(_,1,v), R = yes), error(E, C), R = E/C)",
        _ec(
            "/",
            _ec("type_error", _ea("atom"), _ei(1)),
            _ctx(_sys(_pi("put_attr", 3)), "V0")
        )
    ),
    (
        "av09", "catch((put_attr(_,_,v), R = yes), error(E, C), R = E/C)",
        _ec("/", _ea("instantiation_error"), _ctx(_sys(_pi("put_attr", 3)), "V0"))
    ),
    ("av10", "del_attr(_,a), R = yes", _ea("yes")),
    ("av11", "del_attr(a,a), R = yes", _ea("yes")),
    (
        "av12",
        "put_attr(X,a,1), (attvar(X) -> R1 = yes ; R1 = no), (attvar(_) -> R2 = yes ; R2 = no), R = R1/R2",
        _ec("/", _ea("yes"), _ea("no"))
    ),
    ("av13", "(put_attr(X,a,1), fail ; true), (attvar(X) -> R = yes ; R = no)", _ea("no")),
    ("av14", "put_attr(X,a,1), (put_attr(X,a,2), fail ; get_attr(X,a,R))", _ei(1)),
    (
        "av15", "put_attr(X,a,Y), get_attr(X,a,V), (V == Y -> R = same ; R = different)",
        _ea("same")
    ),
    ("av16", "put_attrs(X, att(a,1,att(b,2,[]))), get_attr(X,b,R)", _ei(2)),
    ("av17", "put_attr(X,a,1), del_attrs(X), (attvar(X) -> R = yes ; R = no)", _ea("no")),
    (
        "av22", "put_attr(X,a,1), (unify_with_occurs_check(X, f(X)) -> R = yes ; R = no)",
        _ea("no")
    )
]

# rows rows.tsv does not have: compared with swipl LIVE (no hand-written expectation)
const _AS_LIVE = [
    "put_attr(X,a,1), put_attr(X,b,2), put_attr(X,c,3), del_attr(X,b), get_attrs(X,R)",  # a middle one removed
    "put_attr(X,a,1), del_attr(X,b), get_attrs(X,R)",                  # an absent name: unchanged
    "put_attr(X,a,1), (put_attr(X,b,2), fail ; get_attrs(X,R))",       # put_att_value: trailed
    "put_attr(X,a,1), (del_attr(X,a), fail ; get_attrs(X,R))",         # del_attr, del_attr/2: trailed
    "put_attr(X,a,1), (del_attrs(X), fail ; true), (attvar(X) -> R = yes ; R = no)",   # del_attrs/1: trailed
    "put_attr(X,a,1), ('\$attv_unify'(X, 5), fail ; true), get_attr(X,a,R)",   # \$attv_unify/2: trailed
    "put_attr(X,a,1), '\$attv_unify'(X, 5), R = X",                   # bound without a wakeup
    "'\$attv_unify'(X, g(1)), R = X",                                 # not attributed: PL_unify
    "put_attrs(X, foo), catch(put_attr(X,a,1), error(E, C), R = E/C)", # a bad attribute list
    "catch(put_attrs(a, []), error(E, C), R = E/C)",                   # put_attrs/2's uninstantiation
    "put_attr(X,a,1), catch(get_attr(X,1,_), error(E, C), R = E/C)",   # get_attr/3's name, on an attvar
    "catch(del_attr(_, 1), error(E, C), R = E/C)",                     # del_attr/2's name, checked first
    "put_attr(X,a,f(Y)), Y = 1, get_attr(X,a,R)",                      # the value linked, not copied
    "put_attrs(X, att(a,1,[])), put_attr(X,b,2), get_attrs(X,R)",      # put_attrs/2, then appended
    "put_attr(X,a,1), get_attrs(X,att(N,V,T)), R = N/V/T",             # get_attrs/2 unifies the list
    "( get_attrs(_, _) -> R = yes ; R = no )",                         # a plain variable has none
    "put_attr(X,a,1), del_attrs(X), put_attr(X,b,2), get_attrs(X,R)",  # attributed again after del_attrs/1
    "put_attr(A,a,1), X = A, get_attr(X,a,R)",                         # Var = Attvar: a reference (pl-prims.c:306)
    "put_attr(A,a,1), A = X, (X == A -> R = same ; R = other)",        # Attvar = Var (:316)
    "put_attr(A,a,1), A = A, get_attr(A,a,R)",                         # the same attvar: t1 == t2
    "put_attr(A,a,1), f(X, 2) = f(A, Y), get_attr(X,a,V), R = V/Y",    # through a compound's arguments
    "put_attr(A,a,1), (X = A, fail ; true), (attvar(X) -> R = attvar ; var(X) -> R = var ; R = bound)"   # trailed
]

"The program `tN(R) :- (Goal).` for each goal, written to a fresh file; its path and the names."
function _as_program(goals::Vector{String})
    names = ["t$(i - 1)" for i in eachindex(goals)]
    f = joinpath(mktempdir(), "p.pl")
    write(f, join(["t$(i - 1)(R) :- ($g).\n" for (i, g) in enumerate(goals)]))
    return f, names
end

"The line the harness prints for answer `r` of row `name` (`nothing`: no solution)."
_as_line(name::String, r::Union{Nothing, String}) =
    r === nothing ? name : name * " " * _ec(name, r)

@testset "rows av01-av17, av22 (evidence/av/rows.tsv): the kernel answers as swipl 10.1.18" begin
    f, names = _as_program([g for (_, g, _) in _AS_ROWS])
    expected = vcat(["ok"], [_as_line(n, r) for (n, (_, _, r)) in zip(names, _AS_ROWS)])
    kl = kernel_lines(f, names)
    @test length(kl) == length(expected) && kl[1] == "ok"
    for (i, (id, _, _)) in enumerate(_AS_ROWS)
        @test (id, get(kl, i + 1, "missing")) == (id, expected[i + 1])
    end
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "AV2 ROWS: the transcription not re-checked — `swipl` is not on PATH here (tools/run_tests.sh and CI have it)."
        @test true
    else
        @test swipl_lines(f, names) == expected             # the transcription of rows.tsv is swipl's own
    end
end

@testset "the store's other paths == live swipl, through a program" begin
    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "AV2 LIVE DIFFERENTIAL NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI."
        @test true
    else
        f, names = _as_program(_AS_LIVE)
        sw = swipl_lines(f, names)
        kl = kernel_lines(f, names)
        @test length(sw) == length(names) + 1 && sw[1] == "ok"
        @test length(kl) == length(sw)
        for i in eachindex(names)
            @test (_AS_LIVE[i], get(kl, i + 1, "missing")) == (_AS_LIVE[i], sw[i + 1])
        end
        # not a vacuous agreement: every row has an answer, and the error rows hold their formal terms
        @test all(i -> occursin(" ", sw[i + 1]), eachindex(names))
        @test any(l -> occursin(_codes("uninstantiation_error"), l), sw)
        @test any(l -> occursin(_codes("instantiation_error"), l), sw)
    end
end
