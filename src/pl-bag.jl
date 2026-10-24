# UPSTREAM: swipl-devel src/pl-bag.c @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# FINDALL SUPPORT (pl-bag.c): the bag a findall/3 collects its answers in. boot/bags.pl's
# findall/4 opens a bag (`'$new_findall_bag'`), runs the goal and records the template at every
# answer (`'$add_findall_bag'/1`, which fails: the goal is backtracked into), makes the list when
# the goal has no more (`'$collect_findall_bag'/2`) and closes the bag from its cleanup handler
# (`'$destroy_findall_bag'`) — however the goal ends. The bag is IMPLICIT: the innermost one of the
# thread (`LD->bags`), so a findall/3 inside the goal of another opens a bag above it.
#
# NOT PORTED: `'$suspend_findall_bag'/0` — a NONDETERMINISTIC foreign predicate (the kernel has
# none yet), findnsols/4,5's; the memory pool (`mem_pool`, `alloc_record`: Julia's GC);
# `cleanup_bags` (a thread's end); atom GC (`markAtomsFindall`, the mutex).

# PORT: pl-bag.c FINDALL_MAGIC
"The `magic` of a live bag (pl-bag.c)."
const FINDALL_MAGIC = 0x37ac78fe

# PORT: pl-bag.c new_findall_bag as pl_new_findall_bag0_va
# (PRED_IMPL("$new_findall_bag", 0, new_findall_bag, PL_FA_SIG_ATOMIC))
# DIVERGES: the bag is pushed on the local data's vector (see `findall_bag`, src/pl-incl.jl):
# there is no `findall_state` to allocate first.
"`'\$new_findall_bag'`: open a bag above the thread's others (pl-bag.c)."
function pl_new_findall_bag0_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    bag = findall_bag{T}(FINDALL_MAGIC, false, 0, 0, 0, record{T}[])
    push!(ld.bags, bag)                             # LD->bags->bags = bag

    return FTRUE
end

# PORT: pl-bag.c current_bag
# DIVERGES: the bag below is the vector's previous element; `nothing` for NULL.
"The innermost bag that is not suspended, or `nothing` (pl-bag.c)."
function current_bag(ld::PL_local_data{T})::Union{Nothing, findall_bag{T}} where {T}
    i = length(ld.bags)                             # bag = LD->bags->bags

    while i > 0 && ld.bags[i].suspended
        @assert i > 1                               # assert(bag->parent)
        i -= 1                                      # bag = bag->parent
    end

    return i > 0 ? ld.bags[i] : nothing
end

# PORT: pl-bag.c add_findall_bag
# DIVERGES: `count` 0 is "no count", as upstream's; `globalStackLimit()` is `stacks_limit`, in words
# (upstream: bytes, divided by the word size). NOT PORTED: `PL_no_memory` (nothing here allocates
# fallibly).
"Record the term `term` references in the current bag; unify `count` with the answers so far, or fail (pl-bag.c)."
function add_findall_bag(
    ld::PL_local_data{T}, term::term_t, count::term_t
)::foreign_t where {T}
    bag = current_bag(ld)

    if bag === nothing
        cbag = mk_sym(T, Symbol("findall-bag"))

        return if PL_error(
            ld, "", 0, "continuation in findall/3 generator?", ERR_PERMISSION,
            mk_sym(T, :append), cbag, term
        )
            FTRUE
        else
            FFALSE
        end
    end

    r = compileTermToHeap(ld, term)
    push!(bag.answers, r)                           # pushRecordSegStack(&bag->answers, r)
    bag.gsize += r.gsize
    bag.solutions += 1

    if bag.gsize + bag.solutions * 3 > ld.stacks_limit
        return outOfStack!(ld, STACK_OVERFLOW_RAISE, :global) ? FTRUE : FFALSE
    end

    if count != 0
        return if PL_unify_integer(ld, count, bag.solutions + bag.suspended_solutions)
            FTRUE
        else
            FFALSE
        end
    else
        return FFALSE
    end
end

# PORT: pl-bag.c add_findall_bag as pl_add_findall_bag1_va
# (PRED_IMPL("$add_findall_bag", 1, add_findall_bag, 0))
"`'\$add_findall_bag'(+Term)`: record `Term` in the current bag, and fail (pl-bag.c)."
function pl_add_findall_bag1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0

    return add_findall_bag(ld, A1, 0)
end

# PORT: pl-bag.c add_findall_bag as pl_add_findall_bag2_va
# (PRED_IMPL("$add_findall_bag", 2, add_findall_bag, 0))
"`'\$add_findall_bag'(+Term, -Count)`: record `Term`; `Count` is the answers so far (pl-bag.c)."
function pl_add_findall_bag2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1

    return add_findall_bag(ld, A1, A2)
end

# PORT: pl-bag.c collect_findall_bag as pl_collect_findall_bag2_va
# (PRED_IMPL("$collect_findall_bag", 2, collect_findall_bag, 0))
# DIVERGES: with no current bag upstream dereferences NULL; here it is asserted. The answers are taken
# from the top — the LAST answer is put back first, so its fresh variables are the oldest, as
# upstream's.
"`'\$collect_findall_bag'(-List, +Tail)`: `List` is the current bag's answers, in order, before `Tail` (pl-bag.c)."
function pl_collect_findall_bag2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    bag = current_bag(ld)
    @assert bag !== nothing "'\$collect_findall_bag'/2: no bag"

    if bag.solutions != 0
        list = PL_copy_term_ref(ld, A2)
        answer = PL_new_term_ref(ld)

        ensureGlobalSpace(ld, bag.gsize + bag.solutions * 3) || return FFALSE   # ensureGlobalSpace(space)

        while !isempty(bag.answers)                 # (rp=topOfSegStack(&bag->answers))
            r = bag.answers[end]
            copyRecordToGlobal(ld, answer, r)
            PL_cons_list(ld, list, answer, list)
            pop!(bag.answers)                       # popTopOfSegStack(&bag->answers)
        end

        return PL_unify(ld, A1, list) ? FTRUE : FFALSE
    else
        return PL_unify(ld, A1, A2) ? FTRUE : FFALSE
    end
end

# PORT: pl-bag.c destroy_findall_bag as pl_destroy_findall_bag0_va
# (PRED_IMPL("$destroy_findall_bag", 0, destroy_findall_bag, 0))
# DIVERGES: popping the vector is `LD->bags->bags = bag->parent` and `popSegStack_`; the records go
# with the bag (no pool to clear).
"`'\$destroy_findall_bag'`: close the innermost bag (pl-bag.c)."
function pl_destroy_findall_bag0_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    @assert !isempty(ld.bags) "'\$destroy_findall_bag'/0: no bag"      # assert(bag)
    bag = ld.bags[end]                              # bag = LD->bags->bags
    @assert bag.magic == FINDALL_MAGIC
    @assert bag.suspended == false

    pop!(ld.bags)                                   # LD->bags->bags = bag->parent

    bag.magic = 0
    empty!(bag.answers)                             # clearSegStack(&bag->answers)

    return FTRUE
end

# PORT: pl-bag.c BeginPredDefs as PL_predicates_from_bag
# DIVERGES: the ported entries (upstream's table also has `'$suspend_findall_bag'/0`).
"pl-bag.c's registration table (`BeginPredDefs(bag)`): the ported entries."
const PL_predicates_from_bag = (
    PL_extension("\$new_findall_bag", 0, pl_new_findall_bag0_va, PL_FA_VARARGS),
    PL_extension("\$add_findall_bag", 1, pl_add_findall_bag1_va, PL_FA_VARARGS),
    PL_extension("\$add_findall_bag", 2, pl_add_findall_bag2_va, PL_FA_VARARGS),
    PL_extension("\$collect_findall_bag", 2, pl_collect_findall_bag2_va, PL_FA_VARARGS),
    PL_extension("\$destroy_findall_bag", 0, pl_destroy_findall_bag0_va, PL_FA_VARARGS)
)
