# ORIGINAL: unit tests of the local stack's primitives (V3), and a live check of its layout against swipl; upstream exercises them only through its VM.
# test/core_lang/test_local_stack.jl — the local stack as V3 builds it (src/pl-incl.jl § the local
# stack, src/pl-wam.jl, src/pl-fli.jl, src/pl-gc.jl, src/pl-setup.jl): one position space of
# swipl's own positions; frame, choice-point and foreign-frame records in pools; the record
# discipline (decision 3 and the user's refinements of 2026-10-05). TERM-GENERIC.
#   * POSITIONS ARE SWIPL'S: a callee's frame lies `8 + variables` above its caller's, and a
#     non-deterministic callee's choice point `8 + variables` above the callee's frame, where the
#     variables are the KERNEL's compiled `clause.variables`. swipl 10.1.16's numbers, read with
#     `prolog_current_frame/1` and `prolog_current_choice/1` as DIFFERENCES (swipl's base holds its
#     own toplevel frames), are pinned here and compared live where swipl runs;
#   * `newChoice`, foreign frames, term references, `copyFrameArguments`, the frame flags, growth;
#   * every lowering of `lTop` drops the records at or above it, and a dropped record stays readable
#     until a push reuses it; a frame being filled above `lTop` is never dropped (asserted); a
#     missed drop is caught at the next push; a reused choice point carries nothing over;
#   * warm, the primitives allocate nothing: growth is the only allocating path (reference type).
# Instruction-level behaviour — an exit popping to its frame, last-call reuse, backtracking, queries
# — is V4a's (port_inventory row V3).
using Test, LogicKernel
const LK = LogicKernel

include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _L = lk_term_type(Union{Int64, Float64, String})
"The database the clauses of this file are compiled in (its global data)."
const _LGD = LK.PL_global_data{_L}()
_ls(n) = lk_sym(_L, Symbol(n))
_lf(f, xs::_L...) = mk_expr(_L, _L[_ls(f); collect(_L, xs)])
_lv(k::Integer) = mk_var(_L, UInt64(k))
_lconj(a::_L, bs::_L...) = isempty(bs) ? a : _lf(",", a, _lconj(bs...))

"Clause `head :- body` compiled in this file's database."
function _lclause(head::_L, body::Union{Nothing, _L})::LK.Clause{_L}
    user = LK.MODULE_user(_LGD)
    name, ar = kind(head) === SYM ? (head, 0) : (child(head, 1), nchildren(head) - 1)
    proc = LK.lookupProcedure(name, ar, user)
    return LK.compileClause(_LGD, head, body, proc, user)
end

"Prolog text of a term built here: variables `V<key>`, symbols by name, `','/2` as written."
function _ltext(t::_L)::String
    kind(t) === VAR && return "V$(var_key(t))"
    kind(t) === GND && return string(lk_value(t))
    kind(t) === SYM && return (s=String(lk_name(t)); s == "," ? "','" : s)
    args = join((_ltext(child(t, i)) for i in 2:nchildren(t)), ", ")
    return "$(_ltext(child(t, 1)))($args)"
end
_ltext(h::_L, b::_L)::String = "$(_ltext(h)) :- $(_ltext(b))."

"Whether `f()` fails the assertion whose message contains `needle` — that guard, not another."
function _lasserts(f, needle::String)::Bool
    try
        f()
    catch e
        return e isa AssertionError && occursin(needle, e.msg)
    end
    return false
end

# ── the cases: swipl 10.1.16's position differences, probed (and re-read live below) ─────────────
const F0, F1, A, B, C, D, F, Ch, X, Y, Z, W = (_lv(k) for k in 1:12)
const X1, X2, X3, X4, X5, X6 = (_lv(k) for k in 21:26)
_lcur(v) = _lf("prolog_current_frame", v)
_lcho(v) = _lf("prolog_current_choice", v)
const _LZ, _LV = _ls("z"), () -> _lv(1000 + rand(1:(10 ^ 6)))   # `_LV()`: a void, met once

"(caller name, caller clause, swipl's `F1 - F0`): the callee `q(F1)`'s frame above the caller's."
const _L_FRAMES = [
    ("p1", _lf("p1", F0, F1), _lconj(_lcur(F0), _lf("q", F1), _LZ), 10),
    ("p2", _lf("p2", F0, F1, A),
        _lconj(
            _lcur(F0),
            _lf("g", A, B, C),
            _lf("g", C, D, _LV()),
            _lf("q", F1),
            _lf("z", B, D)
        ),
        14),
    ("p3", _lf("p3", F0, F1),
        _lconj(_lcur(F0), _lf("g", _LV(), _LV(), _LV()), _lf("q", F1), _LZ),
        10),
    ("p4", _lf("p4", F0, F1, A, B, C, D),
        _lconj(_lcur(F0), _lf("q", F1), _lf("z", A, B), _lf("z", C, D)), 14),
    ("p5", _lf("p5", F0, F1),
        _lconj(_lcur(F0), _lf("g", X1, X2, X3), _lf("g", X4, X5, X6), _lf("g", X1, X2, X3),
            _lf("g", X4, X5, X6), _lf("q", F1), _LZ), 16),
    ("p6", _lf("p6", F0, F1, _lf("f", A, B)),
        _lconj(_lcur(F0), _lf("g", A, B, _lf("h", C, D)), _lf("q", F1), _lf("z", C, D)), 15
    )
]

"(caller name, caller clause, the callee's FIRST clause, swipl's `C - F`): its choice point above the caller's frame."
const _L_CHOICES = [
    ("c1", _lf("c1", F, Ch), _lconj(_lcur(F), _lf("m1", X), _lcho(Ch), _lf("z", X)),
        (_lf("m1", lk_gnd(_L, 1)), nothing), 20),
    ("c2", _lf("c2", F, Ch, A),
        _lconj(_lcur(F), _lf("g", A, B, _LV()), _lf("m2", B, Y), _lcho(Ch), _lf("z", Y)),
        (_lf("m2", X, Y), _lconj(_lf("g", X, Z, W), _lf("g", Z, Y, W))), 25),
    ("c3", _lf("c3", F, Ch),
        _lconj(_lcur(F), _lf("m3", X, Y, Z), _lcho(Ch), _lf("z", X), _lf("z", Y, Z)),
        (_lf("m3", _ls("a"), _ls("b"), _ls("c")), nothing), 24)
]

"The callee's frame above the caller's, by the primitives: the caller's clause selected, then a call."
function _l_frame_diff(caller::LK.Clause{_L})::Int
    ld = LK.PL_local_data{_L}()
    fr = LK.pushFrame!(ld, ld.lTop)                         # the caller's frame (normal_call)
    base = ld.frames[fr].base
    ld.lTop = LK.argFrameP(base, Int(caller.variables))     # TRUST_CLAUSE (vmi:159)
    nfr = LK.pushFrame!(ld, ld.lTop)                        # NFR = lTop (I_CALL, vmi:1869)
    return ld.frames[nfr].base - base
end

"The callee's choice point above the caller's frame: `S_STATIC` selects its first clause, then `newChoice`."
function _l_choice_diff(caller::LK.Clause{_L}, first::LK.Clause{_L})::Int
    ld = LK.PL_local_data{_L}()
    fr = LK.pushFrame!(ld, ld.lTop)
    base = ld.frames[fr].base
    ld.lTop = LK.argFrameP(base, Int(caller.variables))
    m = LK.pushFrame!(ld, ld.lTop)
    ld.lTop = LK.argFrameP(ld.frames[m].base, Int(first.variables))   # vmi:3375
    ch = LK.newChoice(ld, LK.CHP_CLAUSE, m)                            # vmi:3379
    return ld.choices[ch].base - base
end

# the first clauses of m1..m3 come with the cases; their alternatives follow them
const _L_SWIPL_HEAD = raw"""
:- style_check(-singleton).
:- discontiguous m1/1, m2/2, m3/3.
"""
const _L_SWIPL_TAIL = raw"""
q(F1) :- prolog_current_frame(F1), z.
g(_, _, _).
z. z(_). z(_, _).
m1(2). m2(_, _). m3(_, _, _).
"""

"swipl's differences for the cases, in order: frames, then choice points."
function _l_swipl()::Vector{Int}
    mktempdir() do d
        f = joinpath(d, "ls.pl")
        lines = String[_L_SWIPL_HEAD]
        calls = String[]
        for (n, h, b, _) in _L_FRAMES
            push!(lines, _ltext(h, b))
            args = join(("_" for _ in 1:(nchildren(h) - 3)), ", ")
            push!(
                calls,
                "$n(P0$n, P1$n$(isempty(args) ? "" : ", " * args)), D$n is P1$n - P0$n, writeln(D$n)"
            )
        end
        for (n, h, b, (mh, mb), _) in _L_CHOICES
            push!(lines, _ltext(h, b))
            push!(lines, mb === nothing ? _ltext(mh) * "." : _ltext(mh, mb))
            args = join(("_" for _ in 1:(nchildren(h) - 3)), ", ")
            push!(
                calls,
                "$n(P0$n, P1$n$(isempty(args) ? "" : ", " * args)), D$n is P1$n - P0$n, writeln(D$n)"
            )
        end
        write(
            f,
            join(lines, "\n") * "\n" * _L_SWIPL_TAIL *
            "main :- " * join(("($c)" for c in calls), ", ") * ".\n"
        )
        out = read(
            pipeline(ignorestatus(`swipl -q -g main -t halt $f`); stdin=devnull), String
        )
        return [parse(Int, l) for l in split(strip(out), '\n') if !isempty(l)]
    end
end

const _L_SWIPL_BIN = Sys.which("swipl")
const _L_SWIPL_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

@testset "positions are swipl's: frame and choice-point placement" begin
    @test LK.SIZEOF_LOCALFRAME == 8 && LK.SIZEOF_CHOICE == 9 && LK.SIZEOF_FLIFRAME == 6
    @test LK.ARGOFFSET == 8 && LK.VAROFFSET(0) == 8 && LK.VARNUM(LK.VAROFFSET(5)) == 5
    @test LK.argFrameP(100, 2) == 110 == LK.varFrameP(100, Int(LK.VAROFFSET(2)))
    @test LK.refFliP(100, 3) == 109
    @test LK.LOCAL_MARGIN == 8 + 1024 + 9
    ours = vcat(
        [_l_frame_diff(_lclause(h, b)) for (_, h, b, _) in _L_FRAMES],
        [
            _l_choice_diff(_lclause(h, b), _lclause(mh, mb)) for
            (_, h, b, (mh, mb), _) in _L_CHOICES
        ]
    )
    pinned = vcat([d for (_, _, _, d) in _L_FRAMES], [d for (_, _, _, _, d) in _L_CHOICES])
    @test ours == pinned
    if _L_SWIPL_BIN !== nothing
        @testset "identical to swipl, live" begin
            @test _l_swipl() == pinned
        end
    elseif _L_SWIPL_REQUIRED
        error(
            "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the layout check would be skipped"
        )
    else
        @info "LOCAL-STACK LAYOUT vs swipl NOT RUN LIVE: `swipl` is not on PATH (the pinned numbers ran)."
    end
end

@testset "a new local data: emptyStacks leaves one foreign frame at the base" begin
    ld = LK.PL_local_data{_L}()
    @test ld.lMax == LK.LOCAL_INITIAL
    @test ld.nfliframes == 1 && ld.fli_context == 1 && ld.fliframes[1].base == 0
    # the engine's permanent references, in upstream's order, so no term_t and no fid_t is 0
    perm = LK.SIZEOF_FLIFRAME
    @test (
        ld.exception_bin, ld.exception_printed, ld.exception_tmp, ld.exception_pending
    ) ==
        (perm, perm + 1, perm + 2, perm + 3)
    @test ld.fliframes[1].size == 4 && ld.lTop == perm + 4 && ld.exception_term == 0
    @test ld.nframes == 0 && ld.nchoices == 0 && ld.BFR == 0 && ld.environment_frame == 0
    @test length(ld.frames) == cld(ld.lMax, LK.SIZEOF_LOCALFRAME)
    @test length(ld.choices) == cld(ld.lMax, LK.SIZEOF_CHOICE)
    @test length(ld.fliframes) == cld(ld.lMax, LK.SIZEOF_FLIFRAME)
    r = LK.PL_new_term_ref(ld)
    @test r == perm + 4
    LK.Trail!(ld, var_key(ld.slots[r + 1]), _ls("a"))
    LK.pushFrame!(ld, ld.lTop)
    ld.lTop += 20
    LK.newChoice(ld, LK.CHP_JUMP, 1)
    LK.emptyStacks!(ld)
    @test ld.lTop == perm + 4 && ld.nfliframes == 1 && ld.nframes == 0 && ld.nchoices == 0
    @test ld.BFR == 0 && isempty(ld.trail) && isempty(ld.bindings)
end

@testset "newChoice: at lTop, linked to BFR, with a mark" begin
    ld = LK.PL_local_data{_L}()
    fr = LK.pushFrame!(ld, ld.lTop)
    ld.lTop = LK.argFrameP(ld.frames[fr].base, 3)
    top = ld.lTop
    c1 = LK.newChoice(ld, LK.CHP_CLAUSE, fr)
    c = ld.choices[c1]
    @test c.base == top && ld.lTop == top + LK.SIZEOF_CHOICE
    @test c.type == LK.CHP_CLAUSE && c.frame == fr && c.parent == 0 && ld.BFR == c1
    @test c.mark == LK.Mark(ld)
    LK.Trail!(ld, UInt64(7), _ls("a"))
    c2 = LK.newChoice(ld, LK.CHP_JUMP, fr)
    @test ld.choices[c2].parent == c1 && ld.BFR == c2
    @test ld.choices[c2].mark.trailtop == 1 && ld.choices[c2].base == top + LK.SIZEOF_CHOICE
    # BFR must be older than the new choice point (upstream's DEBUG(0) assertion): c2 popped, but
    # BFR left on it, so the new choice point reuses c2's record AT c2's position
    LK.lowerLTop!(ld, ld.choices[c2].base)
    @test _lasserts(() -> LK.newChoice(ld, LK.CHP_JUMP, fr), "BFR is not older")
end

@testset "a reused choice-point record carries nothing of the previous enumeration" begin
    ld = LK.PL_local_data{_L}()
    fr = LK.pushFrame!(ld, ld.lTop)
    ld.lTop = LK.argFrameP(ld.frames[fr].base, 1)
    ch = LK.newChoice(ld, LK.CHP_CLAUSE, fr)
    cc = ld.choices[ch].value_clause
    @test cc.cref === nothing && cc.key == 0
    cc.cref = LK.ClauseRef{_L}(nothing, LK.word(5), nothing, nothing)
    cc.key = LK.word(42)
    LK.lowerLTop!(ld, ld.choices[ch].base)                  # the choice point is popped
    ld.BFR = ld.choices[ch].parent
    @test ld.nchoices == 0
    ch2 = LK.newChoice(ld, LK.CHP_CLAUSE, fr)
    @test ch2 == ch && ld.choices[ch2].value_clause === cc  # the same record, the same object …
    @test cc.cref === nothing && cc.key == 0                # … reset
end

@testset "foreign frames: open, close, rewind, discard" begin
    ld = LK.PL_local_data{_L}()
    top = ld.lTop
    fid = LK.PL_open_foreign_frame(ld)
    @test fid == top && ld.lTop == fid + LK.SIZEOF_FLIFRAME
    f = ld.fli_context
    @test ld.fliframes[f].base == fid && ld.fliframes[f].parent == 1 &&
        ld.fliframes[f].size == 0
    @test ld.fliframes[f].no_free_before == -1 && ld.fliframes[f].mark == LK.Mark(ld)
    @test LK.fliFrameOfFid(ld, fid) == f && LK.fliFrameOfFid(ld, 0) == 1
    @test LK.fliFrameOfFid(ld, fid + 1) == 0

    # close: the bindings are KEPT, the frame and its references are gone
    r = LK.PL_new_term_ref(ld)
    k = var_key(ld.slots[r + 1])
    LK.Trail!(ld, k, _ls("a"))
    LK.PL_close_foreign_frame(ld, fid)
    @test ld.lTop == fid && ld.fli_context == 1 && ld.nfliframes == 1
    @test haskey(ld.bindings, k)

    # rewind: the bindings are UNDONE, the references dropped, the frame stays open
    fid = LK.PL_open_foreign_frame(ld)
    r = LK.PL_new_term_refs(ld, 2)
    k = var_key(ld.slots[r + 1])
    LK.Trail!(ld, k, _ls("b"))
    inner = LK.PL_open_foreign_frame(ld)
    LK.PL_rewind_foreign_frame(ld, fid)
    @test ld.lTop == fid + LK.SIZEOF_FLIFRAME && ld.fliframes[ld.fli_context].base == fid
    @test ld.fliframes[ld.fli_context].size == 0 && !haskey(ld.bindings, k)
    @test LK.fliFrameOfFid(ld, inner) == 0 && ld.nfliframes == 2      # the inner one dropped

    # discard: the bindings are undone and the frame is closed
    r = LK.PL_new_term_ref(ld)
    k = var_key(ld.slots[r + 1])
    LK.Trail!(ld, k, _ls("c"))
    LK.PL_discard_foreign_frame(ld, fid)
    @test ld.lTop == fid && ld.fli_context == 1 && !haskey(ld.bindings, k)

    # a handle that names no open frame is refused
    @test_throws ErrorException LK.PL_close_foreign_frame(ld, 0)
    @test_throws ErrorException LK.PL_close_foreign_frame(ld, fid)
    # a frame opened at the stack's end grows it
    at = ld.lMax - 3
    ld.lTop = at
    @test LK.PL_open_foreign_frame(ld) == at && ld.lMax == 2 * LK.LOCAL_INITIAL
end

@testset "term references" begin
    ld = LK.PL_local_data{_L}()
    base = ld.fliframes[ld.fli_context].base
    nrefs(ld) = ld.fliframes[ld.fli_context].size
    n0 = nrefs(ld)                                          # the engine's permanent ones
    r = LK.PL_new_term_refs(ld, 3)
    @test r == LK.SIZEOF_FLIFRAME + n0 && ld.lTop == r + 3
    vs = [ld.slots[r + 1 + i] for i in 0:2]
    @test all(v -> kind(v) === VAR, vs) && length(unique(var_key.(vs))) == 3
    @test all(v -> var_key(v) >= KERNEL_VAR_BASE, vs)       # the kernel's own variables
    @test nrefs(ld) == n0 + 3 && ld.lTop == LK.refFliP(base, nrefs(ld))   # O_CHECK_TERM_REFS
    t = LK.new_term_ref(ld)
    @test t == r + 3 && nrefs(ld) == n0 + 4
    u = LK.PL_new_term_ref(ld)
    @test u == r + 4 && nrefs(ld) == n0 + 5 && ld.lTop == LK.refFliP(base, nrefs(ld))
    @test LK.PL_new_term_refs(ld, 0) == ld.lTop && nrefs(ld) == n0 + 5

    # copy and put: the new reference holds the term the other one references, dereferenced
    LK.Trail!(ld, var_key(ld.slots[r + 1]), _lf("f", _ls("a")))
    c = LK.PL_copy_term_ref(ld, r)
    @test c == r + 5 && nrefs(ld) == n0 + 6 && lk_eq(ld.slots[c + 1], _lf("f", _ls("a")))
    @test LK.PL_put_term(ld, t, r + 1)
    @test ld.slots[t + 1] === ld.slots[r + 2]                 # an unbound variable: itself

    # reset: lTop back to `r`, the count recomputed
    LK.PL_reset_term_refs(ld, r + 1)
    @test ld.lTop == r + 1 && nrefs(ld) == n0 + 1
    LK.PL_reset_term_refs(ld, r)
    @test ld.lTop == r && nrefs(ld) == n0
end

@testset "every lowering of lTop drops the records above it; a dropped record stays readable" begin
    ld = LK.PL_local_data{_L}()
    def = LK.lookupProcedure(_ls("p"), 0, LK.MODULE_user(_LGD)).definition
    a = LK.pushFrame!(ld, ld.lTop)                          # frame A, then its clause's slots
    fa = ld.frames[a]
    fa.parent, fa.level, fa.flags = 0, UInt32(4), LK.FR_MAGIC
    LK.setFramePredicate(fa, def)
    ld.lTop = LK.argFrameP(fa.base, 3)
    b = LK.pushFrame!(ld, ld.lTop)                          # a child B of A, with a choice point
    ld.frames[b].parent = a
    ld.lTop = LK.argFrameP(ld.frames[b].base, 2)
    ch = LK.newChoice(ld, LK.CHP_CLAUSE, b)
    fid = LK.PL_open_foreign_frame(ld)
    @test (ld.nframes, ld.nchoices, ld.nfliframes) == (2, 1, 2)

    # a deterministic exit of A: lTop = FR (vmi:2178) drops A and everything above it …
    LK.lowerLTop!(ld, fa.base)
    ld.BFR = 0                                              # (its choice point is gone with it)
    @test (ld.nframes, ld.nchoices, ld.nfliframes) == (0, 0, 1)
    # … and A is still read after it, as exit_continue reads FR->programPointer and FR->parent
    @test ld.frames[a] === fa && fa.parent == 0 && fa.level == 4 && fa.predicate === def
    @test ld.frames[b].parent == a && ld.choices[ch].frame == b
    # the next push at that position reuses the record
    @test LK.pushFrame!(ld, ld.lTop) == a && ld.frames[a].base == fa.base

    # PL_close_foreign_frame drops what was pushed inside the foreign frame
    ld.lTop = LK.argFrameP(fa.base, 1)
    fid = LK.PL_open_foreign_frame(ld)
    c = LK.pushFrame!(ld, ld.lTop)
    ld.lTop = LK.argFrameP(ld.frames[c].base, 0)
    LK.newChoice(ld, LK.CHP_JUMP, c)
    @test (ld.nframes, ld.nchoices, ld.nfliframes) == (2, 1, 2)
    LK.PL_close_foreign_frame(ld, fid)
    ld.BFR = 0
    @test (ld.nframes, ld.nchoices, ld.nfliframes) == (1, 0, 1)

    # a drop at a position keeps the records below it
    LK.dropRecords!(ld, fa.base + 1)
    @test ld.nframes == 1
    LK.dropRecords!(ld, fa.base)
    @test ld.nframes == 0
    @test _lasserts(() -> LK.lowerLTop!(ld, ld.lTop + 1), "above lTop")  # lowering only
end

@testset "a frame being filled above lTop is never dropped (asserted)" begin
    ld = LK.PL_local_data{_L}()
    nfr = LK.pushFrame!(ld, ld.lTop)                        # normal_call: NFR = lTop
    @test ld.frames[nfr].base == ld.lTop
    @test _lasserts(() -> LK.lowerLTop!(ld, ld.lTop), "being filled above lTop")
    @test _lasserts(
        () -> LK.dropRecords!(ld, ld.frames[nfr].base), "being filled above lTop"
    )
    @test ld.nframes == 1
    # once clause selection raises lTop over it, an exit may drop it
    ld.lTop = LK.argFrameP(ld.frames[nfr].base, 2)
    LK.lowerLTop!(ld, ld.frames[nfr].base)
    @test ld.nframes == 0
end

@testset "a missed drop is caught at the next push" begin
    ld = LK.PL_local_data{_L}()
    fr = LK.pushFrame!(ld, ld.lTop)
    ld.lTop = LK.argFrameP(ld.frames[fr].base, 1)
    ld.lTop = ld.frames[fr].base                            # `lTop = FR` WITHOUT the drop
    @test _lasserts(() -> LK.pushFrame!(ld, ld.lTop), "pushFrame!: a live frame")
    ld = LK.PL_local_data{_L}()
    fr = LK.pushFrame!(ld, ld.lTop)
    ld.lTop = LK.argFrameP(ld.frames[fr].base, 1)
    ch = LK.newChoice(ld, LK.CHP_CLAUSE, fr)
    ld.lTop = ld.choices[ch].base                           # a pop that forgot its record
    ld.BFR = 0
    @test _lasserts(
        () -> LK.newChoice(ld, LK.CHP_CLAUSE, fr), "pushChoice!: a live choice point"
    )
    ld = LK.PL_local_data{_L}()
    fid = LK.PL_open_foreign_frame(ld)
    ld.lTop = fid                                           # a close that forgot its records
    @test _lasserts(
        () -> LK.PL_open_foreign_frame(ld), "pushFliFrame!: a live foreign frame"
    )
end

@testset "copyFrameArguments: the last call's arguments into the frame below" begin
    ld = LK.PL_local_data{_L}()
    to = ld.lTop
    from = LK.argFrameP(to, 5)                              # the arguments pushed above lTop
    xs = [_ls("a"), _lf("f", _lv(1)), lk_gnd(_L, 3)]
    for (i, x) in enumerate(xs)
        ld.slots[LK.argFrameP(from, i - 1) + 1] = x
    end
    LK.copyFrameArguments(ld, from, to, 3)
    @test all(i -> ld.slots[LK.argFrameP(to, i - 1) + 1] === xs[i], 1:3)
    LK.copyFrameArguments(ld, from, to + 100, 0)            # argc 0: nothing
    @test !isassigned(ld.slots, LK.argFrameP(to + 100, 0) + 1)
end

@testset "frame flags and fields" begin
    ld = LK.PL_local_data{_L}()
    p, n = ld.frames[LK.pushFrame!(ld, ld.lTop)], ld.frames[2]
    p.level = UInt32(7)
    p.flags = LK.FR_MAGIC | LK.FR_DET | LK.FR_CONTEXT | LK.FR_INBOX | LK.FR_HIDE_CHILDS
    LK.setNextFrameFlags(n, p)
    @test LK.levelFrame(n) == 8 && n.flags == LK.FR_MAGIC | LK.FR_INBOX
    LK.lcoSetNextFrameFlags2(n, p)
    @test LK.levelFrame(n) == 8 && n.flags == LK.FR_MAGIC | LK.FR_DET | LK.FR_INBOX
    p.flags |= LK.FR_DETGUARD_SET
    LK.tcallSetNextFrameFlags(p)
    @test LK.levelFrame(p) == 8 &&
        p.flags == LK.FR_MAGIC | LK.FR_DET | LK.FR_CONTEXT | LK.FR_INBOX
    LK.lcoSetNextFrameFlags(p)
    @test LK.levelFrame(p) == 9 && p.flags == LK.FR_MAGIC | LK.FR_DET | LK.FR_INBOX
    LK.setLevelFrame(p, UInt32(1))
    @test LK.levelFrame(p) == 1
    @test LK.FR_WATCHED == LK.FR_CLEANUP | LK.FR_NOTIFY &&
        LK.FR_MAGIC & LK.FR_MAGIC_MASK == LK.FR_MAGIC
end

@testset "growing the local stack; the limit" begin
    ld = LK.PL_local_data{_L}()
    @test LK.hasLocalSpace(ld, ld.lMax - ld.lTop) &&
        !LK.hasLocalSpace(ld, ld.lMax - ld.lTop + 1)
    @test LK.growLocalSpace(ld, 10_000, 0) == LK.LOCAL_OVERFLOW &&
        ld.lMax == LK.LOCAL_INITIAL
    @test LK.ensureLocalSpace(ld, 10_000)
    @test ld.lMax == 4 * LK.LOCAL_INITIAL                   # doubled until it fits
    @test length(ld.frames) == cld(ld.lMax, LK.SIZEOF_LOCALFRAME)
    @test length(ld.choices) == cld(ld.lMax, LK.SIZEOF_CHOICE)
    @test length(ld.fliframes) == cld(ld.lMax, LK.SIZEOF_FLIFRAME)
    @test LK.growLocalSpace(ld, 10, LK.ALLOW_SHIFT) == LK.BOOLEX_TRUE
    ld.stacks_limit = ld.lMax
    e = try
        LK.ensureLocalSpace(ld, ld.lMax)
        nothing
    catch err
        err
    end
    @test e isa LK.LocalStackOverflow && e.limit == ld.lMax
    @test occursin("cannot grow past its limit", sprint(showerror, e))
    @test LK.raiseStackOverflow(ld, LK.BOOLEX_FALSE) == false
    # upstream's quirk: `here` above `top` reads as space (the distance converts to unsigned)
    @test LK.f_hasSpace(10, 5, 1, 1) && !LK.f_hasSpace(5, 6, 2, 1) &&
        LK.f_hasSpace(5, 6, 1, 1)
    ld.lTop = ld.lMax + 4
    @test LK.hasLocalSpace(ld, 1)
end

# A PERFORMANCE property, so the REFERENCE type's only (the second implementation boxes by design).
LK_TERM_IMPL == "reference" &&
    @testset "warm, the primitives allocate nothing: growth is the only allocating path" begin
        ld = LK.PL_local_data{_L}()
        @test LK.ensureLocalSpace(ld, 50_000)               # the pools grow with the stack
        cycle!(ld) = begin
            fr = LK.pushFrame!(ld, ld.lTop)
            base = ld.frames[fr].base
            ld.lTop = LK.argFrameP(base, 4)
            LK.newChoice(ld, LK.CHP_CLAUSE, fr)
            fid = LK.open_foreign_frame(ld)
            LK.PL_close_foreign_frame(ld, fid)
            LK.copyFrameArguments(ld, base, base, 2)
            ld.BFR = 0
            LK.lowerLTop!(ld, base)
            nothing
        end
        deep!(ld, n) = begin
            base = ld.lTop
            for _ in 1:n
                fr = LK.pushFrame!(ld, ld.lTop)
                ld.lTop = LK.argFrameP(ld.frames[fr].base, 3)
                LK.newChoice(ld, LK.CHP_CLAUSE, fr)
            end
            ld.BFR = 0
            LK.lowerLTop!(ld, base)
            nothing
        end
        ld.slots[LK.argFrameP(ld.lTop, 0) + 1] = _ls("a")
        ld.slots[LK.argFrameP(ld.lTop, 1) + 1] = _ls("b")
        cycle!(ld), deep!(ld, 1000)
        @test @allocated(cycle!(ld)) == 0
        @test @allocated(deep!(ld, 1000)) == 0                # 1000 frames and choice points deep
        @test ld.nframes == 0 && ld.nchoices == 0 && ld.nfliframes == 1
        @test @allocated(LK.growStacks!(ld, 2 * ld.lMax)) > 0  # growing does allocate
    end
