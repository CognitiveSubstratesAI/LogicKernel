# UPSTREAM: swipl-devel src/pl-undo.c @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-undo.h @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2022-2925, SWI-Prolog Solutions b.v.
# (the year range is copied exactly as pl-undo.c at the pin has it, typo included: tools/port_check.jl compares the line)
#
# PORTED FROM pl-undo.c (TX1e): `undo/1`, goals run when a trailed assignment of the first global cell is undone (on
# backtracking). `'$undo'(Goal)` records `Goal` (a record in `gd.undo_refs`, named by an atom of the blob type `undo`) and
# conses the atom on the list in the FIRST global cell (`ld.undo_list`), a TRAILED assignment. When `Undo!` resets that cell
# (src/pl-inline.jl) `push_undo` finds the list that is being undone and schedules the blobs on it (`ld.undo_scheduled`,
# `ALERT_UNDO`); the run loop calls `run_undo_hooks` at the next predicate call (src/pl-wam.jl, `depart_or_retry_continue`, pl-vmi.c:1989)
# and after the next backtrack (`deep_backtrack`, pl-vmi.c:6850), which runs `'$syspreds':'$run_undo'/1` on the goals.
#
# NOT PORTED, each to its owner (docs/architecture.md TX1):
#   * `write_undo_ref`, `save_undo_ref`, `load_undo_ref`: `PL_blob_t` has no hooks (src/pl-dbref.jl header); the blob is
#     written `<undo>(0x…)`, like every blob (upstream: `<undo>(%p)` of the record), and a saved state cannot hold one (no QLF
#     state of a goal).
#   * `acquire_undo_blob` (empty upstream).
#   * a raising undo goal: `'$run_undo'/1` (boot/syspred.pl) calls `'$urgent_exception'/3` for it, owner P3 (the success path runs).

# allow-new-artifact: a port of src/pl-undo.c, read with git show at the pin 18168e629eab (the reference corpus is the pin)

# PORT: pl-undo.c undo_blob
# DIVERGES: no `release`, `write`, `acquire`, `save` or `load` slots (`PL_blob_t` has none): see the file header.
"The blob type of an undo goal (pl-undo.c `undo_blob`): unique by payload, non-text, named `undo`."
const undo_blob = PL_blob_t(PL_BLOB_UNIQUE, "undo")

# PORT: pl-undo.c init_undo_list
# (pl-undo.c:41-52: a global cell holding `[]`, the list's cell, a term reference to it; pl-setup.c:1557 "must be first. See __do_undo()")
# DIVERGES: the list's cell position, not a term reference: `emptyStacks!` allocates it before every other global cell (the
# permanent cells of the exception and attvar term references come after it), so it is global position 1, upstream's `gBase`;
# `Undo!` tests for it by that position.
"Allocate the cell of the undo list on the (empty) global stack and make it `[]`; its position (pl-undo.c `init_undo_list`)."
function init_undo_list(ld::PL_local_data{T})::Int where {T}
    p = allocGlobalCells!(ld, 1)                    # Word p = allocGlobal(1)
    ld.gstack[p] = ld.atom_nil_w                    # p[0] = ATOM_nil
    return p
end

# PORT: pl-undo.c free_undo_data
# DIVERGES: the schedule is a Vector that is emptied, where upstream discards and frees the buffer.
"Forget the scheduled undo goals of `ld` (pl-undo.c `free_undo_data`)."
function free_undo_data(ld::PL_local_data)::Nothing
    empty!(ld.undo_scheduled)                       # discardBuffer(), free()
    return nothing
end

# ORIGINAL: the payload of an undo blob (upstream: the 8 bytes of the `record_t` pointer), as `_recref_bytes`.
"The 8 bytes of an undo blob: the record's number in `gd.undo_refs`, little-endian."
_undo_bytes(serial::Int)::Vector{UInt8} = collect(reinterpret(UInt8, Int64[serial]))

# ORIGINAL: upstream's `*(record_t*)PL_blob_data(aref, NULL, NULL)`.
"The record the undo blob atom word `aref` names."
function undo_blob_record(gd::PL_global_data{T}, aref::word)::record{T} where {T}
    at = atomValue(gd.atoms, aref)
    @assert at.type === undo_blob "undo_blob_record: not an undo blob"
    serial = reinterpret(Int64, at.name[1:8])[1]
    return gd.undo_refs[Int(serial)]
end

# PORT: pl-undo.c release_undo_blob
# DIVERGES: no caller (no atom GC); the atom is the argument; the record is freed by Julia's GC (`PL_erase` does nothing).
"An undo blob is released: erase its record (pl-undo.c)."
function release_undo_blob(gd::PL_global_data{T}, aref::word)::Bool where {T}
    PL_erase(undo_blob_record(gd, aref))            # PL_erase(r)
    return true
end

# PORT: pl-undo.c initUndo
# DIVERGES: the database's atom table is the argument; the type's name atom is made by `PL_register_blob_type`. Called where
# pl-setup.c:151 calls it: after `initDBRef!` and before `initWrap!`, so the type's rank in the standard order is upstream's.
"Register the undo blob type of pl-undo.c in `atoms` (pl-undo.c)."
function initUndo!(atoms::atoms_t)::Nothing
    PL_register_blob_type(atoms, undo_blob)
    return nothing
end

# PORT: pl-undo.c save_undo
# DIVERGES: the record's number in `gd.undo_refs` is the payload (see `undo_blob_record`); the atom's WORD is returned and its
# term is recorded (`_blob_term!`) so that a term over it reads back.
"The undo blob atom of a record of the goal `goal` references (pl-undo.c)."
function save_undo(
    gd::PL_global_data{T}, ld::PL_local_data{T}, goal::term_t
)::word where {T}
    r = PL_record(ld, goal)                         # record_t r = PL_record(goal)
    push!(gd.undo_refs, r)
    bytes = _undo_bytes(length(gd.undo_refs))
    w, _ = lookupBlob(gd.atoms, bytes, length(bytes), undo_blob)   # lookupBlob(&r, sizeof(r), &undo_blob, &new)
    _blob_term!(gd.atoms, gd.atom_symbols, T, w)
    return w
end

# PORT: pl-undo.c put_undo
"Make `t` the goal the undo blob atom `u` records (pl-undo.c)."
function put_undo(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t, u::word
)::Bool where {T}
    return PL_recorded(ld, undo_blob_record(gd, u), t)  # PL_recorded(*ref, t)
end

# PORT: pl-undo.c undo as pl_undo1_va
# (PRED_IMPL("$undo", 1, undo, 0), pl-undo.c:133-157)
# DIVERGES: the room for the three cells and the saved old value of the trailed assignment is ensured first (`ensureGlobalSpace`;
# `allocGlobal` and `TrailAssignment` do it upstream); `*ul` after `deRef` is the cell itself (the list's cell is never a reference).
"`'\$undo'(:Goal)`: run `Goal` when the binding state in which this call succeeded is undone, i.e. on backtracking (pl-undo.c)."
function pl_undo1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0

    if ld.undo_running == 0                         # if ( !LD->undo.running )
        gd = _query_gd(ld)
        u = save_undo(gd, ld, A1)                   # atom_t u = save_undo(A1)

        if ensureGlobalSpace(ld, 4)                 # if ( (p=allocGlobal(3)) )
            p = allocGlobalCells!(ld, 3)
            ul = ld.undo_list                       # Word ul = valTermRef(LD->undo.undo_list); deRef(ul)
            ld.gstack[p] = ld.functor_dot2          # p[0] = FUNCTOR_dot2
            ld.gstack[p + 1] = u                    # p[1] = u
            ld.gstack[p + 2] = ld.gstack[ul]        # p[2] = *ul
            TrailAssignment!(ld, ul)                # TrailAssignment(ul)
            ld.gstack[ul] = consPtr(p, TAG_COMPOUND | STG_GLOBAL)   # *ul = consCompound(p)
            return FTRUE
        else
            return FFALSE
        end
    else
        return if PL_error(
            ld, "", 0, "", ERR_PERMISSION, mk_sym(T, :undo), mk_sym(T, :goal), A1
        )
            FTRUE                          # PL_permission_error("undo", "goal", A1)
        else
            FFALSE                          # PL_permission_error("undo", "goal", A1)
        end                          # PL_permission_error("undo", "goal", A1)
    end
end

# PORT: pl-undo.c push_undo
# DIVERGES: `p` is a global position; the schedule is `ld.undo_scheduled` (a Vector of atom words: no `PL_register_atom`, no atom GC);
# `updateAlerted` is called without the `ALERT_UNDO` test only to set the bit.
"Schedule the undo goals of the list in the cell at `p`, which is being undone, when its head is an undo blob (pl-undo.c)."
function push_undo(ld::PL_local_data, p::Int)::Nothing
    p, w = deRefM(ld, p)                            # deRef(p)
    if isTermW(w)                                   # if ( isTerm(*p) )
        f = valPtr(w)                               # Functor f = valueTerm(*p)
        if ld.gstack[f] == ld.functor_dot2          # if ( f->definition == FUNCTOR_dot2 )
            a = ld.gstack[f + 1]                    # word w = f->arguments[0]
            isAtomW(a) || return nothing            # if ( !isAtom(w) ) return
            push!(ld.undo_scheduled, a)             # PL_register_atom(u); addBuffer(LD->undo.scheduled, u, atom_t)
            if (ld.alerted & ALERT_UNDO) == 0       # if ( !(LD->alerted&ALERT_UNDO) )
                updateAlerted(ld)
            end
        end
    end
    return nothing
end

# PORT: pl-undo.h UNDO_SCHEDULED
"Whether undo goals are waiting to be run (pl-undo.h)."
UNDO_SCHEDULED(ld::PL_local_data)::Bool = !isempty(ld.undo_scheduled)

# PORT: pl-undo.c put_scheduled_undo
# DIVERGES: a failure leaves the schedule as it was (upstream also returns before it empties the buffer).
"Make `list` the list of the scheduled goals, the oldest first, and empty the schedule (pl-undo.c)."
function put_scheduled_undo(
    gd::PL_global_data{T}, ld::PL_local_data{T}, list::term_t
)::Bool where {T}
    PL_put_nil(ld, list)

    sched = ld.undo_scheduled
    if !isempty(sched)                              # if ( LD->undo.scheduled )
        h = PL_new_term_ref(ld)
        for i in length(sched):-1:1                 # for(; top > base; ) { atom_t u = *--top; …
            if !put_undo(gd, ld, h, sched[i]) || !PL_cons_list(ld, list, h, list)
                return false
            end
        end
        empty!(sched)                               # PL_unregister_atom(); emptyBuffer(…, 1024)
    end

    return true
end

# PORT: pl-undo.c run_undo_hooks
# DIVERGES: the procedure is `GD->procedures.drun_undo1`, made by `setBuiltinPredicateProperties!` (src/pl-ext.jl) and not at the first
# call; `'$syspreds'` is the module of boot/syspred.pl. A raising goal is `'$run_undo'/1`'s: named refusal, owner P3 (see the file header).
"Run `'\$syspreds':'\$run_undo'/1` on the scheduled goals in a frame of its own; false with the exception pending (pl-undo.c)."
function run_undo_hooks(gd::PL_global_data{T}, ld::PL_local_data{T})::Bool where {T}
    fid = PL_open_foreign_frame(ld)                 # if ( (fid=PL_open_foreign_frame()) )
    if fid != 0
        pred = gd.procedures_drun_undo1             # _PL_predicate("$run_undo", 1, "$syspreds", &GD->procedures.drun_undo1)

        ld.undo_running += 1                        # LD->undo.running++
        list = PL_new_term_ref(ld)
        rc =
            list != 0 && put_scheduled_undo(gd, ld, list) &&
            PL_call_predicate(gd, ld, nothing, PL_Q_PASS_EXCEPTION, pred, list)
        ld.undo_running -= 1                        # LD->undo.running--

        PL_close_foreign_frame(ld, fid)
        return rc
    end

    return false
end

# PORT: pl-undo.c BeginPredDefs as PL_predicates_from_undo
"pl-undo.c's registration table (`BeginPredDefs(undo)`): `\$undo/1`."
const PL_predicates_from_undo = (
    PL_extension("\$undo", 1, pl_undo1_va, PL_FA_VARARGS),
)
