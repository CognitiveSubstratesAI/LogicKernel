# UPSTREAM: swipl-devel src/pl-alloc.c @ 8609e216cab9
# UPSTREAM: swipl-devel src/pl-gc.h @ 8609e216cab9
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# What the kernel takes from SWI-Prolog's memory management (pl-alloc.c): raising a stack overflow
# as a Prolog error with the spare stack enabled (since V5d), and growing the argument stack.

# PORT: pl-alloc.c enableSpareStack as enableSpareStack!
# DIVERGES: the local stack's, in positions.
"""
Add the local stack's spare to its `max`, when there is one and its free room is below the spare's
size or `always` (pl-alloc.c); whether it did.
"""
function enableSpareStack!(ld::PL_local_data{T}, always::Bool)::Bool where {T}
    if ld.local_spare != 0 && (ld.lMax - ld.lTop < ld.local_def_spare || always)
        ld.lMax += ld.local_spare                   # s->max = addPointer(s->max, s->spare)
        ld.local_spare = 0
        return true
    end
    return false
end

# PORT: pl-alloc.c enableSpareStack as enableSpareStack_global!
# DIVERGES (L1f f1b): the global stack's spare, a reserve in the one limit: enabling it returns it to the
# room under the limit (`_stacks_in_use`), which is that room (upstream: `roomStackP`).
"Release the global stack's spare when its room is below the spare's size or `always` (pl-alloc.c); whether it did."
function enableSpareStack_global!(ld::PL_local_data, always::Bool)::Bool
    if ld.global_spare != 0 &&
        (ld.stacks_limit - _stacks_in_use(ld, 0) < ld.global_def_spare || always)
        ld.global_spare = 0                         # s->max += s->spare; s->spare = 0
        return true
    end
    return false
end

# PORT: pl-alloc.c enableSpareStack as enableSpareStack_trail!
# DIVERGES (L1f f1b): as `enableSpareStack_global!`, the trail's.
"Release the trail's spare when its room is below the spare's size or `always` (pl-alloc.c); whether it did."
function enableSpareStack_trail!(ld::PL_local_data, always::Bool)::Bool
    if ld.trail_spare != 0 &&
        (ld.stacks_limit - _stacks_in_use(ld, 0) < ld.trail_def_spare || always)
        ld.trail_spare = 0
        return true
    end
    return false
end

# PORT: pl-alloc.c enableSpareStacks as enableSpareStacks!
"Enable the spare stacks where they are needed (pl-alloc.c)."
function enableSpareStacks!(ld::PL_local_data{T})::Nothing where {T}
    enableSpareStack!(ld, false)                    # local
    enableSpareStack_global!(ld, false)
    enableSpareStack_trail!(ld, false)
    return nothing
end

# PORT: pl-alloc.c push_overflow_context
# DIVERGES (L1f f2, audit D-0029 D2 (a); the local stack's since D-0040): the context of an overflow of
# EITHER stack is the atom `stack_overflow`, the tag of swipl's dict (`stack_overflow{choicepoints:…,
# depth:…, globalused:…, stack:[…]}`), which the kernel cannot build — on the divergence list.
# NOT PORTED: the dict itself (the stack sizes, the depth, the environments and choice points, the
# recursion found by `find_non_terminating_recursion` or the top of the stack): the kernel has no
# dicts; and the stack's name atom, upstream's fallback when the dict cannot be built.
"The context of a stack overflow's error: the atom `stack_overflow` (swipl: a dict of that tag)."
push_overflow_context(::Type{T}, stack::Symbol) where {T} = mk_sym(T, :stack_overflow)

# PORT: pl-alloc.c outOfStack as outOfStack!
# DIVERGES: the local stack's, the only one that overflows here.
#   * A SECOND overflow before the first is recovered from (`LD->outofstack` still set): upstream
#     prints a backtrace and ENDS THE PROCESS (`fatalError`), because it can no longer trust its
#     state. A library must not end its host, so the kernel marks the local data `unusable` —
#     `PL_open_query` refuses every later query on it — and throws a Julia error with upstream's
#     message: nothing runs on a state that cannot be trusted, and the host survives (user,
#     2026-10-07).
#   * The ball is built as a value into `exception_bin` (upstream: raw global cells, then
#     `freezeGlobal`): it holds no variable, so undoing bindings cannot change it.
# NOT PORTED: the backtraces and the low-spare message (the kernel prints nothing, decision 1);
# `trim_stack_requested` (its readers are the stack garbage collector's, G1); the "no room for
# exception term" abort (the ball is a value: there is no global stack to run out of); the longjmp
# of `STACK_OVERFLOW_THROW` — every caller that throws a local-stack overflow sets `LD->outofstack`
# first, so the fatal branch runs before it, and the other stacks do not overflow here.
"""
    outOfStack!(ld, how) -> false

Raise `error(resource_error(stack), stack_overflow)` for an overflow of the local stack: enable its spare,
mark the exception processed and the stack out of room (pl-alloc.c). A second overflow before the
first is recovered from makes `ld` unusable and throws.
"""
function outOfStack!(
    ld::PL_local_data{T}, how::stack_overflow_action, stack::Symbol=:local
)::Bool where {T}
    if ld.outofstack                                # LD->outofstack == stack
        ld.unusable = true                          # (see above: no fatalError)
        error("[Thread 1]: failed to recover from local-overflow: Sorry, cannot continue")
    end
    enableSpareStacks!(ld)
    ld.exception_processing = true
    ld.outofstack = true
    ctx = push_overflow_context(T, stack)
    _slot_store_value!(                             # the ball: a value (decision 1; L1c)
        ld,
        ld.exception_bin + 1,
        mk_expr(
            T,
            T[
                mk_sym(T, :error),
                mk_expr(T, T[mk_sym(T, :resource_error), mk_sym(T, :stack)]),
                ctx
            ]
        )
    )
    ld.exception_term = ld.exception_bin
    return false
end

# PORT: pl-alloc.c raiseStackOverflow
# DIVERGES: only `LOCAL_OVERFLOW` exists here — there is no global, trail, combined or argument stack
# of fixed size, and Julia raises its own `OutOfMemoryError` (`MEMORY_OVERFLOW`); `false` ("some
# other error is pending") returns `false`, as upstream.
"Raise the overflow `overflow` reports (pl-alloc.c)."
function raiseStackOverflow(ld::PL_local_data{T}, overflow::boolex_t)::Bool where {T}
    if overflow == LOCAL_OVERFLOW
        return outOfStack!(ld, STACK_OVERFLOW_RAISE)
    elseif overflow == GLOBAL_OVERFLOW                  # L1f f2
        return outOfStack!(ld, STACK_OVERFLOW_RAISE, :global)
    end
    @assert overflow == BOOLEX_FALSE "raiseStackOverflow: not an overflow: $overflow"
    return false
end

# ORIGINAL (L1f f2, audit D-0036; pl-gc.c grow_stacks: `tsize + gsize + lsize > LD->stacks.limit`): what
# the ONE limit over the three stacks is measured against. DIVERGES: in words; the local stack by its size
# (`lMax` and its spare, as `growStacks!` grows it), the global stack by its use (`gTop`: it grows cell by
# cell on demand) and its spare, the trail by its entries and its spare (the spares since L1f f1b, audit
# D-0042: reserves, released by `enableSpareStacks!`); the record pools (frames, choices) are Julia objects
# and do not count.
"The words the three stacks take once `g` more global cells are laid out (pl-gc.c `grow_stacks`' sum)."
@inline _stacks_in_use(ld::PL_local_data, g::Int)::Int =
    (ld.lMax + ld.local_spare) + (ld.gTop + g + ld.global_spare) + (length(ld.trail) + ld.trail_spare)

# PORT: pl-gc.h ensureGlobalSpace
# DIVERGES (L1f f2, audit D-0029 D1 (a), D3 (a), D-0036): no garbage collection to try (`ALLOW_GC`) and
# nothing to shift — the stack grows on demand (`_growGlobalStack!`) — so the check is the LIMIT: the three
# stacks with `n` more cells within `stacks_limit` (`_stacks_in_use`), else the overflow is raised
# (`resource_error(stack)`). While an exception is processed no request is refused: upstream's
# `grow_stacks` in its error condition raises the limit to the need plus 1 MiB (pl-gc.c:5371,
# `EMERGENCY_LIMIT`) for every request, so none fails for the limit (L1f f1b: the audit's D-0042 traced).
# The handler itself runs after `resumeAfterException` (processing cleared): under the limit again.
"Make room for `n` cells above `gTop` within the limit, or raise the global overflow (pl-gc.h `ensureGlobalSpace`)."
function ensureGlobalSpace(ld::PL_local_data, n::Int)::Bool
    (_stacks_in_use(ld, n) <= ld.stacks_limit || ld.exception_processing) && return true
    return raiseStackOverflow(ld, GLOBAL_OVERFLOW)
end

# PORT: pl-alloc.c allocGlobalNoShift
# DIVERGES (L1f f1b): the stack grows on demand (`allocGlobalCells!`), so "no room without shifting"
# (`gTop+n > gMax`) is the LIMIT, as `ensureGlobalSpace` tests it; returns the first cell's position, 0
# for NULL. Raises nothing: the caller passes `GLOBAL_OVERFLOW` up, as upstream's.
"`n` cells at `gTop` if they fit the limit, else 0 (pl-alloc.c `allocGlobalNoShift`)."
function allocGlobalNoShift(ld::PL_local_data, n::Int)::Int
    (_stacks_in_use(ld, n) <= ld.stacks_limit || ld.exception_processing) || return 0
    return allocGlobalCells!(ld, n)
end

# PORT: pl-alloc.c f_pushArgumentStack
# DIVERGES: the stack doubles; nothing is re-based (`aSave` is a height, not a pointer), and there is
# no limit of its own (upstream's `outOfStack` on the argument stack).
"Grow the argument stack and push `e` (pl-alloc.c)."
function f_pushArgumentStack(ld::PL_local_data{T}, e::argstack_entry{T})::Nothing where {T}
    resize!(ld.astack, 2 * length(ld.astack))
    ld.aTop += 1
    ld.astack[ld.aTop] = e
    return nothing
end

# PORT: pl-alloc.c allocGlobal as allocGlobalCells!
# DIVERGES: allocates `n` cell VARIABLES (L1a): each cell unbound (`setVar`), its key recorded;
# returns the first cell's position, the others follow it (upstream returns its address). One stamp
# per allocation (src/pl-global.jl `CELL_KEY_TAG`). Growth is `_growGlobalStack!`'s, the only
# allocating path; no garbage collection (`ensureGlobalSpace`'s `ALLOW_GC`) until pl-gc.c's
# collector is ported, after L1.
"Allocate `n` fresh variables on the global stack; the position of the first (pl-alloc.c `allocGlobal`)."
function allocGlobalCells!(ld::PL_local_data{T}, n::Int)::Int where {T}
    ld.stamp_next == ld.stamp_end && _reserveStamps!(ld)
    stamp = ld.stamp_next & CELL_STAMP_MASK
    ld.stamp_next += UInt64(1)
    p = ld.gTop + 1
    top = ld.gTop + n
    top > length(ld.gstack) && _growGlobalStack!(ld, top)
    k = CELL_KEY_TAG | (stamp << 28) | UInt64(p)
    for i in 0:(n - 1)
        ld.gstack[p + i] = word(0)    # setVar()
        ld.gkey[p + i] = k + UInt64(i)                 # (its variable term: on demand, `_cell_var`)
    end
    ld.gTop = top
    return p
end

# ORIGINAL: `allocGlobalCells!` for the callers that build a variable term: the first cell's KEY,
# the others following it (`k + i`).
"Allocate `n` fresh variables on the global stack; the key of the first."
allocGlobalVars!(ld::PL_local_data, n::Int)::UInt64 =
    _cell_key(ld, allocGlobalCells!(ld, n))

# ORIGINAL: a block of stamps from the process-wide counter (src/pl-global.jl).
"Reserve the engine's next block of stamps."
@noinline function _reserveStamps!(ld::PL_local_data)::Nothing
    first = Threads.atomic_add!(_CELL_STAMP_COUNTER, CELL_STAMP_BLOCK)
    ld.stamp_next = first
    ld.stamp_end = first + CELL_STAMP_BLOCK
    return nothing
end

# ORIGINAL: the global stack's growth (upstream: `growStacks`, pl-gc.c, which shifts the stacks):
# the two vectors grow to hold position `top`, doubling. No limit until `stack_limit` covers the
# global stack (after L1), beyond the positions a key can name.
"Grow the global stack to hold at least `top` cells."
@noinline function _growGlobalStack!(ld::PL_local_data, top::Int)::Nothing
    top <= Int(CELL_POS_MASK) || error("the global stack is full: $top cells (L1a: 2^28)")
    n = max(top, 2 * length(ld.gstack), 1024)
    n = min(n, Int(CELL_POS_MASK))
    resize!(ld.gstack, n)
    resize!(ld.gkey, n)
    old = length(ld.gterms)
    resize!(ld.gterms, n)
    fill!(view(ld.gterms, (old + 1):n), nothing)     # (a new position holds no export: L1c)
    return nothing
end
