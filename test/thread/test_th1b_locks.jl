# ORIGINAL: LK-ONLY — the rows of the kernel's L_* lock table (TH1-B): the expected values are the numbers, names and rules of swipl-devel 18168e62's pl-thread.c, pl-thread.h and pl-mutex.h, each testset naming its lines.
# test/thread/test_th1b_locks.jl — the lock table of step TH1-B (design evidence/TH1/design.md §1b, §3, §6.B; ruled D-0789). The kernel
# runs ONE thread; the table is the database's (`gd.mutexes`, DIVERGES: upstream's is the process-wide `_PL_mutexes[]`), and no call site
# takes a lock yet (TH1-C places them). The rows:
#   * the 30 names in upstream's order, the ids (L_MUTEX = 7, L_UMUTEX = 23), the fresh state of a table (pl-thread.c:302-337, pl-thread.h:242-271);
#   * a new database: the table, `thread_enabled` true, the thread counters 1 and 0 (pl-init.c:1609, pl-thread.c:952-953);
#   * lock/unlock pairing and the counters (pl-thread.h:288-309, 325-326), the relock error and the unlock that requires an open hold
#     (DIVERGES: a ReentrantLock and an owner, where upstream's non-recursive mutex would wait for itself);
#   * holdsLock is true while ANY task holds the mutex, and a lock taken while another task holds it counts a collision (pl-thread.h:288-302, 336-340);
#   * IF_MT: while `thread_enabled` is false the lock and unlock of every id but L_THREAD are skipped (pl-thread.h:286);
#   * enableThreads (pl-thread.c:606-634): created - finished == 1 gives true and sets the flag; any other count gives
#     `permission_error(modify, flag, threads)` with the context message `Active threads`, and L_THREAD is released on both paths;
#   * a copy of a database, and a deepcopy of a mutex, own an unlocked table of their own (src/pl-incl.jl `Base.deepcopy_internal`).
# NOT RUN when written (edit-only, 2026-11-15): every row is "UNVERIFIED on the kernel: the gate decides".
using Test, LogicKernel
const LK = LogicKernel
# TERM TYPES PER CHUNK: REFERENCE — the database is built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))

# the payload the booted constructor needs (as test/db/test_gd_template.jl)
const _P = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})

# pl-thread.c:302-337 `_PL_mutexes[]`: ids 0-29, upstream's order (pl-thread.h:242-271)
const _NAMES = [
    "L_MISC", "L_ALLOC", "L_REHASH_ATOMS", "L_FLAG", "L_FUNCTOR", "L_RECORD", "L_THREAD",
    "L_MUTEX", "L_PREDICATE", "L_MODULE", "L_SRCFILE", "L_TABLE", "L_BREAK", "L_FILE",
    "L_SEETELL", "L_PLFLAG", "L_OP", "L_INIT", "L_TERM", "L_FOREIGN", "L_OS", "L_LOCALE",
    "L_SORTR", "L_UMUTEX", "L_INIT_ATOMS", "L_CGCGEN", "L_EVHOOK", "L_OSDIR", "L_ALERT",
    "L_GENERATION"
]

_owner(cm::LK.counting_mutex) = @atomic cm.owner

# a database with no engine: the fresh-state rows and the copies (a database that has an engine holds streams and refuses the copy)
const TMPL = LK.PL_global_data{_P}()
# a database with an engine, whose `GD` is set: the lock rows and enableThreads (a bare engine has `ld.GD === nothing`)
const GDT = LK.PL_global_data{_P}()
const LDT = let ld = LK.PL_local_data{_P}(GDT)
    ld.GD = GDT
    ld
end

# The pending exception of `ld` as `(error/2 shape, formal shape, the three atom arguments of the formal, context shape, the context's message)`.
function _ball(ld::LK.PL_local_data)
    ex = ld.exception_term
    ex == 0 && return nothing
    fid = LK.PL_open_foreign_frame(ld)
    f = LK.PL_new_term_ref(ld)
    c = LK.PL_new_term_ref(ld)
    x = LK.PL_new_term_ref(ld)
    shape(t) = (
        r = LK.PL_get_name_arity(ld, t);
        r === nothing ? nothing : (String(lk_name(r[1])), r[2])
    )
    atom(t) = (
        r = LK.PL_get_atom(ld, t);
        r === nothing ? "?" : String(lk_name(r))
    )
    top = shape(ex)
    LK._PL_get_arg(ld, 1, ex, f)
    LK._PL_get_arg(ld, 2, ex, c)
    formal = shape(f)
    args = String[]
    for i in 1:3
        LK._PL_get_arg(ld, i, f, x)
        push!(args, atom(x))
    end
    ctx = shape(c)
    LK._PL_get_arg(ld, 2, c, x)
    msg = atom(x)
    LK.PL_close_foreign_frame(ld, fid)
    return (top, formal, args, ctx, msg)
end

# ROW r01-r04: the table's names, ids and fresh state
@testset "r01 the 30 names in upstream's order, the ids (pl-thread.c:302-337, pl-thread.h:242-271)" begin
    tbl = LK.new_PL_mutexes()
    @test tbl isa Vector{LK.counting_mutex}
    @test length(tbl) == length(_NAMES) == 30
    @test allunique(_NAMES)
    for (i, n) in enumerate(_NAMES)
        @test tbl[i].name == n
        @test getfield(LK, Symbol(n)) isa Int
        @test getfield(LK, Symbol(n)) == i - 1                      # entry id + 1 is L_*
    end
    @test LK.L_MISC == 0 && LK.L_THREAD == 6 && LK.L_GENERATION == 29
    @test LK.L_MUTEX == 7 && LK.L_UMUTEX == 23                      # index 7 is L_MUTEX, 23 is L_UMUTEX
    @test tbl[LK.L_MUTEX + 1].name == "L_MUTEX"
    @test tbl[LK.L_UMUTEX + 1].name == "L_UMUTEX"
    @test tbl[LK.L_THREAD + 1].name == "L_THREAD"
    @test allunique(objectid(cm) for cm in tbl)                     # thirty objects, thirty locks
    @test allunique(objectid(cm.mutex) for cm in tbl)
    other = LK.new_PL_mutexes()
    @test all(other[i] !== tbl[i] && other[i].mutex !== tbl[i].mutex for i in 1:30)   # a call makes a new table
end

@testset "r02 a fresh table is unlocked and counts nothing (pl-mutex.h:151-159)" begin
    for cm in LK.new_PL_mutexes()
        @test cm.count isa UInt64 && cm.count == 0
        @test cm.lock_count isa UInt32 && cm.lock_count == 0
        @test cm.collisions isa UInt32 && cm.collisions == 0
        @test _owner(cm) === nothing
        @test !islocked(cm.mutex)
    end
    cm = LK.counting_mutex("L_X")
    @test cm.name == "L_X" && cm.count == 0 && cm.lock_count == 0 && _owner(cm) === nothing
end

@testset "r03 a new database: the table, thread_enabled, the counters (pl-init.c:1609, pl-thread.c:952-953)" begin
    for gd in (TMPL, GDT)
        @test gd.mutexes isa Vector{LK.counting_mutex}
        @test [cm.name for cm in gd.mutexes] == _NAMES
        @test gd.thread_enabled === true
        @test gd.statistics_threads_created == 1
        @test gd.statistics_threads_finished == 0
    end
    for cm in TMPL.mutexes
        @test cm.count == 0 && cm.lock_count == 0 && cm.collisions == 0 && !islocked(cm.mutex)
    end
    @test TMPL.mutexes[1] !== GDT.mutexes[1]                        # two databases: two tables
    @test TMPL.mutexes[1].mutex !== GDT.mutexes[1].mutex
end

# ROW r04-r07: lock and unlock
@testset "r04 lock/unlock pairing and counts, per id (pl-thread.h:288-309, 325-326)" begin
    for id in 0:29
        cm = GDT.mutexes[id + 1]
        c0, l0, k0 = cm.count, cm.lock_count, cm.collisions
        @test !LK.holdsLock(GDT, id)
        @test LK.PL_LOCK(GDT, id) === nothing
        @test LK.holdsLock(GDT, id)
        @test cm.count == c0 + 1 && cm.lock_count == l0 + 1 && cm.collisions == k0
        @test islocked(cm.mutex) && _owner(cm) === current_task()
        @test [LK.holdsLock(GDT, j) for j in 0:29] == [j == id for j in 0:29]   # this one only: the id picks entry id + 1
        @test LK.PL_UNLOCK(GDT, id) === nothing
        @test !LK.holdsLock(GDT, id)
        @test cm.count == c0 + 1 && cm.lock_count == l0 && cm.collisions == k0
        @test !islocked(cm.mutex) && _owner(cm) === nothing
    end
end

@testset "r05 repeated pairs add to count, all 30 held at once (pl-thread.h:288-309)" begin
    cm = GDT.mutexes[LK.L_FLAG + 1]
    c0 = cm.count
    for _ in 1:3
        LK.PL_LOCK(GDT, LK.L_FLAG)
        LK.PL_UNLOCK(GDT, LK.L_FLAG)
    end
    @test cm.count == c0 + 3 && cm.lock_count == 0
    before = [x.count for x in GDT.mutexes]
    for id in 0:29
        LK.PL_LOCK(GDT, id)
    end
    @test all(LK.holdsLock(GDT, id) for id in 0:29)
    @test all(x.lock_count == 1 for x in GDT.mutexes)
    @test [x.count for x in GDT.mutexes] == before .+ 1
    for id in 29:-1:0
        LK.PL_UNLOCK(GDT, id)
    end
    @test !any(LK.holdsLock(GDT, id) for id in 0:29)
    @test all(x.lock_count == 0 && !islocked(x.mutex) && _owner(x) === nothing for x in GDT.mutexes)
end

@testset "r06 a relock by the owning task is an error and changes nothing (pl-thread.h:288-302; DIVERGES: upstream's mutex would wait for itself)" begin
    cm = GDT.mutexes[LK.L_MISC + 1]
    LK.PL_LOCK(GDT, LK.L_MISC)
    c0 = cm.count
    e = try
        LK.PL_LOCK(GDT, LK.L_MISC)
        nothing
    catch err
        err
    end
    @test e isa ErrorException
    @test e isa ErrorException && occursin("L_MISC", e.msg) && occursin("already", e.msg)
    @test cm.count == c0 && cm.lock_count == 1 && cm.collisions == 0   # the refused relock counted nothing
    @test LK.holdsLock(GDT, LK.L_MISC) && _owner(cm) === current_task()
    LK.PL_UNLOCK(GDT, LK.L_MISC)
    @test !LK.holdsLock(GDT, LK.L_MISC) && _owner(cm) === nothing
    LK.PL_LOCK(GDT, LK.L_MISC)                                      # the owner is cleared: the lock can be taken again
    @test cm.count == c0 + 1
    LK.PL_UNLOCK(GDT, LK.L_MISC)
end

@testset "r07 an unlock requires an open hold (pl-thread.h:304-309)" begin
    cm = GDT.mutexes[LK.L_MISC + 1]
    e = try
        LK.PL_UNLOCK(GDT, LK.L_MISC)
        nothing
    catch err
        err
    end
    @test e isa AssertionError
    @test e isa AssertionError && occursin("L_MISC", e.msg)
    @test cm.lock_count == 0 && !islocked(cm.mutex) && _owner(cm) === nothing
    @test_throws AssertionError LK.countingMutexUnlock(LK.counting_mutex("L_X"))
end

# ROW r08: holdsLock by any owner, and a collision
@testset "r08 holdsLock is true while another task holds it; a lock taken meanwhile counts a collision (pl-thread.h:288-302, 336-340)" begin
    id = LK.L_ALLOC
    cm = GDT.mutexes[id + 1]
    c0, k0 = cm.count, cm.collisions
    held = Base.Event()
    release = Base.Event()
    t1 = @async begin
        LK.PL_LOCK(GDT, id)
        notify(held)
        wait(release)
        LK.PL_UNLOCK(GDT, id)
    end
    wait(held)
    @test LK.holdsLock(GDT, id)                                     # held by t1, asked by the main task
    @test _owner(cm) === t1 && _owner(cm) !== current_task()
    @test cm.count == c0 + 1 && cm.lock_count == 1 && cm.collisions == k0
    t2 = @async begin
        LK.PL_LOCK(GDT, id)
        LK.PL_UNLOCK(GDT, id)
    end
    @test timedwait(() -> cm.collisions == k0 + 1, 30.0) === :ok    # the collision is counted before the wait
    @test !istaskdone(t2)
    @test cm.lock_count == 1 && _owner(cm) === t1                   # t2 waits: t1's is the only hold
    notify(release)
    wait(t1)
    wait(t2)
    @test cm.count == c0 + 2 && cm.collisions == k0 + 1 && cm.lock_count == 0
    @test !LK.holdsLock(GDT, id) && _owner(cm) === nothing && !islocked(cm.mutex)
end

# ROW r09: IF_MT
@testset "r09 while thread_enabled is false only L_THREAD is taken (pl-thread.h:286, 325-326)" begin
    try
        GDT.thread_enabled = false
        for id in 0:29
            cm = GDT.mutexes[id + 1]
            c0 = cm.count
            LK.PL_LOCK(GDT, id)
            if id == LK.L_THREAD
                @test LK.holdsLock(GDT, id) && cm.count == c0 + 1 && islocked(cm.mutex)
                LK.PL_UNLOCK(GDT, id)
                @test !LK.holdsLock(GDT, id) && cm.count == c0 + 1 && !islocked(cm.mutex)
            else
                @test !LK.holdsLock(GDT, id) && cm.count == c0 && !islocked(cm.mutex)   # the lock was skipped
                LK.PL_UNLOCK(GDT, id)                                                   # and so is the unlock: no refusal
                @test cm.count == c0 && cm.lock_count == 0 && !LK.holdsLock(GDT, id)
            end
        end
    finally
        GDT.thread_enabled = true
    end
    @test GDT.thread_enabled
    LK.PL_LOCK(GDT, LK.L_FLAG)                                      # enabled again: taken
    @test LK.holdsLock(GDT, LK.L_FLAG)
    LK.PL_UNLOCK(GDT, LK.L_FLAG)
end

# ROW r10-r12: enableThreads
@testset "r10 enableThreads: created - finished == 1 gives true and sets the flag (pl-thread.c:606-634)" begin
    cm = GDT.mutexes[LK.L_THREAD + 1]
    try
        @test GDT.statistics_threads_created == 1 && GDT.statistics_threads_finished == 0
        c0 = cm.count
        @test LK.enableThreads(LDT, false) === true
        @test GDT.thread_enabled === false
        @test !LK.holdsLock(GDT, LK.L_THREAD) && !islocked(cm.mutex)   # L_THREAD is taken (also while disabled) and released
        @test cm.count == c0 + 1 && cm.lock_count == 0
        @test LDT.exception_term == 0
        @test LK.enableThreads(LDT, true) === true                  # enabling takes no lock
        @test GDT.thread_enabled === true
        @test cm.count == c0 + 1
        @test LDT.exception_term == 0
    finally
        GDT.thread_enabled = true
    end
end

@testset "r11 enableThreads: the counters decide, created - finished (pl-thread.c:606-634)" begin
    cm = GDT.mutexes[LK.L_THREAD + 1]
    try
        # (created, finished, alone?)
        for (created, finished, alone) in (
            (1, 0, true), (2, 1, true), (5, 4, true), (2, 0, false), (3, 1, false),
            (1, 1, false), (7, 2, false)
        )
            GDT.statistics_threads_created = created
            GDT.statistics_threads_finished = finished
            GDT.thread_enabled = true
            c0 = cm.count
            @test LK.enableThreads(LDT, false) === alone
            @test GDT.thread_enabled === !alone                     # the flag is cleared only when this thread is alone
            @test cm.count == c0 + 1 && cm.lock_count == 0 && !LK.holdsLock(GDT, LK.L_THREAD)   # released on both paths
            @test (LDT.exception_term != 0) === !alone
            LK.PL_clear_exception(LDT)
            @test LDT.exception_term == 0
        end
    finally
        GDT.statistics_threads_created = 1
        GDT.statistics_threads_finished = 0
        GDT.thread_enabled = true
        LK.PL_clear_exception(LDT)
    end
end

@testset "r12 enableThreads: the refusal is permission_error(modify, flag, threads) with the message `Active threads` (pl-thread.c:606-634)" begin
    try
        GDT.statistics_threads_created = 2
        GDT.statistics_threads_finished = 0
        @test _ball(LDT) === nothing
        @test LK.enableThreads(LDT, false) === false
        @test GDT.thread_enabled === true
        @test !LK.holdsLock(GDT, LK.L_THREAD)
        @test _ball(LDT) ==
            (("error", 2), ("permission_error", 3), ["modify", "flag", "threads"], ("context", 2), "Active threads")
        LK.PL_clear_exception(LDT)
        @test _ball(LDT) === nothing
        # the counters back at 1 and 0: the next call answers true, with no exception
        GDT.statistics_threads_created = 1
        @test LK.enableThreads(LDT, false) === true
        @test !LK.holdsLock(GDT, LK.L_THREAD)
    finally
        GDT.statistics_threads_created = 1
        GDT.statistics_threads_finished = 0
        GDT.thread_enabled = true
        LK.PL_clear_exception(LDT)
    end
    ld0 = LK._bare_local_data(TMPL)                                 # an engine with no database: the missing GD is named
    @test ld0.GD === nothing
    @test_throws ErrorException LK.enableThreads(ld0, false)
end

# ROW r13-r14: the copies
@testset "r13 a deepcopy of a mutex is a fresh unlocked one, shared inside one copy (src/pl-incl.jl; DIVERGES from upstream's one process-wide table)" begin
    cm = LK.counting_mutex("L_X")
    LK.countingMutexLock(cm)
    c = deepcopy(cm)
    @test c isa LK.counting_mutex && c !== cm && c.mutex !== cm.mutex
    @test c.name == "L_X"
    @test c.count == 0 && c.lock_count == 0 && c.collisions == 0
    @test _owner(c) === nothing && !islocked(c.mutex)
    @test cm.count == 1 && cm.lock_count == 1 && islocked(cm.mutex) && _owner(cm) === current_task()   # the source is untouched
    LK.countingMutexLock(c)                                         # the copy locks while the source is held, and is no relock
    @test c.lock_count == 1 && cm.lock_count == 1
    LK.countingMutexUnlock(c)
    LK.countingMutexUnlock(cm)
    @test !islocked(cm.mutex) && !islocked(c.mutex)
    v = deepcopy([cm, cm])                                          # one object met twice: one copy
    @test v[1] === v[2] && v[1] !== cm
    @test deepcopy(cm).name == "L_X" && deepcopy(cm) !== deepcopy(cm)
end

@testset "r14 a copy of a database owns its own unlocked table (src/gd_template.jl copy_global_data)" begin
    LK.PL_LOCK(TMPL, LK.L_MISC)
    LK.PL_LOCK(TMPL, LK.L_TABLE)
    try
        TMPL.statistics_threads_created = 4
        TMPL.statistics_threads_finished = 1
        c = LK.copy_global_data(TMPL)
        @test c.mutexes !== TMPL.mutexes && length(c.mutexes) == 30
        @test [cm.name for cm in c.mutexes] == _NAMES
        for i in 1:30
            @test c.mutexes[i] !== TMPL.mutexes[i] && c.mutexes[i].mutex !== TMPL.mutexes[i].mutex
            @test c.mutexes[i].count == 0 && c.mutexes[i].lock_count == 0 && c.mutexes[i].collisions == 0
            @test !islocked(c.mutexes[i].mutex) && _owner(c.mutexes[i]) === nothing
        end
        @test LK.holdsLock(TMPL, LK.L_MISC) && LK.holdsLock(TMPL, LK.L_TABLE)   # the source keeps its holds
        @test !LK.holdsLock(c, LK.L_MISC) && !LK.holdsLock(c, LK.L_TABLE)
        @test c.thread_enabled === TMPL.thread_enabled
        @test c.statistics_threads_created == 4 && c.statistics_threads_finished == 1   # the counters are copied
        LK.PL_LOCK(c, LK.L_MISC)                                    # the copy takes it while the source holds its own: no relock
        @test LK.holdsLock(c, LK.L_MISC) && c.mutexes[1].count == 1
        LK.PL_UNLOCK(c, LK.L_MISC)
        @test !LK.holdsLock(c, LK.L_MISC) && LK.holdsLock(TMPL, LK.L_MISC)
    finally
        TMPL.statistics_threads_created = 1
        TMPL.statistics_threads_finished = 0
        LK.PL_UNLOCK(TMPL, LK.L_TABLE)
        LK.PL_UNLOCK(TMPL, LK.L_MISC)
    end
    @test !LK.holdsLock(TMPL, LK.L_MISC) && !LK.holdsLock(TMPL, LK.L_TABLE)
end
