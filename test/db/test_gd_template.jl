# ORIGINAL: LB4 b1's gate for the template database (src/gd_template.jl; loader_boot design LD4 and H3) — upstream has one GD per process and no copy of it, so there is no swipl counterpart to compare with.
# test/db/test_gd_template.jl — the H3 rows (design evidence/r2/design/loader_boot.md §5 H3):
#   * the copy of a database state equals it (a DIGEST of the generation, the atom count, the flag table, the module table,
#     every procedure's flags and clause count) and shares NO mutable object with it (`gd_aliased_objects`, with a
#     negative control: a shallow rebuild of the struct, and one with the atom table shared, are both caught);
#   * the identities inside a database hold in its copy (`modules_user` is an entry of `modules`, `=/2` is the system module's
#     procedure, the definitions hold the copy's supervisors);
#   * ASSERT INTO A COPY: a clause, a new atom, a flag, a module, an operator and a source file each change the copy
#     and leave the TEMPLATE and a SIBLING copy unchanged (digests compared; the copy's digest must change, so the
#     comparison is not vacuous); a copy of a mutated copy is independent too;
#   * the registry: the template is built once per process and term type, a build that raises registers nothing, a reset
#     builds again; the stream tables: a closed slot is kept, a live stream refuses the copy.
# NOT RUN when written (edit-only, 2026-11-01): every row is "UNVERIFIED on the kernel: gate decides".
# The boot-time bench of H3 (30 interleaved runs) is not a row: evidence/LB4B1/bench_note.md.
using Test, LogicKernel
include(joinpath(@__DIR__, "index_testlib.jl"))
# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))

const _P = lk_term_type(Union{Int64, Float64})
_ps(n) = lk_sym(_P, Symbol(n))
_pe(f, xs::_P...) = mk_expr(_P, _P[_ps(f), xs...])
_pg(v) = lk_gnd(_P, v)

# what an observer of the database can tell: ONE extractor for every side of every comparison below
function gd_digest(gd::LK.PL_global_data{T}) where {T}
    rows = Tuple[]
    push!(rows, (:generation, LK.global_generation(gd)))
    push!(rows, (:atoms, gd.atoms.highest))
    push!(rows, (:flags, length(gd.prolog_flag.entries), gd.prolog_flag.mask))
    push!(rows, (:files, length(gd.files_array)))
    for m in gd.modules
        push!(
            rows,
            (:module, m.index, sym_key(m.atom), length(m.procedures), length(m.operators), copy(m.supers), m.flags)
        )
        for k in sort!(collect(keys(m.procedures)))
            d = m.procedures[k].definition
            push!(rows, (:procedure, m.index, k, d.flags, Int(d.impl_clauses.number_of_clauses), d.impl_foreign_function))
        end
    end
    return rows
end

# the six ways a test changes a database state, each returning nothing; every one changes the digest (asserted below)
function lb4b1_mutations()
    return Pair{Symbol, Function}[
        :clause => function (c)
            db = IxDB{_P}(c, LK.PL_local_data{_P}(c))
            p = ix_pred(_P, :lb4b1_fact, 1; dynamic=true, db=db)
            ix_assertz!(p, _pe(:lb4b1_fact, _pg(1)))
            return nothing
        end,
        :atom => function (c)
            LK._atom_word!(c.atoms, c.atom_symbols, _ps(:lb4b1_atom))
            return nothing
        end,
        :flag => function (c)
            LK.setPrologFlag(c, "lb4b1_flag", LK.FT_BOOL, true, 0)
            return nothing
        end,
        :module => function (c)
            LK._lookupModule!(c.modules, c.modules_system.code_data, _ps(:lb4b1_mod))
            return nothing
        end,
        :operator => function (c)
            LK.defOperator!(c, nothing, LK.MODULE_user(c), _ps(:lb4b1_op), LK.OP_XFX, Int16(700), true)
            return nothing
        end,
        :source_file => function (c)
            sf = LK.lookupSourceFile(c, _ps(:lb4b1_file), true)
            sf === nothing || LK.releaseSourceFile(sf)
            return nothing
        end,
    ]
end

const TMPL = LK.PL_global_data{_P}()
const D0 = gd_digest(TMPL)

@testset "the copy equals the template and shares nothing with it" begin
    c = LK.copy_global_data(TMPL)
    @test c !== TMPL && c isa LK.PL_global_data{_P}
    @test gd_digest(c) == D0
    @test length(D0) > 100                                          # non-vacuous: hundreds of built-in procedures
    nmut = 0
    for f in fieldnames(typeof(TMPL))
        a, b = getfield(TMPL, f), getfield(c, f)
        al = LK.gd_aliased_objects(a, b)
        @test isempty(al)                                           # field $f shares no mutable object
        isempty(LK._reachable_mutables(a)) || (nmut += 1)
    end
    @test nmut > 20                                                 # most fields hold mutable state: the loop saw them
    @test all(k in fieldnames(typeof(TMPL)) for k in keys(LK.GD_COPY_POLICY))   # no stale name in the policy table
    ra, rb = LK._reachable_mutables(TMPL), LK._reachable_mutables(c)
    @test length(ra) == length(rb) > 3 * length(TMPL.modules_system.procedures)   # the same graph, and a large one
    @test isempty(LK.gd_aliased_objects(TMPL, c))
    @test isempty(LK.gd_aliased_objects(c, LK.copy_global_data(TMPL)))        # two copies: nothing in common
end

@testset "the alias check catches a shared table (negative control)" begin
    n = nfields(TMPL)
    fields = Any[getfield(TMPL, i) for i in 1:n]
    shallow = typeof(TMPL)(fields...)                               # every field the template's own
    al = LK.gd_aliased_objects(TMPL, shallow)
    @test length(al) == length(LK._reachable_mutables(TMPL))
    c = LK.copy_global_data(TMPL)
    cf = Any[getfield(c, i) for i in 1:n]
    cf[Base.fieldindex(typeof(TMPL), :atoms)] = TMPL.atoms
    half = typeof(TMPL)(cf...)                                      # a copy that shares only the atom table
    al = LK.gd_aliased_objects(TMPL, half)
    @test any(x -> x === TMPL.atoms, al)
    @test !any(x -> x === TMPL.modules_user, al)
    @test !any(x -> x === TMPL.prolog_flag, al)
end

@testset "the identities inside a database hold in its copy" begin
    c = LK.copy_global_data(TMPL)
    for (gd, name) in ((TMPL, "template"), (c, "copy"))
        @test gd.modules_user === gd.modules[gd.modules_user.index]
        @test gd.modules_system === gd.modules[gd.modules_system.index]
        @test gd.modules_user.supers == [gd.modules_system.index]
        eq = LK.isCurrentProcedure(sym_key(_ps(:(=))), 2, gd.modules_system)
        @test eq !== nothing                                        # found on both sides: non-vacuous
        @test gd.procedures_equals2 === eq
        @test eq.definition.code_data.exit === gd.code_data.exit
    end
    @test c.modules_user !== TMPL.modules_user && c.modules_system !== TMPL.modules_system
    @test c.procedures_equals2 !== TMPL.procedures_equals2
    @test c.code_data.exit !== TMPL.code_data.exit
    @test c.atoms !== TMPL.atoms && c.prolog_flag !== TMPL.prolog_flag
end

@testset "assert into a copy: the template and a sibling copy are unchanged" begin
    for (name, mutate) in lb4b1_mutations()
        c1 = LK.copy_global_data(TMPL)
        c2 = LK.copy_global_data(TMPL)                              # the sibling, made before
        mutate(c1)
        @test gd_digest(c1) != D0                                   # the mutation DID change its database ($name)
        @test gd_digest(TMPL) == D0                                 # the template did not
        @test gd_digest(c2) == D0                                   # nor the sibling
        @test gd_digest(LK.copy_global_data(TMPL)) == D0            # nor does a copy made after
        c3 = LK.copy_global_data(c1)                                # a copy of a mutated copy
        d1 = gd_digest(c1)
        @test gd_digest(c3) == d1
        for (_, other) in lb4b1_mutations()
            other(c3)
        end
        @test gd_digest(c1) == d1                                   # c3's changes stay in c3
        @test gd_digest(TMPL) == D0
    end
    c = LK.copy_global_data(TMPL)
    db = IxDB{_P}(c, LK.PL_local_data{_P}(c))
    p = ix_pred(_P, :lb4b1_fact, 1; dynamic=true, db=db)
    ix_assertz!(p, _pe(:lb4b1_fact, _pg(1)))
    @test p.def.impl_clauses.number_of_clauses == 1
    key = sym_key(_ps(:lb4b1_fact))
    @test LK.isCurrentProcedure(key, 1, LK.MODULE_user(c)) === p.proc
    @test LK.isCurrentProcedure(key, 1, LK.MODULE_user(TMPL)) === nothing
end

@testset "the stream tables: a closed slot is kept, a live stream refuses the copy" begin
    gd = LK.PL_global_data{_P}()
    s = LK.Sopen_string(Vector{UInt8}("abc"), 3, "r")
    @test s !== nothing
    @test LK.getStreamContext(gd, s) == 1
    @test length(gd.stream_table) == 1
    @test_throws ErrorException LK.copy_global_data(gd)             # a live stream
    gd.stream_table[1] = nothing                                    # closed: the slot stays, empty
    c = LK.copy_global_data(gd)
    @test length(c.stream_table) == 1 && c.stream_table[1] === nothing
    @test c.stream_table !== gd.stream_table
    @test isempty(c.stream_filenames) && isempty(c.stream_aliases)
    @test typeof(c.stream_filenames) == typeof(gd.stream_filenames)
end

@testset "the registry builds once per process and term type" begin
    LK.reset_gd_templates!()
    n1, n2 = Ref(0), Ref(0)
    b1 = () -> (n1[] += 1; LK.PL_global_data{_P}())
    other = LK.Term{Float64} == _P ? LK.Term{Int64} : LK.Term{Float64}   # a second term type
    b2 = () -> (n2[] += 1; LK.PL_global_data{other}())
    @test !LK.gd_template_built(_P) && !LK.gd_template_built(other)
    t1 = LK.gd_template(_P, b1)
    @test LK.gd_template(_P, b1) === t1 && n1[] == 1                # built once
    @test LK.gd_template_built(_P) && !LK.gd_template_built(other)  # the other type is not built by the first
    u1 = LK.PL_global_data_from_template(_P, b1)
    u2 = LK.PL_global_data_from_template(_P, b1)
    @test n1[] == 1 && u1 !== t1 && u1 !== u2                       # a copy per request, not the template
    @test gd_digest(u1) == gd_digest(t1) == gd_digest(u2)
    t2 = LK.gd_template(other, b2)
    @test t2 isa LK.PL_global_data{other} && n2[] == 1 && n1[] == 1
    @test LK.gd_template(other, b2) === t2 && n2[] == 1
    @test LK.gd_template(_P, b1) === t1                             # per type: the first is still its own
    LK.reset_gd_templates!()
    @test !LK.gd_template_built(_P) && !LK.gd_template_built(other)
    @test gd_digest(u1) == gd_digest(t1)                            # a copy already made is unaffected
    t3 = LK.gd_template(_P, b1)
    @test n1[] == 2 && t3 !== t1                                    # built again after the reset
    LK.reset_gd_templates!()
    @test_throws ErrorException LK.gd_template(_P, () -> error("boot failed"))
    @test !LK.gd_template_built(_P)                                 # a build that raised registered nothing
    @test !islocked(LK._GD_TEMPLATES.lock)                          # the lock is released (a ReentrantLock re-locks in the same task, so test it)
    @test LK.gd_template(_P, b1) isa LK.PL_global_data{_P}          # and left the lock free
    LK.reset_gd_templates!()
end
