# UPSTREAM: swipl-devel src/pl-trace.c @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# What the kernel takes from SWI-Prolog's tracer support (pl-trace.c): the two built-ins that report
# POSITIONS on the local stack — `prolog_current_frame/1` (registered by pl-ext.c's FRG table, so
# called with the `a1` convention, `I_FCALLDET1`) and `prolog_current_choice/1` (a `PRED_DEF`,
# `I_FCALLDETVA`). Their differences are V3's oracle for frame and choice-point placement: a
# position is a word offset from `lBase`, so the kernel's equals swipl's (src/pl-incl.jl § the local
# stack). The debugger itself is not ported.

# PORT: pl-trace.c PL_unify_frame
"Unify `t` with frame `fr`'s position, or `none` for no frame (pl-trace.c)."
function PL_unify_frame(ld::PL_local_data{T}, t::term_t, fr::Int)::Bool where {T}
    if fr != 0
        b = ld.frames[fr].base
        @assert 0 <= b < ld.lTop                        # fr >= lBase && fr < lTop
        return PL_unify_integer(ld, t, b)               # (Word)fr - (Word)lBase
    end
    return PL_unify_atom(ld, t, mk_sym(T, :none))
end

# PORT: pl-trace.c PL_unify_choice
"Unify `t` with choice point `ch`'s position, or `none` for none (pl-trace.c)."
function PL_unify_choice(ld::PL_local_data{T}, t::term_t, ch::Int)::Bool where {T}
    if ch != 0
        b = ld.choices[ch].base
        @assert 0 <= b < ld.lTop                        # ch >= lBase && ch < lTop
        return PL_unify_integer(ld, t, b)               # (Word)ch - (Word)lBase
    end
    return PL_unify_atom(ld, t, mk_sym(T, :none))
end

# PORT: pl-trace.c pl_prolog_current_frame
# DIVERGES: "that's me" compares the frame's predicate with this built-in by name, arity and
# `P_FOREIGN` — upstream compares `impl.foreign.function` with the C function's address, which a
# table index (decision 5) is not; only a registered built-in is foreign. (The index would serve if
# qualified by its table, FRG or PRED_DEF, both numbered from 1; with one module and no
# `PL_register_foreign`, the name test is equivalent.)
"`prolog_current_frame/1` (pl-trace.c): the running frame's position — the caller's, not this call's."
function pl_prolog_current_frame(ld::PL_local_data{T}, frame::term_t)::foreign_t where {T}
    fr = ld.environment_frame
    def = ld.frames[fr].predicate::Definition{T}
    if (def.flags & P_FOREIGN) != 0 && def.arity == 1 &&
        def.functor_name == sym_key(mk_sym(T, :prolog_current_frame))
        fr = parentFrame(ld, fr)                        # thats me!
    end
    return PL_unify_frame(ld, frame, fr) ? FTRUE : FFALSE
end

# PORT: pl-trace.c prolog_current_choice as pl_prolog_current_choice1_va
# (PRED_IMPL("prolog_current_choice", 1, prolog_current_choice, 0))
"`prolog_current_choice/1` (pl-trace.c): the newest choice point's position (not the debugger's)."
function pl_prolog_current_choice1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    ch = ld.BFR                                         # LD->choicepoints
    while ch != 0 && ld.choices[ch].type == CHP_DEBUG
        ch = ld.choices[ch].parent
    end
    if ch != 0
        return PL_unify_choice(ld, A1, ch) ? FTRUE : FFALSE
    end
    return FFALSE
end

# PORT: pl-trace.c BeginPredDefs as PL_predicates_from_trace
# DIVERGES: the ported entry only (upstream's table also has `prolog_frame_attribute/3` and the
# other debugger predicates, pl-trace.c:2830-2840).
"pl-trace.c's registration table (`BeginPredDefs(trace)`): the ported entry."
const PL_predicates_from_trace = (
    PL_extension("prolog_current_choice", 1, pl_prolog_current_choice1_va, PL_FA_VARARGS),
)
