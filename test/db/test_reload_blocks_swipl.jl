# ORIGINAL: R2's LB6a gate — the reconsult half of pl-srcfile.c (startReconsultFile, reloadContext, the reload arms of assertProcedureSource, setAttrProcedureSource and setMetapredicateSource, the clause matching, the reload visibility of pl-inline.h) as WHITE-BOX rows; upstream tests it through Prolog (test_reload.pl), which needs the second consult LB6b re-points.
# test/db/test_reload_blocks_swipl.jl — LB6a's rows (evidence/LB6/plan.md section 3, audit D-0415). LB6a is dead code until LB6b's last commit re-points
# `startConsult`, so these rows call the functions directly: `startReconsultFile`, `reloadContext`, `assertProcedureSource` on a reload that is set up by hand,
# `setAttrProcedureSource`, `setMetapredicateSource`, `fix_*`, `check_ssu`, `equal_clause`, `find_clause`/`advance_clause`, `visibleClause`, and the search
# (`firstClause!`/`nextClause!`) and the database-only functions (`hasClausesDefinition`, `num_visible_clauses`, `getClauses`) while a reload runs.
# The swipl-compared reload rows (exports, clause lists, `source_file_property` after a second consult) are LB6b's (test/db/test_reload_swipl.jl).
# EXPECTED VALUES: swipl cannot be asked about a Julia call, so every value below is hand-derived from the upstream code (pl-srcfile.c:889-1405 at cbf4e189,
# pl-inline.h:655-680) and carries the upstream line it follows; where swipl itself answers (the flags `P_MODIFIED`/`P_RELOADING` share one bit: pl-incl.h:1127)
# the comment says so. EVERY ROW IS "UNVERIFIED on the kernel: gate decides": the writer had no daemon (LB6a piece 4, 2026-11-05).
# NON-VACUITY: each group first asserts the state its comparison starts from (a clause erased at the reload generation, a flag set, a list with two sides) and
# compares through ONE extractor (`_rb_list`, `_rb_refs`), so a guard that cannot pass or cannot fail shows as a failed precondition.
using Test, LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "index_testlib.jl"))        # IxDB: a database's global and local data
const LK = LogicKernel
const _RB = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}, Bool})

# ---- term and database builders (every term-building helper takes the term type)
_rb_expr(::Type{T}, f::Symbol, xs::T...) where {T} = mk_expr(T, T[lk_sym(T, f), xs...])
_rb_int(::Type{T}, n::Integer) where {T} = lk_gnd(T, Int64(n))
_rb_p(::Type{T}, name::Symbol, n::Integer) where {T} = _rb_expr(T, name, _rb_int(T, n))

"The procedure `name/arity` of the user module, created when absent."
_rb_proc(db::IxDB{T}, name::Symbol, arity::Int) where {T} =
    LK.lookupProcedure(lk_sym(T, name), arity, LK.MODULE_user(db.gd))

"The CURRENT procedure `name/arity` of the user module (an error when there is none)."
function _rb_cur(db::IxDB{T}, name::Symbol, arity::Int)::LK.Procedure{T} where {T}
    proc = LK.isCurrentProcedure(sym_key(lk_sym(T, name)), arity, LK.MODULE_user(db.gd))
    proc === nothing && error("no procedure $name/$arity")
    return proc
end

"The source file called `name`, created when absent (one reference is the caller's)."
_rb_sf(db::IxDB{T}, name::String) where {T} =
    LK.lookupSourceFile(db.gd, lk_sym(T, Symbol(name)), true)::LK.SourceFile{T}

"""
A clause for `head` of `proc` as `assert_term!` leaves a loaded one: its source file `sf`, its owner `owner` (default `sf`), the line `line`, and the reference to each file
that `freeClause!`/`copy_clause_source` give back.
"""
function _rb_clause(
    db::IxDB{T}, sf::LK.SourceFile{T}, proc::LK.Procedure{T}, head::T; body::Union{Nothing, T}=nothing,
    flags::UInt32=UInt32(0), line::Integer=1, owner::LK.SourceFile{T}=sf
)::LK.Clause{T} where {T}
    cl = LK.compileClause(db.gd, db.ld, head, body, proc, LK.MODULE_user(db.gd), 0, flags)
    cl === nothing && error("compileClause refused the clause")
    cl.line_no = UInt32(line)
    cl.source_no = UInt32(sf.index)
    cl.owner_no = UInt32(owner.index)
    LK.acquireSourceFile(sf)
    owner === sf || LK.acquireSourceFile(owner)
    return cl
end

"Add the clauses with the heads `heads` to `proc` for the file `sf` in the first-load way (`assertProcedureSource` with no reload); the clauses, in order."
function _rb_old!(
    db::IxDB{T}, sf::LK.SourceFile{T}, proc::LK.Procedure{T}, heads::Vector{T}; owner::LK.SourceFile{T}=sf
)::Vector{LK.Clause{T}} where {T}
    LK.addProcedureSourceFile(sf, proc)
    out = LK.Clause{T}[]
    for h in heads
        cl = _rb_clause(db, sf, proc, h; owner=owner)
        cref = LK.assertProcedureSource(db.gd, db.ld, sf, proc, cl)
        (cref !== nothing && cref.clause === cl) || error("the clause was not added")
        push!(out, cl)
    end
    return out
end

"The clauses of `def`, in list order (the one extractor of the rows)."
function _rb_list(def::LK.Definition{T})::Vector{LK.Clause{T}} where {T}
    out = LK.Clause{T}[]
    c = def.impl_clauses.first_clause
    while c !== nothing
        push!(out, c.clause::LK.Clause{T})
        c = c.next
    end
    return out
end

"The clause references of `def`, in list order."
function _rb_refs(def::LK.Definition{T})::Vector{LK.ClauseRef{T}} where {T}
    out = LK.ClauseRef{T}[]
    c = def.impl_clauses.first_clause
    while c !== nothing
        push!(out, c)
        c = c.next
    end
    return out
end

"Are `a` and `b` the same clauses, element by element, by identity?"
_rb_same(a::Vector{<:LK.Clause}, b::Vector{<:LK.Clause}) = length(a) == length(b) && all(i -> a[i] === b[i], eachindex(a))

"The metas of an argument-mask vector."
_rb_metas(v::Vector{LK.arg_info}) = UInt8[a.meta for a in v]

"An argument-mask vector with the metas `ms`."
function _rb_args(ms::UInt8...)::Vector{LK.arg_info}
    out = LK.arg_info[]
    for m in ms
        a = LK.arg_info()
        a.meta = m
        push!(out, a)
    end
    return out
end

"What `endReconsult` (LB6b) does to the three values `startReconsultFile` writes."
function _rb_end!(db::IxDB)::Nothing
    db.ld.reload_generation = LK.GEN_INVALID
    db.gd.reload_generation = LK.GEN_INVALID
    db.ld.reload_nesting = 0
    return nothing
end

"A reload set up by hand: file `sf` with `proc` (`name/1`), the old clauses `p(1)..p(n)`, and `startReconsultFile` done."
function _rb_scene(::Type{T}, name::Symbol, n::Integer; multifile::Bool=false) where {T}
    db = IxDB{T}()
    sf = _rb_sf(db, "/lb6a/$(name).pl")
    proc = _rb_proc(db, name, 1)
    multifile && (proc.definition.flags |= LK.P_MULTIFILE)
    olds = _rb_old!(db, sf, proc, T[_rb_p(T, name, i) for i in 1:n])
    @assert all(cl -> cl.generation_erased == LK.GEN_MAX, olds)        # live before the reload
    LK.startReconsultFile(db.gd, db.ld, sf)
    return (db=db, sf=sf, proc=proc, def=proc.definition, olds=olds)
end

# ---- the loaded program: file A (static, multifile, dynamic) and file B (a second multifile owner)
const _FA = """
:- multifile mf/1.
:- dynamic dy/1.
s1(1).
s1(2).
s2(a).
mf(1).
mf(2).
dy(10).
q(1).
q(2).
q(3).
"""
const _FB = ":- multifile mf/1.\nmf(20).\n"

function _rb_loaded(::Type{T}) where {T}
    db = IxDB{T}()
    d = realpath(mktempdir())
    sfs = LK.SourceFile{T}[]
    for (nm, src) in (("a.pl", _FA), ("b.pl", _FB))
        f = joinpath(d, nm)
        write(f, src)
        st, ball = LK.load_file!(db.gd, db.ld, f)
        st === :ok || error("load_file! $nm: $st")
        sf = LK.lookupSourceFile(db.gd, lk_sym(T, Symbol(f)), false)
        sf === nothing && error("no source file for $nm")
        push!(sfs, sf)
    end
    return db, sfs[1], sfs[2]
end

# ========================================================================================================
# r01-r04: startReconsultFile (pl-srcfile.c:900-953)
# ========================================================================================================
@testset "r01-r04 startReconsultFile: the file's clauses are erased at the reload generation, the others stay; flags; counters" begin
    db, sfA, sfB = _rb_loaded(_RB)
    gd, ld = db.gd, db.ld
    s1, s2 = _rb_cur(db, :s1, 1), _rb_cur(db, :s2, 1)
    mf, dy, q = _rb_cur(db, :mf, 1), _rb_cur(db, :dy, 1), _rb_cur(db, :q, 1)
    # a run-time clause of the dynamic predicate: owner_no 0 (assertz, not the loader)
    rt = LK.compileClause(gd, ld, _rb_p(_RB, :dy, 99), nothing, dy, LK.MODULE_user(gd))
    LK.assertDefinition!(gd, ld, dy.definition, rt, LK.CL_END)
    # the state the comparison starts from: every clause live; the procedures of A are recorded; the flags to be cleared are set
    allcl = vcat(_rb_list(s1.definition), _rb_list(s2.definition), _rb_list(mf.definition), _rb_list(dy.definition), _rb_list(q.definition))
    @test length(allcl) == 2 + 1 + 3 + 2 + 3 && all(cl -> cl.generation_erased == LK.GEN_MAX, allcl)
    @test s1 in sfA.procedures && s2 in sfA.procedures && mf in sfA.procedures && dy in sfA.procedures && q in sfA.procedures
    @test sfA.index != sfB.index && sfA.reload === nothing
    @test ld.reload_generation == LK.GEN_INVALID && gd.reload_generation == LK.GEN_INVALID && ld.reload_nesting == 0
    for proc in sfA.procedures
        proc.definition.flags |= LK.P_DISCONTIGUOUS | LK.P_AUTOLOAD
    end
    gen0 = LK.global_generation(gd)

    @test LK.startReconsultFile(gd, ld, sfA)

    # r01: the file's static clauses are erased at the reload generation (A1: not at the global generation)
    for p in (s1, s2, q)
        cls = _rb_list(p.definition)
        @test !isempty(cls) && all(cl -> cl.generation_erased == LK.GEN_RELOAD && cl.owner_no == sfA.index, cls)
    end
    @test LK.GEN_RELOAD == LK.GEN_MAX - 1 && LK.global_generation(gd) == gen0         # nothing moved the database's generation
    # r02: a multifile predicate: A's clauses are marked, B's clause (another owner) is not (A2)
    mfc = _rb_list(mf.definition)
    @test length(mfc) == 3
    @test count(cl -> cl.owner_no == sfA.index, mfc) == 2 && count(cl -> cl.owner_no == sfB.index, mfc) == 1
    for cl in mfc
        if cl.owner_no == sfA.index
            @test cl.generation_erased == LK.GEN_RELOAD
        else
            @test cl.generation_erased == LK.GEN_MAX
        end
    end
    # r03: a dynamic predicate: the file's clause is marked, the run-time clause (owner_no 0) is not (A3)
    dyc = _rb_list(dy.definition)
    @test length(dyc) == 2 && count(cl -> cl.owner_no == 0, dyc) == 1 && count(cl -> cl.owner_no == sfA.index, dyc) == 1
    for cl in dyc
        @test cl.generation_erased == (cl.owner_no == 0 ? LK.GEN_MAX : LK.GEN_RELOAD)
    end
    @test rt.generation_erased == LK.GEN_MAX
    # r04: the flags and counters (A4, A5, A6, A6b)
    for proc in sfA.procedures
        fl = proc.definition.flags
        @test (fl & LK.P_RELOADING) != 0 && (fl & LK.P_DISCONTIGUOUS) == 0 && (fl & LK.P_AUTOLOAD) == 0
    end
    @test LK.P_RELOADING == LK.P_MODIFIED                              # one bit, pl-incl.h:1127 (swipl's own alias)
    rl = sfA.reload
    @test rl !== nothing && rl.reload_gen == LK.GEN_RELOAD && isempty(rl.procedures) && isempty(rl.modules) && rl.number_of_clauses == 0
    @test ld.reload_generation == LK.GEN_RELOAD && gd.reload_generation == LK.GEN_RELOAD
    @test ld.reload_nesting == 1
    # nesting 2 after a second start (another file; the C counter, `endReconsult` decrements it in LB6b)
    @test LK.startReconsultFile(gd, ld, sfB)
    @test ld.reload_nesting == 2 && sfB.reload !== nothing && sfB.reload !== rl
    # B's own clause is now marked, A's marks are untouched
    @test all(cl -> cl.generation_erased == (cl.owner_no == 0 ? LK.GEN_MAX : LK.GEN_RELOAD), _rb_list(dy.definition))
    @test count(cl -> cl.generation_erased == LK.GEN_RELOAD, _rb_list(mf.definition)) == 3
    _rb_end!(db)
end

# r04b (audit D-0416 item 3, LB6a Q6): two files reloading IN TURN: the generation after each. One source of truth: `startReconsultFile` writes the value (the
# local data's `LD->reload.generation` and the global stand-in `gd.reload_generation`, owner TH1), `endReconsult` (LB6b; here `_rb_end!`, the same three writes)
# clears it, and nothing keeps a copy that outlives the file. `endReconsult` does not exist before LB6b, so the row calls `_rb_end!`, the helper that does what it does
# to these values; the stale value between the files is planted by hand because the generation is the constant GEN_RELOAD and a stale copy would otherwise read the same.
@testset "r04b two files reloading in turn: the reload generation after each start and each end" begin
    db = IxDB{_RB}()
    gd, ld = db.gd, db.ld
    sfA = _rb_sf(db, "/lb6a/turn_a.pl")
    sfB = _rb_sf(db, "/lb6a/turn_b.pl")
    @test sfA.index != sfB.index && sfA.reload === nothing && sfB.reload === nothing
    @test gd.reload_generation == LK.GEN_INVALID && ld.reload_generation == LK.GEN_INVALID && ld.reload_nesting == 0
    # file A: started, the generation is the reload generation on both sides; ended, it is gone
    @test LK.startReconsultFile(gd, ld, sfA)
    @test gd.reload_generation == LK.GEN_RELOAD && ld.reload_generation == LK.GEN_RELOAD && ld.reload_nesting == 1
    @test sfA.reload !== nothing && sfA.reload.reload_gen == gd.reload_generation
    _rb_end!(db)
    @test gd.reload_generation == LK.GEN_INVALID && ld.reload_generation == LK.GEN_INVALID && ld.reload_nesting == 0
    # a stale value left in the local data between the files (the thing a second copy would be): file B's start overwrites it, so the two agree
    stale = LK.gen_t(7)
    @test stale != LK.GEN_RELOAD && stale != LK.GEN_INVALID
    ld.reload_generation = stale
    @test LK.startReconsultFile(gd, ld, sfB)
    @test gd.reload_generation == LK.GEN_RELOAD && ld.reload_generation == LK.GEN_RELOAD && ld.reload_nesting == 1
    @test sfB.reload !== nothing && sfB.reload !== sfA.reload && sfB.reload.reload_gen == gd.reload_generation
    @test ld.reload_generation == gd.reload_generation                              # one value, read through either name
    _rb_end!(db)
    @test gd.reload_generation == LK.GEN_INVALID && ld.reload_generation == LK.GEN_INVALID && ld.reload_nesting == 0
end

# ========================================================================================================
# r05-r07: visibility during a reload (pl-inline.h:655-680)
# ========================================================================================================
@testset "r05-r07 visibleClause: erased at the reload generation is invisible, created at it is visible; outside a reload nothing changes" begin
    db = IxDB{_RB}()
    sf = _rb_sf(db, "/lb6a/vis.pl")
    proc = _rb_proc(db, :v, 1)
    cl = _rb_clause(db, sf, proc, _rb_p(_RB, :v, 1))
    ld = db.ld
    g = LK.gen_t(20)                                          # a database generation, the clauses below are placed relative to it
    R = LK.GEN_RELOAD
    # the plain rule (rgen == GEN_INVALID): created <= gen < erased
    cl.generation_created = LK.gen_t(3); cl.generation_erased = LK.GEN_MAX
    @test LK.visibleClause(cl, g, LK.GEN_INVALID)
    @test LK.visibleClause(cl, g, R)                                  # an ordinary live clause stays visible during a reload
    # r05: erased at the reload generation: invisible during the reload (A7), visible by the plain rule (the control: both sides)
    cl.generation_created = LK.gen_t(3); cl.generation_erased = R
    @test LK.visibleClause(cl, g, LK.GEN_INVALID)
    @test !LK.visibleClause(cl, g, R)
    @test !LK.visibleClauseCNT(cl, g, R)
    # r06: created at the reload generation: visible during the reload (A8), invisible by the plain rule
    cl.generation_created = R; cl.generation_erased = LK.GEN_MAX
    @test !LK.visibleClause(cl, g, LK.GEN_INVALID)
    @test LK.visibleClause(cl, g, R)
    # a clause erased at an ordinary generation stays invisible, a clause created in the future likewise
    cl.generation_created = LK.gen_t(3); cl.generation_erased = LK.gen_t(7)
    @test !LK.visibleClause(cl, g, R) && !LK.visibleClause(cl, g, LK.GEN_INVALID)
    cl.generation_created = LK.gen_t(30); cl.generation_erased = LK.GEN_MAX
    @test !LK.visibleClause(cl, g, R) && !LK.visibleClause(cl, g, LK.GEN_INVALID)
    # r07: the `ld` form reads ld.reload_generation: outside a reload it is the plain rule, inside it the reload rule
    cl.generation_created = LK.gen_t(3); cl.generation_erased = R
    @test ld.reload_generation == LK.GEN_INVALID
    @test LK.visibleClause(ld, cl, g) && LK.visibleClauseCNT(ld, cl, g)
    ld.reload_generation = R
    @test !LK.visibleClause(ld, cl, g) && !LK.visibleClauseCNT(ld, cl, g)
    ld.reload_generation = LK.GEN_INVALID
    # STATIC_RELOADING (pl-index.c:159-160): static and reloading only
    dyn = _rb_proc(db, :vd, 1)
    LK.setDynamicDefinition!(dyn.definition, true)
    @test LK.STATIC_RELOADING(R, proc.definition) && !LK.STATIC_RELOADING(R, dyn.definition)      # A9
    @test !LK.STATIC_RELOADING(LK.GEN_INVALID, proc.definition)
end

# ========================================================================================================
# Q1 (D-0415 item 1): a reload started between two solutions of a search changes what the second solution sees
# ========================================================================================================
@testset "Q1 a reload started between two solutions of a static search: the second solution sees the reload" begin
    db, sfA, sfB = _rb_loaded(_RB)
    gd, ld = db.gd, db.ld
    q = _rb_cur(db, :q, 1)
    def = q.definition
    LK.reconsiderIndexes!(def)
    LK.update_primary_index!(def)
    goal = _rb_expr(_RB, :q, lk_var(_RB, UInt64(1)))
    gen = LK.global_generation(gd)
    # the control: the same search with no reload meets the three clauses
    n_plain = Ref(0)
    ix_with_argv(ld, goal) do argv
        chp = LK.ClauseChoice{_RB}(nothing, LK.word(0))
        c = LK.firstClause!(ld, argv, gen, def, chp)
        while c !== nothing
            n_plain[] += 1
            chp.cref === nothing && break
            c = LK.nextClause!(ld, chp, argv, gen, def)
        end
    end
    @test n_plain[] == 3
    # the search: first solution, then the reload starts, then the second
    first_found = Ref(false)
    more_before = Ref(false)
    second = Ref{Union{Nothing, LK.ClauseRef{_RB}}}(_rb_refs(def)[1])   # a marker that is not `nothing`
    ix_with_argv(ld, goal) do argv
        chp = LK.ClauseChoice{_RB}(nothing, LK.word(0))
        c = LK.firstClause!(ld, argv, gen, def, chp)
        first_found[] = c !== nothing
        more_before[] = chp.cref !== nothing
        @test ld.reload_generation == LK.GEN_INVALID                 # the first call ran with no reload
        LK.startReconsultFile(gd, ld, sfA)                           # q's clauses are now erased at the reload generation
        second[] = LK.nextClause!(ld, chp, argv, gen, def)           # redo: the value is read again at this entry (A21)
    end
    @test first_found[] && more_before[]
    @test second[] === nothing                                       # q(2) and q(3) are erased at the reload generation: invisible now
    @test all(cl -> cl.generation_erased == LK.GEN_RELOAD, _rb_list(def))     # the precondition of "invisible": the clauses ARE marked
    _rb_end!(db)
end

# ========================================================================================================
# Q6 (D-0415, handoff QUESTION 6): the database-only functions read the reload generation through `gd`
# ========================================================================================================
@testset "Q6 hasClausesDefinition, num_visible_clauses, getClauses and isDefinedProcedure during a reload" begin
    db, sfA, sfB = _rb_loaded(_RB)
    gd, ld = db.gd, db.ld
    q = _rb_cur(db, :q, 1)
    def = q.definition
    refs = LK.ClauseRef{_RB}[]
    # outside a reload: the clean fast path / the flag count (A10, A10b, A10c: the other side)
    @test LK.hasClausesDefinition(gd, def) === def.impl_clauses.first_clause
    @test LK.num_visible_clauses(gd, def, false) == 3
    @test LK.getClauses(gd, def, refs, 10) == 3 && length(refs) == 3
    @test LK.isDefinedProcedure(gd, q)
    LK.startReconsultFile(gd, ld, sfA)
    @test all(cl -> cl.generation_erased == LK.GEN_RELOAD, _rb_list(def))          # precondition: every clause of q is marked
    # during: a static predicate whose clauses are all erased at the reload generation has none visible
    @test LK.hasClausesDefinition(gd, def) === nothing                              # A10
    @test LK.num_visible_clauses(gd, def, false) == 0                                # A10b
    @test LK.num_visible_clauses(gd, def, true) == 0
    @test LK.getClauses(gd, def, refs, 10) == 0 && isempty(refs)                    # A10c
    @test !LK.isDefinedProcedure(gd, q)
    # a clause created at the reload generation IS visible: hand-made, in a predicate of the file
    sf = sfA
    cl = _rb_clause(db, sf, q, _rb_p(_RB, :q, 4))
    cref = LK.assertProcedure!(gd, ld, q, cl, LK.CL_END)
    cl.generation_created = LK.GEN_RELOAD                                            # what assertProcedureSource does for an inserted clause
    @test cref !== nothing
    @test LK.hasClausesDefinition(gd, def) === cref
    @test LK.num_visible_clauses(gd, def, false) == 1
    @test LK.getClauses(gd, def, refs, 10) == 1 && refs[1] === cref
    _rb_end!(db)
    # after the end: the marks are gone with the generation, the other clauses are live again (the flag count is 4: the hand-made clause counts)
    @test LK.getClauses(gd, def, refs, 10) == 3
end

# ========================================================================================================
# r08-r13: the assert path with a hand-built reload (pl-srcfile.c:1108-1204)
# ========================================================================================================
@testset "r08-r10 assertProcedureSource: keep an equal clause, insert before a different one, skip forward to an equal one" begin
    s = _rb_scene(_RB, :p, 3)
    db, sf, proc, def, olds = s.db, s.sf, s.proc, s.def, s.olds
    gd, ld = db.gd, db.ld
    @test all(cl -> cl.generation_erased == LK.GEN_RELOAD, olds)                      # started: every old clause is marked
    @test !LK.reloadHasClauses(sf, proc)                                               # nothing seen yet
    # r08: p(1) equals the first old clause: that clause is kept
    refs0 = sf.references
    new1 = _rb_clause(db, sf, proc, _rb_p(_RB, :p, 1); line=77)
    refs1 = sf.references
    @test refs1 == refs0 + 1                                                           # the new clause holds a reference
    cref = LK.assertProcedureSource(gd, ld, sf, proc, new1)
    reload = sf.reload.procedures[proc]
    @test cref !== nothing && cref.clause === olds[1]                                  # the OLD clause object is in the list
    @test olds[1].generation_erased == LK.GEN_MAX                                      # live again (A11)
    @test olds[1].line_no == 77                                                        # source position copied (A12b)
    @test _rb_same(_rb_list(def), olds) && def.impl_clauses.number_of_clauses == 3     # the new clause was dropped
    @test reload.current_clause !== nothing && reload.current_clause.clause === olds[2]
    @test (reload.flags & LK.P_MODIFIED) == 0                                          # nothing changed: not modified
    @test sf.references == refs1 - 1                                                   # the new clause's reference is given back (freeClause!)
    @test sf.reload.number_of_clauses == 1 && reload.number_of_clauses == 1             # A31
    @test LK.reloadHasClauses(sf, proc)
    @test (reload.flags & (LK.P_NEW | LK.P_NO_CLAUSES)) == 0                           # p is redefined, not new (A16)
    @test olds[2].generation_erased == LK.GEN_RELOAD && olds[3].generation_erased == LK.GEN_RELOAD   # the rest still waits
    # r09: p(9) differs from the current clause (p(2)) and from every later one: inserted BEFORE p(2)
    new2 = _rb_clause(db, sf, proc, _rb_p(_RB, :p, 9))
    cref = LK.assertProcedureSource(gd, ld, sf, proc, new2)
    @test cref !== nothing && cref.clause === new2
    @test _rb_same(_rb_list(def), [olds[1], new2, olds[2], olds[3]])
    @test new2.generation_created == LK.GEN_RELOAD && new2.generation_erased == LK.GEN_MAX      # A14
    @test (reload.flags & LK.P_MODIFIED) != 0                                          # A15b
    @test reload.current_clause.clause === olds[2]
    # r10: p(3) differs from the current clause but equals a later one: the clause between stays marked, p(3) is kept
    new3 = _rb_clause(db, sf, proc, _rb_p(_RB, :p, 3))
    cref = LK.assertProcedureSource(gd, ld, sf, proc, new3)
    @test cref !== nothing && cref.clause === olds[3]
    @test olds[3].generation_erased == LK.GEN_MAX
    @test olds[2].generation_erased == LK.GEN_RELOAD                                   # skipped: endReconsult (LB6b) deletes it
    @test reload.current_clause === nothing                                            # the list is exhausted
    @test _rb_same(_rb_list(def), [olds[1], new2, olds[2], olds[3]])
    @test sf.reload.number_of_clauses == 3 && reload.number_of_clauses == 3
    _rb_end!(db)
end

@testset "r11 assertProcedureSource: append at an exhausted list sets P_MODIFIED (the flag clear before)" begin
    s = _rb_scene(_RB, :p, 1)
    db, sf, proc, def, olds = s.db, s.sf, s.proc, s.def, s.olds
    gd, ld = db.gd, db.ld
    c1 = _rb_clause(db, sf, proc, _rb_p(_RB, :p, 1))
    @test LK.assertProcedureSource(gd, ld, sf, proc, c1).clause === olds[1]
    reload = sf.reload.procedures[proc]
    @test reload.current_clause === nothing && (reload.flags & LK.P_MODIFIED) == 0     # the precondition: exhausted, unmodified
    c2 = _rb_clause(db, sf, proc, _rb_p(_RB, :p, 2))
    cref = LK.assertProcedureSource(gd, ld, sf, proc, c2)
    @test cref !== nothing && cref.clause === c2
    @test _rb_same(_rb_list(def), [olds[1], c2])                                       # at the end
    @test c2.generation_created == LK.GEN_RELOAD && c2.generation_erased == LK.GEN_MAX
    @test (reload.flags & LK.P_MODIFIED) != 0                                          # A15
    _rb_end!(db)
end

@testset "r12 assertProcedureSource: a predicate with no visible clause is P_NEW; its clauses are added as in a first load" begin
    s = _rb_scene(_RB, :p, 2)
    db, sf, gd, ld = s.db, s.sf, s.db.gd, s.db.ld
    nw = _rb_proc(db, :nw, 1)
    @test !LK.isRedefinedProcedure(nw, LK.global_generation(gd))
    cl = _rb_clause(db, sf, nw, _rb_p(_RB, :nw, 1))
    cref = LK.assertProcedureSource(gd, ld, sf, nw, cl)
    reload = sf.reload.procedures[nw]
    @test cref !== nothing && cref.clause === cl
    @test (reload.flags & LK.P_NEW) != 0 && (reload.flags & LK.P_NO_CLAUSES) == 0 && reload.current_clause === nothing    # A16
    @test cl.generation_created != LK.GEN_RELOAD && cl.generation_created == LK.global_generation(gd)   # no reload generation for a new predicate
    @test LK.isRedefinedProcedure(nw, LK.global_generation(gd))                          # now it has a clause
    # the redefined one is not new (the other side of A16)
    cl2 = _rb_clause(db, sf, s.proc, _rb_p(_RB, :p, 1))
    LK.assertProcedureSource(gd, ld, sf, s.proc, cl2)
    @test (sf.reload.procedures[s.proc].flags & LK.P_NEW) == 0
    _rb_end!(db)
end

@testset "r13 reloadContext: a foreign or thread-local predicate gets P_NO_CLAUSES; the record is made once" begin
    s = _rb_scene(_RB, :p, 1)
    db, sf, gd, ld = s.db, s.sf, s.db.gd, s.db.ld
    fp = _rb_proc(db, :fp, 1)
    fp.definition.flags |= LK.P_FOREIGN
    r = LK.reloadContext(gd, ld, sf, fp)
    @test (r.flags & LK.P_NO_CLAUSES) != 0 && (r.flags & LK.P_NEW) == 0 && r.current_clause === nothing
    @test LK.reloadContext(gd, ld, sf, fp) === r && sf.reload.procedures[fp] === r
    @test !LK.reloadHasClauses(sf, fp)                                                  # a record with no clause seen
    tp = _rb_proc(db, :tp, 1)
    tp.definition.flags |= LK.P_THREAD_LOCAL
    @test (LK.reloadContext(gd, ld, sf, tp).flags & LK.P_NO_CLAUSES) != 0
    # the ordinary predicate, for the contrast: its record has a generation and a current clause
    r0 = LK.reloadContext(gd, ld, sf, s.proc)
    @test (r0.flags & LK.P_NO_CLAUSES) == 0 && r0.current_clause !== nothing && r0.current_clause.clause === s.olds[1]
    @test r0.generation == LK.global_generation(gd) && r0.predicate === s.def
    @test !isempty(ld.predicate_references)                                              # pushPredicateAccessObj! for the redefined predicate
    _rb_end!(db)
end

@testset "A19 the skip-forward scan of a multifile predicate ignores another file's equal clause" begin
    db = IxDB{_RB}()
    gd, ld = db.gd, db.ld
    sf = _rb_sf(db, "/lb6a/m_ours.pl")
    sfO = _rb_sf(db, "/lb6a/m_other.pl")
    proc = _rb_proc(db, :m, 1)
    proc.definition.flags |= LK.P_MULTIFILE
    LK.addProcedureSourceFile(sf, proc)
    m1 = _rb_clause(db, sf, proc, _rb_p(_RB, :m, 1)); LK.assertProcedureSource(gd, ld, sf, proc, m1)
    m5 = _rb_clause(db, sfO, proc, _rb_p(_RB, :m, 5)); LK.assertProcedureSource(gd, ld, sfO, proc, m5)
    m2 = _rb_clause(db, sf, proc, _rb_p(_RB, :m, 2)); LK.assertProcedureSource(gd, ld, sf, proc, m2)
    @test _rb_same(_rb_list(proc.definition), [m1, m5, m2]) && m1.owner_no == sf.index && m5.owner_no == sfO.index
    LK.startReconsultFile(gd, ld, sf)
    @test m1.generation_erased == LK.GEN_RELOAD && m5.generation_erased == LK.GEN_MAX && m2.generation_erased == LK.GEN_RELOAD
    new5 = _rb_clause(db, sf, proc, _rb_p(_RB, :m, 5))
    cref = LK.assertProcedureSource(gd, ld, sf, proc, new5)
    @test cref !== nothing && cref.clause === new5                                       # NOT the other file's m(5)
    @test m5.generation_erased == LK.GEN_MAX && m5.owner_no == sfO.index
    @test _rb_same(_rb_list(proc.definition), [new5, m1, m5, m2])
    _rb_end!(db)
end

# ========================================================================================================
# r14-r16: find_clause, advance_clause, reloadHasClauses, isRedefinedProcedure on lists with erased and invisible clauses
# ========================================================================================================
@testset "r14-r16 find_clause, advance_clause, isRedefinedProcedure, reloadHasClauses" begin
    db = IxDB{_RB}()
    gd, ld = db.gd, db.ld
    sf = _rb_sf(db, "/lb6a/fc.pl")
    proc = _rb_proc(db, :fc, 1)
    cls = _rb_old!(db, sf, proc, _RB[_rb_p(_RB, :fc, i) for i in 1:4])
    g = LK.global_generation(gd)
    cls[1].generation_erased = cls[1].generation_created          # erased: invisible at g
    cls[3].generation_created = g + LK.gen_t(5)                    # created in the future: invisible at g
    refs = _rb_refs(proc.definition)
    @test length(refs) == 4
    @test !LK.GLOBALLY_VISIBLE_CLAUSE(cls[1], g) && LK.GLOBALLY_VISIBLE_CLAUSE(cls[2], g) &&
        !LK.GLOBALLY_VISIBLE_CLAUSE(cls[3], g) && LK.GLOBALLY_VISIBLE_CLAUSE(cls[4], g)    # both sides
    @test LK.find_clause(refs[1], g) === refs[2]                   # skips the erased one
    @test LK.find_clause(refs[3], g) === refs[4]                   # skips the one of the future
    @test LK.find_clause(refs[2], g) === refs[2]                   # a visible one is its own answer
    @test LK.find_clause(refs[4].next, g) === nothing && LK.find_clause(nothing, g) === nothing
    r = LK.p_reload{_RB}(proc.definition, g, refs[2], nothing, UInt64(0), UInt32(0))
    LK.advance_clause(r)
    @test r.current_clause === refs[4]                              # past the invisible p(3)
    LK.advance_clause(r)
    @test r.current_clause === nothing
    LK.advance_clause(r)
    @test r.current_clause === nothing                              # stays at the end
    @test LK.isRedefinedProcedure(proc, g)
    gone = _rb_proc(db, :gone, 1)
    gc = _rb_old!(db, sf, gone, _RB[_rb_p(_RB, :gone, 1)])
    gc[1].generation_erased = gc[1].generation_created
    @test !LK.isRedefinedProcedure(gone, g)                         # its only clause is erased
    @test !LK.isRedefinedProcedure(_rb_proc(db, :empty, 1), g)      # no clause at all
    # reloadHasClauses: no reload, a reload without a record, a record without a clause, a record with one
    @test !LK.reloadHasClauses(sf, proc)
    LK.startReconsultFile(gd, ld, sf)
    @test !LK.reloadHasClauses(sf, proc)
    LK.reloadContext(gd, ld, sf, proc)
    @test !LK.reloadHasClauses(sf, proc)
    sf.reload.procedures[proc].number_of_clauses = UInt32(1)
    @test LK.reloadHasClauses(sf, proc) && !LK.reloadHasClauses(sf, gone)
    _rb_end!(db)
end

@testset "A26 redefineProcedure returns at once for a predicate the reload has seen no clause of; A27 addProcedureSourceFile during a reload" begin
    db = IxDB{_RB}()
    gd, ld = db.gd, db.ld
    sf = _rb_sf(db, "/lb6a/rd_ours.pl")
    rd = _rb_proc(db, :rd, 1)
    cur = _rb_proc(db, :rd_cur, 1)
    xs = _rb_old!(db, sf, rd, _RB[_rb_p(_RB, :rd, 1)])             # the file's own clause (owner_no == sf.index)
    @test xs[1].generation_erased == LK.GEN_MAX && rd.source_no == sf.index
    # A27: a procedure whose source_no is this file's but which the file does not list yet: with a reload it is listed (and flagged multi-source), without it is not
    own = _rb_proc(db, :own, 1)
    own.source_no = UInt32(sf.index)
    @test sf.reload === nothing && !(own in sf.procedures)
    LK.addProcedureSourceFile(sf, own)
    @test !(own in sf.procedures)                                   # first load: the same file, nothing to add
    LK.startReconsultFile(gd, ld, sf)
    LK.addProcedureSourceFile(sf, own)
    @test own in sf.procedures && (own.definition.flags & LK.FILE_ASSIGNED) != 0       # during a reload it is added (A27)
    # A26 (pl-proc.c:3996-4004): the reload has seen no clause of rd. startReconsultFile marked rd's clause, which would end the call at the
    # `first === nothing` return; the mark is undone so the call reaches the reload test. The discontiguous warning is what the early return
    # skips: it needs a current procedure and the style check, and an unbooted database collects the message text on `ld.messages`.
    xs[1].generation_erased = LK.GEN_MAX
    sf.current_procedure = cur
    ld.debugstatus_styleCheck |= Int(LK.DISCONTIGUOUS_STYLE)
    rd.definition.flags &= ~LK.P_DISCONTIGUOUS
    @test !LK.reloadHasClauses(sf, rd) && LK.hasClausesDefinition(gd, rd.definition) !== nothing
    n0 = length(ld.messages)
    @test LK.redefineProcedure(gd, ld, rd, sf, 0)
    @test length(ld.messages) == n0                                  # the early return: no warning
    @test xs[1].generation_erased == LK.GEN_MAX && _rb_same(_rb_list(rd.definition), xs)
    # the other side: once the reload has seen a clause of rd the same call does warn (the guard can fail)
    LK.reloadContext(gd, ld, sf, rd).number_of_clauses = UInt32(1)
    @test LK.reloadHasClauses(sf, rd)
    @test LK.redefineProcedure(gd, ld, rd, sf, 0)
    @test length(ld.messages) > n0
    _rb_end!(db)
end

# ========================================================================================================
# r17-r20: setAttrProcedureSource, fix_det, fix_ssu, check_ssu, fix_attributes
# ========================================================================================================
@testset "r17 setAttrProcedureSource records the attribute in the reload and returns before setAttrDefinition for P_ATEND|P_TRANSPARENT" begin
    s = _rb_scene(_RB, :p, 1)
    db, sf, proc, def, gd, ld = s.db, s.sf, s.proc, s.def, s.db.gd, s.db.ld
    @test (def.flags & (LK.P_VOLATILE | LK.P_TRANSPARENT | LK.P_DISCONTIGUOUS)) == 0
    @test LK.setAttrProcedureSource(gd, ld, sf, proc, LK.P_VOLATILE, true)
    reload = sf.reload.procedures[proc]
    @test (reload.flags & LK.P_VOLATILE) != 0 && (def.flags & LK.P_VOLATILE) == 0          # recorded, not applied (A22)
    @test LK.setAttrProcedureSource(gd, ld, sf, proc, LK.P_TRANSPARENT, true)
    @test (reload.flags & LK.P_TRANSPARENT) != 0 && (def.flags & LK.P_TRANSPARENT) == 0
    @test LK.setAttrProcedureSource(gd, ld, sf, proc, LK.P_VOLATILE, false)
    @test (reload.flags & LK.P_VOLATILE) == 0                                              # cleared in the record
    # an attribute outside P_ATEND is recorded AND applied
    @test LK.setAttrProcedureSource(gd, ld, sf, proc, LK.P_DISCONTIGUOUS, true)
    @test (reload.flags & LK.P_DISCONTIGUOUS) != 0 && (def.flags & LK.P_DISCONTIGUOUS) != 0
    # without a reload: applied at once, no record
    sf2 = _rb_sf(db, "/lb6a/attr2.pl")
    q2 = _rb_proc(db, :q2, 1)
    @test sf2.reload === nothing
    @test LK.setAttrProcedureSource(gd, ld, sf2, q2, LK.P_VOLATILE, true)
    @test (q2.definition.flags & LK.P_VOLATILE) != 0 && sf2.reload === nothing
    _rb_end!(db)
end

@testset "r18-r19 fix_det, fix_ssu: the flag copies" begin
    db = IxDB{_RB}()
    gd, ld = db.gd, db.ld
    sf = _rb_sf(db, "/lb6a/fx.pl")
    mkr(def) = LK.p_reload{_RB}(def, LK.gen_t(0), nothing, nothing, UInt64(0), UInt32(0))
    # fix_det: a predicate that was det and is not declared so again loses P_DET; one declared again keeps it
    d1 = _rb_proc(db, :fd1, 1).definition
    d1.flags |= LK.P_DET
    LK.fix_det(gd, mkr(d1))
    @test (d1.flags & LK.P_DET) == 0                                                  # A17
    d2 = _rb_proc(db, :fd2, 1).definition
    d2.flags |= LK.P_DET
    r2 = mkr(d2)
    r2.flags |= LK.P_DET
    LK.fix_det(gd, r2)
    @test (d2.flags & LK.P_DET) != 0
    # fix_ssu: SSU first clause sets P_SSU_DET and P_CHECK_SSU; a normal first clause clears them; dynamic and multifile predicates are left alone
    pr = _rb_proc(db, :fs1, 1)
    ssu = _rb_clause(db, sf, pr, _rb_p(_RB, :fs1, 1); body=lk_sym(_RB, :true), flags=UInt32(LK.SSU_COMMIT_CLAUSE))
    nrm = _rb_clause(db, sf, pr, _rb_p(_RB, :fs1, 2))
    @test (ssu.flags & LK.SSU_COMMIT_CLAUSE) != 0 && (nrm.flags & (LK.SSU_COMMIT_CLAUSE | LK.SSU_CHOICE_CLAUSE)) == 0
    r = mkr(pr.definition)
    LK.fix_ssu(r, ssu)
    @test (pr.definition.flags & LK.P_SSU_DET) != 0 && (r.flags & LK.P_CHECK_SSU) != 0     # A17b
    r = mkr(pr.definition)
    LK.fix_ssu(r, ssu)
    @test (r.flags & LK.P_CHECK_SSU) == 0                                             # already SSU: no change to check
    r = mkr(pr.definition)
    LK.fix_ssu(r, nrm)
    @test (pr.definition.flags & LK.P_SSU_DET) == 0 && (r.flags & LK.P_CHECK_SSU) != 0     # A17c
    for fl in (LK.P_DYNAMIC, LK.P_MULTIFILE)
        pd = _rb_proc(db, Symbol("fs_$(fl)"), 1).definition
        pd.flags |= fl
        r = mkr(pd)
        LK.fix_ssu(r, ssu)
        @test (pd.flags & LK.P_SSU_DET) == 0 && (r.flags & LK.P_CHECK_SSU) == 0
    end
end

@testset "r20 check_ssu leaves its text on the local data's messages when the live clauses mix => and :-; fix_attributes copies P_ATEND" begin
    s = _rb_scene(_RB, :p, 2)
    db, sf, proc, def, gd, ld = s.db, s.sf, s.proc, s.def, s.db.gd, s.db.ld
    r = LK.reloadContext(gd, ld, sf, proc)
    mixed(ld) = count(m -> occursin("Mixed SSU (=> and :-) clauses in", String(sym_text(m[2]))), ld.messages)
    # the other side: all clauses normal and the predicate not SSU: no message
    n0 = mixed(ld)
    LK.check_ssu(gd, ld, r)
    @test mixed(ld) == n0
    # the predicate is SSU while its live clauses are normal: one message
    def.flags |= LK.P_SSU_DET
    LK.check_ssu(gd, ld, r)
    @test mixed(ld) == n0 + 1
    def.flags &= ~LK.P_SSU_DET
    # fix_attributes: non-multifile: the definition's P_ATEND bits become the reload's (A23); multifile: the reload's are added
    def.flags |= LK.P_ISO
    r.flags |= LK.P_VOLATILE
    @test (def.flags & LK.P_ISO) != 0 && (def.flags & LK.P_VOLATILE) == 0
    LK.fix_attributes(gd, sf, def, r)
    @test (def.flags & LK.P_VOLATILE) != 0 && (def.flags & LK.P_ISO) == 0
    mfp = _rb_proc(db, :atm, 1)
    mfp.definition.flags |= LK.P_MULTIFILE | LK.P_ISO
    r2 = LK.p_reload{_RB}(mfp.definition, LK.gen_t(0), nothing, nothing, LK.P_VOLATILE, UInt32(0))
    LK.fix_attributes(gd, sf, mfp.definition, r2)
    @test (mfp.definition.flags & LK.P_VOLATILE) != 0 && (mfp.definition.flags & LK.P_ISO) != 0
    _rb_end!(db)
end

# ========================================================================================================
# r21-r22: setMetapredicateSource, equal_meta, fix_metapredicate
# ========================================================================================================
@testset "r21 setMetapredicateSource records the masks in the reload; without a reload it sets them at once" begin
    s = _rb_scene(_RB, :p, 1)
    db, sf, gd, ld = s.db, s.sf, s.db.gd, s.db.ld
    mp = _rb_proc(db, :mp, 2)
    before = _rb_metas(mp.definition.impl_clauses.args::Vector{LK.arg_info})
    @test LK.setMetapredicateSource(gd, ld, sf, mp, _rb_args(LK.MA_META, LK.MA_ANY))
    reload = sf.reload.procedures[mp]
    @test _rb_metas(reload.args::Vector{LK.arg_info}) == UInt8[LK.MA_META, LK.MA_ANY]
    @test (reload.flags & LK.P_META) != 0 && (reload.flags & LK.P_TRANSPARENT) != 0         # A25
    @test (mp.definition.flags & (LK.P_META | LK.P_TRANSPARENT)) == 0                       # not applied
    @test _rb_metas(mp.definition.impl_clauses.args::Vector{LK.arg_info}) == before
    @test mp in sf.procedures                                                               # associateSource
    @test LK.setMetapredicateSource(gd, ld, sf, mp, _rb_args(LK.MA_ANY, LK.MA_NONVAR))
    @test _rb_metas(reload.args::Vector{LK.arg_info}) == UInt8[LK.MA_ANY, LK.MA_NONVAR]
    @test (reload.flags & LK.P_META) != 0 && (reload.flags & LK.P_TRANSPARENT) == 0         # not transparent now
    # without a reload
    sf2 = _rb_sf(db, "/lb6a/meta2.pl")
    m2 = _rb_proc(db, :mp2, 2)
    @test sf2.reload === nothing
    @test LK.setMetapredicateSource(gd, ld, sf2, m2, _rb_args(LK.MA_META, LK.MA_ANY))
    @test (m2.definition.flags & LK.P_META) != 0 && (m2.definition.flags & LK.P_TRANSPARENT) != 0
    @test _rb_metas(m2.definition.impl_clauses.args::Vector{LK.arg_info}) == UInt8[LK.MA_META, LK.MA_ANY]
    _rb_end!(db)
end

@testset "r22 equal_meta, fix_metapredicate: copy or leave the masks" begin
    db = IxDB{_RB}()
    gd = db.gd
    mkr(def, flags, args) = LK.p_reload{_RB}(def, LK.gen_t(0), nothing, args, UInt64(flags), UInt32(0))
    defargs(def) = _rb_metas(def.impl_clauses.args::Vector{LK.arg_info})
    # equal_meta
    e = _rb_proc(db, :em, 2).definition
    LK.setMetapredicateMask(e, _rb_args(LK.MA_META, LK.MA_ANY))
    @test LK.equal_meta(e, _rb_args(LK.MA_META, LK.MA_ANY))
    @test !LK.equal_meta(e, _rb_args(LK.MA_META, LK.MA_NONVAR))                       # the second mask differs
    @test !LK.equal_meta(e, _rb_args(LK.MA_ANY, LK.MA_ANY))
    @test !LK.equal_meta(e, nothing)
    # (a) a reload that declares: the definition gets P_META, P_TRANSPARENT and the masks
    a = _rb_proc(db, :fm1, 2).definition
    LK.fix_metapredicate(gd, mkr(a, LK.P_META | LK.P_TRANSPARENT, _rb_args(LK.MA_META, LK.MA_ANY)))
    @test (a.flags & LK.P_META) != 0 && (a.flags & LK.P_TRANSPARENT) != 0 && defargs(a) == UInt8[LK.MA_META, LK.MA_ANY]
    # (b) a reload that no longer declares: the declaration goes
    b = _rb_proc(db, :fm2, 2).definition
    LK.setMetapredicateMask(b, _rb_args(LK.MA_META, LK.MA_ANY))
    @test (b.flags & LK.P_META) != 0
    LK.fix_metapredicate(gd, mkr(b, 0, nothing))
    @test (b.flags & (LK.P_META | LK.P_TRANSPARENT)) == 0 && defargs(b) == UInt8[LK.MA_ANY, LK.MA_ANY]
    # (c) a module_transparent predicate the reload does not declare so again: P_TRANSPARENT is cleared (A24)
    c = _rb_proc(db, :fm3, 2).definition
    c.flags |= LK.P_TRANSPARENT
    LK.fix_metapredicate(gd, mkr(c, 0, nothing))
    @test (c.flags & LK.P_TRANSPARENT) == 0
    # (d) the same flags, different masks: the definition takes the reload's masks (A18)
    d = _rb_proc(db, :fm4, 2).definition
    LK.setMetapredicateMask(d, _rb_args(LK.MA_META, LK.MA_ANY))
    LK.fix_metapredicate(gd, mkr(d, LK.P_META | LK.P_TRANSPARENT, _rb_args(LK.MA_META, LK.MA_NONVAR)))
    @test defargs(d) == UInt8[LK.MA_META, LK.MA_NONVAR] && (d.flags & LK.P_META) != 0
    # (e) multifile: a declaration is set, a bare P_TRANSPARENT is added, nothing is removed
    f = _rb_proc(db, :fm5, 2).definition
    f.flags |= LK.P_MULTIFILE
    LK.fix_metapredicate(gd, mkr(f, LK.P_META | LK.P_TRANSPARENT, _rb_args(LK.MA_META, LK.MA_ANY)))
    @test (f.flags & LK.P_META) != 0 && defargs(f) == UInt8[LK.MA_META, LK.MA_ANY]
    g = _rb_proc(db, :fm6, 1).definition
    g.flags |= LK.P_MULTIFILE
    LK.fix_metapredicate(gd, mkr(g, LK.P_TRANSPARENT, nothing))
    @test (g.flags & LK.P_TRANSPARENT) != 0 && (g.flags & LK.P_META) == 0
end

# ========================================================================================================
# keep_clause, copy_clause_source, equal_clause (pl-srcfile.c:983-1026); Q3 (D-0415 item 3): equal_clause by identity
# ========================================================================================================
@testset "A12 copy_clause_source moves the owner and the file references" begin
    s = _rb_scene(_RB, :p, 1)
    db, sf, proc, olds, gd, ld = s.db, s.sf, s.proc, s.olds, s.db.gd, s.db.ld
    sf2 = _rb_sf(db, "/lb6a/other_owner.pl")
    nw = _rb_clause(db, sf, proc, _rb_p(_RB, :p, 1); owner=sf2, line=5)                # source = sf, owner = sf2
    a0, b0 = sf.references, sf2.references
    cref = LK.assertProcedureSource(gd, ld, sf, proc, nw)
    @test cref !== nothing && cref.clause === olds[1]
    @test olds[1].owner_no == sf2.index && olds[1].source_no == sf.index && olds[1].line_no == 5      # A12, A12b
    @test sf.references == a0 - 1 && sf2.references == b0                               # the references stay balanced: old (1) + new (2) -> kept (2)
    _rb_end!(db)
end

@testset "A20 an old clause with CL_ERASED set is not kept for an equal new clause" begin
    s = _rb_scene(_RB, :p, 2)
    db, sf, proc, def, olds = s.db, s.sf, s.proc, s.def, s.olds
    gd, ld = db.gd, db.ld
    old1 = olds[1]
    old1.flags |= LK.CL_ERASED                       # retracted by hand: still in the list, still globally visible at the reload generation
    @test LK.GLOBALLY_VISIBLE_CLAUSE(old1, LK.global_generation(gd)) && (olds[2].flags & LK.CL_ERASED) == 0
    new1 = _rb_clause(db, sf, proc, _rb_p(_RB, :p, 1))
    @test LK.equal_clause(old1, new1)                # the precondition: only the flag differs
    cref = LK.assertProcedureSource(gd, ld, sf, proc, new1)
    @test cref !== nothing && cref.clause === new1   # NOT the erased old clause (A20)
    @test _rb_same(_rb_list(def), [new1, old1, olds[2]])
    @test new1.generation_created == LK.GEN_RELOAD && old1.generation_erased == LK.GEN_RELOAD
    reload = sf.reload.procedures[proc]
    @test (reload.flags & LK.P_MODIFIED) != 0 && reload.current_clause.clause === old1
    # the other side: p(2) equals the live old clause behind it and that one is kept
    new2 = _rb_clause(db, sf, proc, _rb_p(_RB, :p, 2))
    cref = LK.assertProcedureSource(gd, ld, sf, proc, new2)
    @test cref !== nothing && cref.clause === olds[2] && olds[2].generation_erased == LK.GEN_MAX
    @test _rb_same(_rb_list(def), [new1, old1, olds[2]])
    _rb_end!(db)
end

function _rb_ec(db::IxDB{T}, head::T; body::Union{Nothing, T}=nothing)::LK.Clause{T} where {T}
    proc = _rb_proc(db, :ec, 1)
    cl = LK.compileClause(db.gd, db.ld, head, body, proc, LK.MODULE_user(db.gd))
    cl === nothing && error("compileClause refused the clause")
    return cl
end

@testset "Q3 equal_clause: the code vectors, the literal tables by identity, the procedure tables" begin
    db = IxDB{_RB}()
    ec(h; body=nothing) = _rb_ec(db, h; body=body)
    ep(x) = _rb_expr(_RB, :ec, x)
    a, b = lk_sym(_RB, :a), lk_sym(_RB, :b)
    # equal: the same fact twice (both sides of every comparison below are non-empty: literals / codes are looked at first)
    c1, c2 = ec(ep(a)), ec(ep(a))
    @test !isempty(c1.codes) && !isempty(c1.literals) && LK.equal_clause(c1, c2)
    # A13: different code vectors (an integer operand): not equal
    i1, i2 = ec(ep(_rb_int(_RB, 1))), ec(ep(_rb_int(_RB, 2)))
    @test !LK.equal_clause(i1, i2) && LK.equal_clause(i1, ec(ep(_rb_int(_RB, 1))))
    # different instruction, different table sizes: not equal
    @test !LK.equal_clause(ec(ep(a)), ec(ep(_rb_int(_RB, 1))))
    # A13b: EQUAL codes, different literals
    ab1, ab2 = ec(ep(a)), ec(ep(b))
    @test ab1.codes == ab2.codes && ab1.literals != ab2.literals                       # the precondition: only the literal differs
    @test !LK.equal_clause(ab1, ab2)
    # floats: 1.5 vs 2.5 (equal codes, different literals); 0.0 vs -0.0; one NaN payload pair (equal when the bits are equal)
    f(x) = ec(ep(lk_gnd(_RB, x)))
    @test LK.equal_clause(f(1.5), f(1.5)) && !LK.equal_clause(f(1.5), f(2.5))
    z0, zm = f(0.0), f(-0.0)
    @test z0.codes == zm.codes && length(z0.literals) == 1                            # only the sign bit differs
    @test !LK.equal_clause(z0, zm) && LK.equal_clause(z0, f(0.0)) && LK.equal_clause(zm, f(-0.0))
    nan1 = reinterpret(Float64, 0x7ff8000000000001)
    nan2 = reinterpret(Float64, 0x7ff8000000000002)
    @test isnan(nan1) && isnan(nan2) && reinterpret(UInt64, nan1) != reinterpret(UInt64, nan2)
    @test LK.equal_clause(f(nan1), f(nan1))                                            # the same bits: equal
    @test !LK.equal_clause(f(nan1), f(nan2))                                           # another payload: not equal
    # 1 vs 1.0: equal codes cannot be had from a compiled integer (a small integer is no literal), so the literal of a float clause is replaced by the integer: identity says they differ
    fl = f(1.0)
    fl2 = f(1.0)
    @test LK.equal_clause(fl, fl2)
    fl2.literals[1] = lk_gnd(_RB, Int64(1))
    @test fl.codes == fl2.codes && !LK.equal_clause(fl, fl2)
    @test !LK.equal_clause(ec(ep(_rb_int(_RB, 1))), f(1.0))                            # compiled: the codes differ already
    # strings: by content
    s(x) = ec(ep(lk_gnd(_RB, x)))
    @test LK.equal_clause(s("xy"), s("xy")) && !LK.equal_clause(s("xy"), s("xz"))
    # A13c: equal codes, different procedure tables (a call of f/1 against a call of g/1)
    x = lk_var(_RB, UInt64(1))
    cf1, cf2 = ec(ep(x); body=_rb_expr(_RB, :ecf, x)), ec(ep(x); body=_rb_expr(_RB, :ecg, x))
    @test cf1.codes == cf2.codes && length(cf1.procedures) == 1 && cf1.procedures[1] !== cf2.procedures[1]
    @test !LK.equal_clause(cf1, cf2)
    @test LK.equal_clause(cf1, ec(ep(x); body=_rb_expr(_RB, :ecf, x)))
end

@testset "the leaf functions of the reload leave the file references balanced (freeClause!, acquireSourceFileNo, releaseSourceFileNo)" begin
    db = IxDB{_RB}()
    sf = _rb_sf(db, "/lb6a/refs.pl")
    r0 = sf.references
    LK.acquireSourceFileNo(db.gd, sf.index)
    @test sf.references == r0 + 1
    @test LK.releaseSourceFileNo(db.gd, sf.index) && sf.references == r0
    LK.acquireSourceFileNo(db.gd, 0)                                                    # no file 0: nothing happens
    @test LK.releaseSourceFileNo(db.gd, 0)
    proc = _rb_proc(db, :fcr, 1)
    cl = _rb_clause(db, sf, proc, _rb_p(_RB, :fcr, 1))
    @test sf.references == r0 + 1
    LK.freeClause!(db.gd, cl)
    @test sf.references == r0
    # an owner that is not the source file holds a second reference
    sf2 = _rb_sf(db, "/lb6a/refs2.pl")
    r2 = sf2.references
    cl2 = _rb_clause(db, sf, proc, _rb_p(_RB, :fcr, 2); owner=sf2)
    @test sf.references == r0 + 1 && sf2.references == r2 + 1
    LK.freeClause!(db.gd, cl2)
    @test sf.references == r0 && sf2.references == r2
    # popNPredicateAccess!: pops the top n, answers the number left
    ld = db.ld
    n0 = length(ld.predicate_references)
    LK.pushPredicateAccessObj!(ld, db.gd, proc.definition)
    LK.pushPredicateAccessObj!(ld, db.gd, proc.definition)
    @test LK.popNPredicateAccess!(ld, 0) == n0 + 2
    @test LK.popNPredicateAccess!(ld, 2) == n0
end
