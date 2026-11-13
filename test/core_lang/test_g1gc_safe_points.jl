# ORIGINAL: G1-GC's safe-point audit run against the kernel (piece G1-2); no swipl-devel counterpart. The answers of the rows are swipl's (the .out).
# allow-new-artifact: G1-2, the test of the safe-point table docs/g1gc_safe_points.md and of the hook (src/pl-gc.jl considerGC), after test/core_lang/test_trie_gen_swipl.{jl,pl,out}
# test/core_lang/test_g1gc_safe_points.jl — what the safe-point audit claims, checked on the code (docs/g1gc_safe_points.md, pin 18168e62):
#   * TABLE == CODE: the `SITE <name> <file> <upstream>` block of the table and the `ALLOW_GC ... # G1-GC safe point: <name>` lines of src/*.jl
#     are the same set of names (each side read through ONE extractor, both non-empty), each name's line is in the file the table names, and
#     every row of the tables carries a verdict word;
#   * THE HOOK, by hand: `ensureGlobalSpace(ld, n, flags, site)` with `ld.gc_force` records `site` only when `flags` has ALLOW_GC, and a
#     placeholder collection moves nothing (the global stack's words, its top, the trail, the value table are as they were);
#   * THE SITES, through a program: test_g1gc_safe_points.pl holds a row `gN(R)` per SAFE site; every row runs on a fresh kernel with
#     `ld.gc_force` off and on; the answers equal the .out (swipl's) either way, the heap with the flag on is never larger than with it off (the
#     collector runs at a foreign site, G1-6c: the answers are compared equal in the same row), with the flag off
#     nothing is recorded, with it on the row's site is recorded and nothing outside the table is (a site the table rules NEEDS-ROOT passes no ALLOW_GC).
# `ld.gc_force` is the model of upstream's FAKE_GC (pl-vmi.c:238-251). The collector itself is G1-3..G1-6: until it exists a "collection" is
# the declining placeholder `garbageCollect`, so what is checked is WHERE the hook is reached and that reaching it changes nothing.
# NOT HERE: the VM macro sites (@ENSURE_GLOBAL_SPACE: no ALLOW_GC yet, table A "VM" rows), the signal and exception points (table C).
# The kill rows are `@test`s INSIDE testsets (a top-level failing `@test` gives no verdict in CI mode).
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _GP = lk_term_type(Union{Int64, Float64, String, BigInt, Rational{BigInt}})

_gcodes(s::String) = "[" * join(Int.(collect(s)), ",") * "]"
function enc(t::_GP, seen::Vector{UInt64}=UInt64[])::String
    k = kind(t)
    if k === VAR
        i = findfirst(==(var_key(t)), seen)
        if i === nothing
            push!(seen, var_key(t))
            i = length(seen)
        end
        return "V$(i - 1)"
    elseif k === SYM
        return is_nil(t) ? "nil" : "a" * _gcodes(sym_text(t))
    elseif k === GND
        v = lk_value(t)
        v isa AbstractString && return "s" * _gcodes(String(v))
        v isa Integer && return "i$v"
        v isa Rational && return "q$(numerator(v))r$(denominator(v))"
        v isa AbstractFloat && return "f$(v)"
        return "?$(typeof(v))"
    end
    h = child(t, 1)
    return (is_nil(h) ? "c[]" : "c" * _gcodes(sym_text(h))) * "/$(nchildren(t) - 1)(" *
           join([enc(child(t, i), seen) for i in 2:nchildren(t)], ",") * ")"
end

const _G_ROOT = joinpath(@__DIR__, "..", "..")
const _G_PL = joinpath(@__DIR__, "test_g1gc_safe_points.pl")
const _G_OUT = joinpath(@__DIR__, "test_g1gc_safe_points.out")
const _G_DOC = joinpath(_G_ROOT, "docs", "g1gc_safe_points.md")

# the rows' names, in the order of the program
_g_names() =
    unique([String(m[1]) for m in eachmatch(r"^(g\d+)\(R\) :-"m, read(_G_PL, String))])

# THE SITES THE ROWS MUST RECORD (the table's names): one or more per row. A row that reaches a site only through another
# predicate lists that site too (g3 and g4 build their attvar with put_attr/3 first).
const _G_REQ = Dict{String, Vector{Symbol}}(
    "g1" => [:put_attr3],
    "g2" => [:put_attrs2],
    "g3" => [:put_attr3, :del_attr2],
    "g4" => [:put_attr3, :del_attrs1],
    "g5" => [:put_attr3, :attv_unify2],
    "g6" => [:dfreeze2],
    "g7" => [:dsuspend3],
    "g8" => [:functor3],
    "g9" => [:compound_name_arity3],
    "g10" => [:univ2],
    "g11" => [:compound_name_arguments3],
    "g12" => [:length2],
    "g13" => [:setval],
    "g14" => [:setval],
    "g15" => [:collect_findall_bag, :copyRecordToGlobal],
    "g16" => [:copyRecordToGlobal],
    "g17" => [:copy_term_refs],
    "g18" => [:get_dict_ex],
    "g19" => [:put_environment],
    "g20" => Symbol[],    # the wakeup of a frozen variable: bind_attvar_const passes no ALLOW_GC (table A, NEEDS-ROOT)
    "g21" => [:copyRecordToGlobal],   # recorded/3 with a bound reference (pl-rec.jl, the first call site)
    "g22" => [:copyRecordToGlobal],   # instance/2 of a record reference
    "g23" => [:copyRecordToGlobal]   # PL_recorded through a trie value
)

# ── the table and the code, each through ONE extractor ──────────────────────────────────────────
# the table's `SITE <name> <file> <upstream>` lines: (name, file)
function doc_sites(text::String)::Vector{Tuple{String, String}}
    return [
        (String(m[1]), String(m[2])) for
        m in eachmatch(r"^SITE (\w+) (\S+) (\S+)\s*$"m, text)
    ]
end

# the code's sites: a line of `src` passing ALLOW_GC as an argument and marked `# G1-GC safe point: <name>`: (name, file)
function src_sites(src::String)::Vector{Tuple{String, String}}
    out = Tuple{String, String}[]
    for f in sort(readdir(src))
        endswith(f, ".jl") || continue
        for line in eachline(joinpath(src, f))
            m = match(r",\s*ALLOW_GC\b.*#\s*G1-GC safe point:\s*(\w+)", line)
            m === nothing || push!(out, (String(m[1]), "src/" * f))
        end
    end
    return out
end

const _G_VERDICT = r"\b(SAFE-REGISTERS|SAFE|NEEDS-ROOT|NEEDS-REFACTOR|NOT-A-SAFE-POINT|NO-COUNTERPART|MACRO)\b"

@testset "G1-GC: the SITE table == the ALLOW_GC lines of src, every row has a verdict" begin
    text = read(_G_DOC, String)
    ds = doc_sites(text)
    ss = src_sites(joinpath(_G_ROOT, "src"))
    @test !isempty(ds) && !isempty(ss)
    @test length(ds) == length(unique(first.(ds)))                    # a name once in the table
    @test Set(first.(ds)) == Set(first.(ss))                          # the same names
    for (name, file) in ds
        @test (name, file) in ss                                      # and the file the table names holds the line
    end
    @test length(ds) >= 18
    # the rows: Table A has the 129 upstream sites; B and C have rows of their own; each row has one verdict word
    a = split(text, "## Table A")[2]
    arows = filter(l -> startswith(l, "| pl-"), split(first(split(a, "## Table B")), '\n'))
    @test length(arows) == 129
    @test all(l -> occursin(_G_VERDICT, l), arows)
    rows = filter(
        l -> startswith(l, "| ") && !occursin("| verdict |", l) && !startswith(l, "|---"),
        split(text, '\n')
    )
    @test length(rows) >= 140                                         # 129 + the rows of B and C
    @test all(l -> occursin(_G_VERDICT, l), rows)
    # every SAFE-listed site of the code carries a SAFE verdict in the table (its name is in an `ALLOW_GC passed` action)
    for (name, _) in ds
        @test any(l -> occursin("`$name`", l) && occursin("SAFE", l), rows)
    end
end

# ── the hook, by hand ───────────────────────────────────────────────────────────────────────────
# the heap as the hook must leave it: the global stack's words and top, the trail's and the value table's lengths
_heap(ld::LK.PL_local_data) =
    (ld.gTop, copy(ld.gstack[1:ld.gTop]), length(ld.trail), length(ld.vtable))

@testset "G1-GC: ensureGlobalSpace(.., flags, site) records the site only with ALLOW_GC under gc_force, and moves nothing" begin
    gd = LK.PL_global_data{_GP}()
    ld = LK.PL_local_data{_GP}(gd)
    LK.allocGlobalCells!(ld, 5)
    before = _heap(ld)
    @test before[1] >= 5 && !isempty(before[2])                       # something on the heap to move
    ld.gc.status.blocked = 1          # G1-6c: the collector is real now and would compact this heap; blocked it declines, as the placeholder did
    @test !ld.gc_force && isempty(ld.gc_safe_hits)

    # not forced: the hook may run (the area is full) but nothing is recorded (it records only under the flag)
    @test LK.ensureGlobalSpace(ld, 4, LK.ALLOW_GC, :probe_site)
    @test LK.ensureGlobalSpace(ld, length(ld.gstack) + 10, LK.ALLOW_GC, :probe_full)
    @test isempty(ld.gc_safe_hits)

    ld.gc_force = true
    @test LK.ensureGlobalSpace(ld, 4, LK.ALLOW_GC, :probe_site)
    @test ld.gc_safe_hits == [:probe_site]                            # forced, ALLOW_GC: recorded
    @test LK.ensureGlobalSpace(ld, 4)                                  # flags 0 (the default): the hook is not reached
    @test LK.ensureGlobalSpace(ld, 4, LK.ALLOW_SHIFT, :probe_shift)    # ALLOW_SHIFT alone: not reached either
    @test ld.gc_safe_hits == [:probe_site]
    @test LK.ensureGlobalSpace(ld, 4, LK.ALLOW_GC | LK.ALLOW_SHIFT, :probe_both)
    @test ld.gc_safe_hits == [:probe_site, :probe_both]               # ALLOW_GC among other bits: reached

    # considerGC directly: the blocked collector declines, the hook says so
    @test !LK.considerGC(ld, LK.ALLOW_GC, LK.GC_USER, :probe_direct)
    @test ld.gc_safe_hits == [:probe_site, :probe_both, :probe_direct]
    @test !LK.considerGC(ld, 0, LK.GC_USER, :probe_none)
    @test length(ld.gc_safe_hits) == 3
    @test LK.garbageCollect(ld, Int(LK.GC_USER)) == LK.BOOLEX_FALSE     # blocked: BOOLEX_FALSE
    @test !LK.considerGarbageCollect(ld)

    @test _heap(ld) == before                                          # nothing moved, nothing freed
    ld.gc_force = false
    @test LK.ensureGlobalSpace(ld, 4, LK.ALLOW_GC, :probe_off)
    @test length(ld.gc_safe_hits) == 3                                 # the flag off again: nothing more
end

# ── the sites, through a program ────────────────────────────────────────────────────────────────
# a fresh kernel with `path` consulted: `(gd, ld, "ok" or "exc <ball>")`
function _tp_load(::Type{T}, path::String) where {T}
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}(gd)
    st, ball = LK.load_file!(gd, ld, path)
    return gd, ld, (st === :ok ? "ok" : "exc " * enc(ball::T))
end

# the driver's line for the row `name`/1 (every answer, at most 100): the name, then each solution
function _tp_row(
    gd::LK.PL_global_data{T}, ld::LK.PL_local_data{T}, name::String
)::String where {T}
    proc = LK.isCurrentProcedure(sym_key(lk_sym(T, Symbol(name))), 1, LK.MODULE_user(gd))
    (proc === nothing || !LK.isDefinedProcedure(gd, proc)) && return "$name undefined"
    sols = String[]
    fid = LK.PL_open_foreign_frame(ld)
    a = LK.PL_new_term_refs(ld, 1)
    LK.putSlotValue!(ld, a + 1, mk_var(T, LK.fresh_var_keys!(1)), LK.PutVarMap())
    qid = LK.PL_open_query(
        gd, ld, nothing, LK.PL_Q_CATCH_EXCEPTION | LK.PL_Q_EXT_STATUS, proc, a
    )
    n = 0
    while (n += 1) <= 100
        rc = LK.PL_next_solution(gd, ld, qid)
        if rc == LK.PL_S_TRUE || rc == LK.PL_S_LAST
            push!(
                sols,
                try
                    enc(
                        mk_expr(T, T[lk_sym(T, Symbol(name)), lk_answers(ld, (a:a)...)...])
                    )
                catch e
                    "export-error " * first(sprint(showerror, e), 80)
                end
            )
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
    return "$name" * join(" " .* sols)
end

# every row on a fresh kernel (`force` = ld.gc_force, set after the program is loaded): the lines (`ok`, then each row), each row's recorded
# sites, the heap's size after each row (the global stack's top, the trail's and the value table's lengths), and the number of collections that ran
function run_rows(path::String, names::Vector{String}; force::Bool)
    gd, ld, st = _tp_load(_GP, path)
    ld.gc_force = force
    lines = String[st]
    hits = Vector{Vector{Symbol}}()
    heap = Vector{Tuple{Int, Int, Int}}()
    ncoll = Int(ld.gc.stats.totals.collections)
    for name in names
        empty!(ld.gc_safe_hits)
        push!(lines, _tp_row(gd, ld, name))
        push!(hits, copy(ld.gc_safe_hits))
        push!(heap, (ld.gTop, length(ld.trail), length(ld.vtable)))
    end
    return lines, hits, heap, Int(ld.gc.stats.totals.collections) - ncoll
end

# the driver swipl runs to print its lines (the .out is its output; the text of test_trie_gen_swipl.jl's DRIVER)
const DRIVER = raw"""
enc(T) :- enc(T, [], _).
enc(V, S0, S) :- var(V), !, ( vidx(S0, V, 0, I) -> S = S0 ; length(S0, I), append(S0, [V], S) ), format("V~w", [I]).
enc(T, S, S) :- T == [], !, write(nil).
enc(T, S, S) :- atom(T), !, atom_codes(T, Cs), format("a~w", [Cs]).
enc(T, S, S) :- string(T), !, string_codes(T, Cs), format("s~w", [Cs]).
enc(T, S, S) :- integer(T), !, format("i~w", [T]).
enc(T, S, S) :- rational(T, N, D), !, format("q~wr~w", [N, D]).
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
    catch(findnsols(100, G, G, Gs), _, Gs = [exception]),
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
        read(
            pipeline(addenv(`swipl -q $f`, "LC_ALL" => "C"); stdin=devnull, stderr=devnull),
            String
        )
    end
    return String.(split(chomp(out), '\n'))
end

@testset "G1-GC: every SAFE site is reached by its row; the hook records it and changes nothing (flag off == flag on == swipl)" begin
    names = _g_names()
    expected = String.(readlines(_G_OUT))
    table = Set(Symbol(first(s)) for s in doc_sites(read(_G_DOC, String)))
    @test length(names) == 23 && Set(keys(_G_REQ)) == Set(names)
    @test length(expected) == length(names) + 1 && expected[1] == "ok"
    @test all(i -> startswith(expected[i + 1], names[i] * " "), eachindex(names))
    @test !any(l -> occursin(r"export-error|undefined| exception$", l), expected)
    # every site of the table is required by some row (both sides non-empty): a site no row reaches proves nothing
    required = Set(Symbol.(vcat(values(_G_REQ)...)))
    @test !isempty(required) && !isempty(table)
    @test required == table

    off_lines, off_hits, off_heap, _ = run_rows(_G_PL, names; force=false)
    on_lines, on_hits, on_heap, on_coll = run_rows(_G_PL, names; force=true)
    @test length(off_lines) == length(expected) == length(on_lines)
    for i in eachindex(expected)
        @test (i, off_lines[i]) == (i, expected[i])                   # the flag off: swipl's answers
        @test (i, on_lines[i]) == (i, expected[i])                    # the flag on: the same answers
    end
    for (i, name) in enumerate(names)
        @test isempty(off_hits[i])                                    # the flag off: nothing recorded
        for site in _G_REQ[name]
            @test (name, site, site in on_hits[i]) == (name, site, true)   # the flag on: the row's site recorded
        end
        @test all(s -> s in table, on_hits[i])                        # nothing outside the table (NEEDS-ROOT sites pass no ALLOW_GC)
        # G1-6c: the collector RUNS at a foreign safe point, so the heap may be SMALLER with the flag on (never larger). The answers are compared equal in
        # THIS row, through the same reader for both runs and swipl's (`expected`, the .out): equal answers and a heap that did not grow is the claim; a
        # different answer would be a collector bug, not a tolerance (audit D-0644 item 2).
        @test (
            i, on_lines[i + 1] == off_lines[i + 1] == expected[i + 1],
            !isempty(on_lines[i + 1]),
            on_heap[i][1] <= off_heap[i][1], on_heap[i][2] <= off_heap[i][2],
            on_heap[i][3] <= off_heap[i][3]
        ) == (i, true, true, true, true, true)
    end
    @info "G1-GC safe-points row" on_coll hits_on=length(union(on_hits...))    # diagnostic only (D-0644: the assertions stay strict)
    @test on_coll > 0                                                 # the collector ran at the foreign sites, so the `<=` above is not vacuous
    @test !isempty(union(on_hits...))

    swipl = get(ENV, "LOGICKERNEL_NO_SWIPL", "") == "1" ? nothing : Sys.which("swipl")
    if swipl === nothing
        @info "G1-GC DIFFERENTIAL NOT RUN LIVE: `swipl` is not on PATH here (the .out was checked). It runs in tools/run_tests.sh and CI."
    else
        @test swipl_lines(_G_PL, names) == expected
    end
end

# The kill rows: single rows, each fails on its own when the one thing it names breaks.
@testset "G1-GC kill rows: the answers of single rows and their sites" begin
    names = _g_names()
    lines, hits, _, _ = run_rows(_G_PL, names; force=true)
    kl = Dict(zip(["ok"; names], lines))
    kh = Dict(zip(names, hits))
    @test kl["ok"] == "ok"
    @test kl["g1"] == "g1 c[103,49]/1(i1)"                             # the attribute is kept
    @test kl["g3"] == "g3 c[103,51]/1(a[112,108,97,105,110])"          # del_attr/2 makes the variable plain
    @test kl["g8"] == "g8 c[103,56]/1(c[102,111,111]/3(V0,V1,V2))"     # functor/3: three fresh arguments
    @test kl["g12"] ==
        "g12 c[103,49,50]/1(c[91,124,93]/2(V0,c[91,124,93]/2(V1,c[91,124,93]/2(V2,nil))))"   # '$length'/2: three cells
    @test kl["g20"] == "g20 c[103,50,48]/1(i1)"                        # the wakeup of a frozen variable still binds
    @test :put_attr3 in kh["g1"] && :put_attr3 in kh["g3"]
    @test :functor3 in kh["g8"] && !(:univ2 in kh["g8"])               # a row records ITS site, not another's
    @test :univ2 in kh["g10"] && !(:functor3 in kh["g10"])
    @test :setval in kh["g13"] && :setval in kh["g14"]
    @test :copyRecordToGlobal in kh["g16"] && :copyRecordToGlobal in kh["g15"]
    @test all(n -> :copyRecordToGlobal in kh[n], ["g21", "g22", "g23"])   # each caller of copyRecordToGlobal has its own row
    @test kl["g21"] ==
        "g21 c[103,50,49]/1(c[45]/2(a[103,49,103,99,95,107,50],c[102,111,111]/1(a[97])))"   # the key is unified from the reference
    @test !(:bind_attvar_const in kh["g20"])                           # NEEDS-ROOT: no ALLOW_GC at bind_attvar_const
end
