# ORIGINAL: the functor table (L1b stage B, src/pl-funct.jl) against pl-funct.c's rules and src/ATOMS at the pin; upstream has no unit test of its functor table (its tests reach it through functor/3 and friends, which read the table only from stage C here).
# test/core_lang/test_functor_table.jl — white-box, each case hand-written with its reason:
#   * THE DATA: src/pl-funct.jl's generated region is exactly what tools/gen_atoms.jl makes of
#     src/ATOMS AT THE PIN wherever a checkout is found; without one, the test asserts there is
#     none, so it cannot skip silently;
#   * lookup: `lookupFunctorDef(a, n)` twice → one word; the same name at another arity → another
#     word; `isCurrentFunctor` → 0 for an unknown pair and creates nothing;
#   * the word: `isFunctor` (TAG_ATOM | STG_GLOBAL), not an atom word (same tag, other storage);
#     `indexFunctor`/`arityFunctor` round trip at arities 0, 1, 30, 31, 32, 1000 — 31 and up read
#     from the table (`_arityFunc_(w) == F_ARITY_MASK`); `isAtomFunctor` iff arity 0;
#   * the built-ins: 336 functors in src/ATOMS order, index 1 first (defatom.c's `int functor=1`),
#     each found again by lookup without creating; `CONTROL_F` on exactly `,/2 ;/2 |/2 ->/2 *->/2
#     \+/1 :/2 $/1 @/2` (O_CALL_AT_MODULE is defined, pl-incl.h:236), `ARITH_F` on exactly
#     `=:=/2 =\=/2 </2 >/2 =</2 >=/2 is/2`;
#   * rehash: 3,000 new functors (more than `FUNCTORHASHSIZE * 2`), each found again, the
#     built-ins unmoved;
#   * one functor table per database.
# NOT HERE, with stage C (when terms are read through the table): the swipl differentials of the
# L1 plan's B list (`functor(T, f, 31)`, 32, 1000; the `$expr/n` compound).
using Test, LogicKernel
const LK = LogicKernel

const _FT_CHECKOUT = get(
    ENV, "LOGICKERNEL_UPSTREAM_SWIPL_DEVEL", joinpath(homedir(), "dev-zone", "swipl-devel")
)

"A fresh functor table, as a database's (`initFunctors!`)."
_ft_table() = LK.initFunctors!(LK.functors_t())

"The word of a new atom named `s` in `atoms` (a fresh atom table by default)."
_ft_atom(s::AbstractString, atoms=LK.do_init_atoms!(LK.atoms_t())) =
    LK.lookupAtom(atoms, Vector{UInt8}(codeunits(s)))

"The atom word of built-in atom number `a` (`(a << LMASK_BITS) | TAG_ATOM`, `reserveAtom`)."
_ft_atom_word(a::Integer) = (UInt64(a) << LK.LMASK_BITS) | LK.TAG_ATOM

if isdir(joinpath(_FT_CHECKOUT, ".git"))
    @testset "src/pl-funct.jl's built-in functors are src/ATOMS at the pin (tools/gen_atoms.jl)" begin
        m = Module(:GenFunctorsCheck)
        Base.include(m, joinpath(pkgdir(LogicKernel), "tools", "gen_atoms.jl"))
        commit = Base.invokelatest(m.pinned_commit, pkgdir(LogicKernel))
        ids, _ = Base.invokelatest(m.atoms_at_pin, _FT_CHECKOUT, commit)
        src = read(`git -C $_FT_CHECKOUT show $commit:src/ATOMS`, String)
        fs = Base.invokelatest(m.parse_functors, src)
        dst = joinpath(pkgdir(LogicKernel), "src", "pl-funct.jl")
        reg = Base.invokelatest(m.functor_region, fs, ids, commit)
        @test Base.invokelatest(m.rewrite, dst, reg; begin_mark=m.FBEGIN_MARK) ==
            read(dst, String)
        @test length(fs) == 336 == length(LK._BUILTIN_FUNCTORS)
        @test count(l -> startswith(l, 'F'), split(src, '\n')) == 336
        # each generated entry names the atom of its `F` line, at the line's arity
        @test all(
            k ->
                LK._BUILTIN_ATOM_IDS[LK._BUILTIN_FUNCTORS[k][1]] == fs[k][1] &&
                LK._BUILTIN_FUNCTORS[k][2] == fs[k][2],
            eachindex(fs)
        )
    end
else
    @info "FUNCTOR TABLE DATA CHECK NOT RUN: no swipl-devel checkout at $_FT_CHECKOUT."
    @testset "the functor data check is skipped only where there is no checkout" begin
        @test !isdir(joinpath(_FT_CHECKOUT, ".git"))
    end
end

@testset "lookup: one word per (name, arity); isCurrentFunctor never creates" begin
    functors = _ft_table()
    atoms = LK.do_init_atoms!(LK.atoms_t())       # one table: two fresh ones reuse an index
    a = _ft_atom("lk_not_a_builtin_functor", atoms)
    h, n = functors.highest, functors.statistics_functors
    w2 = LK.lookupFunctorDef(functors, a, 2)
    @test LK.lookupFunctorDef(functors, a, 2) == w2                       # the same word
    @test functors.highest == h + 1 && functors.statistics_functors == n + 1
    w3 = LK.lookupFunctorDef(functors, a, 3)
    @test w3 != w2 && LK.indexFunctor(w3) == h + 1                         # the next index
    @test LK.isCurrentFunctor(functors, a, 2) == w2
    @test LK.isCurrentFunctor(functors, a, 3) == w3
    # an unknown pair: 0, and nothing made (no index taken, nothing counted, not found after)
    h, n = functors.highest, functors.statistics_functors
    @test LK.isCurrentFunctor(functors, a, 4) == 0
    @test LK.isCurrentFunctor(functors, _ft_atom("lk_other_name", atoms), 2) == 0
    @test functors.highest == h && functors.statistics_functors == n
    @test LK.isCurrentFunctor(functors, a, 4) == 0
    # the new definition: its word, its name (the ATOM WORD), its arity, VALID_F and no other flag
    fd = LK.valueFunctor(functors, w2)
    @test fd.functor == w2 && fd.name == a && fd.arity == 2 && fd.flags == LK.VALID_F
    @test LK.nameFunctor(functors, w2) == a
end

@testset "the word: isFunctor, its index and arity, inline below 31 and from the table above" begin
    functors = _ft_table()
    a = _ft_atom("lk_arity_probe")
    for n in (0, 1, 30, 31, 32, 1000)
        w = LK.lookupFunctorDef(functors, a, n)
        @test LK.isFunctor(w)
        @test LK.tagex(w) != (LK.TAG_ATOM | LK.STG_STATIC)                # not an atom word
        @test LK.tagex(w) & LK.TAG_MASK == LK.TAG_ATOM                     # the same tag
        @test LK.fetchFunctorArray(functors, LK.indexFunctor(w)).functor == w
        @test LK.arityFunctor(functors, w) == n
        @test LK._arityFunc_(w) == min(n, Int(LK.F_ARITY_MASK))            # 31 and up: the mask
        @test LK.isAtomFunctor(functors, w) == (n == 0)
        @test w == LK.MK_FUNCTOR(
            UInt64(LK.indexFunctor(w)), n < LK.F_ARITY_MASK ? UInt64(n) : LK.F_ARITY_MASK
        )
    end
end

@testset "the built-ins: 336 in src/ATOMS order, index 1 first; CONTROL_F and ARITH_F exactly" begin
    functors = _ft_table()
    @test functors.highest == 337 && functors.statistics_functors == 336
    @test functors.table.buckets == LK.FUNCTORHASHSIZE
    for (k, (a, arity)) in enumerate(LK._BUILTIN_FUNCTORS)
        fd = LK.fetchFunctorArray(functors, k)
        @test fd.name == _ft_atom_word(a) && fd.arity == arity
        @test LK.indexFunctor(fd.functor) == k
        @test LK.lookupFunctorDef(functors, fd.name, arity) == fd.functor     # found, not made
        @test LK.builtin_functor(LK._BUILTIN_ATOM_IDS[a], arity) == fd.functor
    end
    @test functors.highest == 337 && functors.statistics_functors == 336
    @test_throws ArgumentError LK.builtin_functor("comma", 3)
    @test_throws ArgumentError LK.builtin_functor("no_such_atom_id", 2)
    flagged(flag) = Set(
        (LK._BUILTIN_ATOM_IDS[a], arity) for
        (k, (a, arity)) in enumerate(LK._BUILTIN_FUNCTORS)
        if LK.fetchFunctorArray(functors, k).flags & flag != 0
    )
    @test flagged(LK.CONTROL_F) == Set([
        ("comma", 2), ("semicolon", 2), ("bar", 2), ("ifthen", 2), ("softcut", 2),
        ("not_provable", 1), ("colon", 2), ("dollar", 1), ("at_sign", 2)
    ])
    @test flagged(LK.ARITH_F) == Set([
        ("ar_equals", 2), ("ar_not_equal", 2), ("smaller", 2), ("larger", 2),
        ("smaller_equal", 2), ("larger_equal", 2), ("is", 2)
    ])
    @test length(flagged(LK.VALID_F)) == 336
    # the flagged ones by their text: the atom table's names of the CONTROL_F definitions
    atoms = LK.do_init_atoms!(LK.atoms_t())
    texts = Set(
        (
            String(
                LK.atomValue(atoms, fd.name).name[1:LK.atomValue(atoms, fd.name).length]
            ),
            fd.arity
        )
        for fd in (LK.fetchFunctorArray(functors, k) for k in 1:336) if
        fd.flags & LK.CONTROL_F != 0
    )
    @test texts == Set([
        (",", 2), (";", 2), ("|", 2), ("->", 2), ("*->", 2), ("\\+", 1), (":", 2),
        ("\$", 1),
        ("@", 2)
    ])
end

@testset "rehash: 3,000 new functors, each found again; the built-ins unmoved" begin
    functors = _ft_table()
    builtins = [LK.fetchFunctorArray(functors, k) for k in 1:336]
    atoms = LK.do_init_atoms!(LK.atoms_t())
    names = [_ft_atom("f_$i", atoms) for i in 1:3_000]
    ws = [LK.lookupFunctorDef(functors, names[i], i % 7) for i in 1:3_000]
    @test allunique(ws)
    @test functors.table.buckets > LK.FUNCTORHASHSIZE                     # it rehashed
    @test functors.table.buckets * 2 >= functors.statistics_functors
    @test functors.statistics_functors == 3_336 && functors.highest == 3_337
    @test all(i -> LK.lookupFunctorDef(functors, names[i], i % 7) == ws[i], 1:3_000)
    @test all(i -> LK.isCurrentFunctor(functors, names[i], i % 7) == ws[i], 1:3_000)
    @test all(k -> LK.fetchFunctorArray(functors, k) === builtins[k], 1:336)
    @test functors.statistics_functors == 3_336                          # nothing made again
    # every valid definition is on exactly one chain of the new table
    chained = 0
    for f0 in functors.table.table
        f = f0
        while f !== nothing
            chained += 1
            f = f.next
        end
    end
    @test chained == 3_336
end

@testset "a database holds its own functor table" begin
    gd1 = LK.PL_global_data{LK.DefaultTerm}()
    gd2 = LK.PL_global_data{LK.DefaultTerm}()
    @test gd1.functors !== gd2.functors
    # the INVARIANT, not the total (user, 2026-10-15: the total moves whenever a boot clause adds a
    # functor — two more than the built-ins since L1c, `findall_loop/4` registered through its functor-word operand when the
    # boot clauses are compiled at creation): the 336 built-ins at indices 1..336 as generated from
    # the pin, and every later functor resolving to its own name/arity
    for g in (gd1, gd2)
        @test g.functors.highest >= 337
        for (k, (a, arity)) in enumerate(LK._BUILTIN_FUNCTORS)
            fd = LK.fetchFunctorArray(g.functors, k)
            @test fd.name == _ft_atom_word(a) && fd.arity == arity &&
                LK.indexFunctor(fd.functor) == k
        end
        for k in 337:(g.functors.highest - 1)
            fd = LK.fetchFunctorArray(g.functors, k)
            @test LK.indexFunctor(fd.functor) == k
            @test LK.lookupFunctorDef(g.functors, fd.name, fd.arity) == fd.functor   # found, not made
            @test LK.isCurrentFunctor(g.functors, fd.name, fd.arity) == fd.functor
        end
    end
    h = gd1.functors.highest
    a = LK.lookupAtom(gd1.atoms, Vector{UInt8}(codeunits("only_in_one")))
    w = LK.lookupFunctorDef(gd1.functors, a, 1)
    @test LK.isCurrentFunctor(gd2.functors, a, 1) == 0                    # gd2 has not got it
    @test gd2.functors.highest == h && gd1.functors.highest == h + 1
    @test LK.lookupFunctorDef(gd1.functors, a, 1) == w
end
