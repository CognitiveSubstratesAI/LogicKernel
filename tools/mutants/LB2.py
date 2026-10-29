# ORIGINAL: LB2's mutant list — no swipl-devel counterpart.
# tools/mutants/LB2.py — the mutation battery of LB2 (R2 loader_boot: the pl-srcfile.c predicates '$source_file'/2,
# '$source_file_predicates'/2, '$time_source_file'/3, '$source_file_property'/3, '$set_source_file'/3, '$start_consult'/2,
# '$end_consult'/1, '$fixup_reconsult'/1; source_location/2; system mode and the P_LOCKED sites; audit D-0244), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must
# occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# TARGETS (D-0238): the step's own file plus EVERY test file that loads a source file through the mutated sites (the loader, clause
# assert/retract, the module / operator / flag tests that read ReadingSource, SYSTEM_MODE and the source-file table).
# NOT RUN YET (written edit-only, 2026-10-29): the verdict column is what the rows are DESIGNED to kill. Expected survivors, to be
# looked at first:
#   * LB2-26 (associateSource without the P_LOCKED bit): assert_term (pl-comp.c:5015) sets the same bits on a clause-defined
#     predicate, so only a predicate defined by a declaration alone (`dynamic`) in system mode shows it: if it survives, add that row;
#   * LB2-30 (the FRG_CUTTED answer) is observable only if the caller reads the result of the cut call.
T = ["test/db/test_source_file_swipl.jl"]
S = T + [
    "test/files/test_load_swipl.jl",
    "test/db/test_clause_ref_swipl.jl",
    "test/db/test_clause_swipl.jl",
    "test/db/test_retract_swipl.jl",
    "test/core_lang/test_module_swipl.jl",
    "test/core_lang/test_current_op_swipl.jl",
    "test/core_lang/test_prolog_flag_swipl.jl",
    "test/compile/test_compiler_warnings_swipl.jl",
]
SF = "src/pl-srcfile.jl"
MUTANTS = [
    # ---- '$source_file'/2 and '$source_file_predicates'/2
    dict(id="LB2-1 $source_file_predicates walks the oldest predicate first", file=SF, targets=S,
         old='''Iterators.reverse(sf.procedures)''',
         new='''sf.procedures'''),
    dict(id="LB2-2 $source_file looks an unqualified head up in user", file=SF, targets=S,
         old='''get_procedure_findhere(gd, ld, descr, MODULE_system(gd))''',
         new='''get_procedure_findhere(gd, ld, descr, MODULE_user(gd))'''),
    dict(id="LB2-3 a qualifier naming no module fails the lookup path (nothing) instead of user", file="src/pl-proc.jl", targets=S,
         old='''        m === nothing && (m = MODULE_user(gd))''',
         new='''        m === nothing && return nothing'''),
    dict(id="LB2-4 $source_file_predicates answers for a file nothing has started", file=SF, targets=S,
         old='''        if sf.count > 0
            tail''',
         new='''        if true
            tail'''),
    # ---- '$time_source_file'/3
    dict(id="LB2-5 $time_source_file starts at the second file", file=SF, targets=S,
         old='''        index = 0
''',
         new='''        index = 2
'''),
    dict(id="LB2-6 $time_source_file lists a file nothing has started", file=SF, targets=S,
         old='''if !(f === nothing || f.count == 0)''',
         new='''if f !== nothing'''),
    dict(id="LB2-7 the time of a real file is 0", file=SF, targets=S,
         old='''    f.isfile && return PL_unify_float(ld, t, f.mtime)''',
         new='''    !f.isfile && return PL_unify_float(ld, t, f.mtime)'''),
    dict(id="LB2-8 the type of a file is swapped", file=SF, targets=S,
         old='''f.system ? :system : :user''',
         new='''f.system ? :user : :system'''),
    dict(id="LB2-9 the redo context is not advanced", file=SF, targets=S,
         old='''                return PL_retry(index + 1)''',
         new='''                return PL_retry(index)'''),
    dict(id="LB2-30 a cut $time_source_file call fails", file=SF, targets=S,
         old='''        return FTRUE                                    # FRG_CUTTED''',
         new='''        return FFALSE                                   # FRG_CUTTED'''),
    # ---- '$source_file_property'/3, '$set_source_file'/3
    dict(id="LB2-10 reloading is true", file=SF, targets=S,
         old='''PL_unify_bool(ld, A3, false)''',
         new='''PL_unify_bool(ld, A3, true)'''),
    dict(id="LB2-11 loaded of an unknown file succeeds", file=SF, targets=S,
         old='''rc = (sf === nothing || sf.ltime == 0.0) ? false : PL_unify_float(ld, A3, sf.ltime)''',
         new='''rc = sf === nothing ? true : PL_unify_float(ld, A3, sf.ltime)'''),
    dict(id="LB2-12 loaded of a never-loaded file answers 0.0", file=SF, targets=S,
         old='''rc = (sf === nothing || sf.ltime == 0.0) ? false : PL_unify_float(ld, A3, sf.ltime)''',
         new='''rc = sf === nothing ? false : PL_unify_float(ld, A3, sf.ltime)'''),
    dict(id="LB2-13 $set_source_file stores the negated value", file=SF, targets=S,
         old='''sf.resource = v ''',
         new='''sf.resource = !v '''),
    dict(id="LB2-14 $source_file_property does not release its reference", file=SF, targets=S,
         old='''    sf === nothing || releaseSourceFile(sf)''',
         new='''    nothing'''),
    dict(id="LB2-15 $set_source_file does not release its reference", file=SF, targets=S,
         old='''        releaseSourceFile(sf)
        return rc ? FTRUE : FFALSE''',
         new='''        return rc ? FTRUE : FFALSE'''),
    # ---- '$start_consult'/2, '$end_consult'/1, '$fixup_reconsult'/1
    dict(id="LB2-16 $start_consult treats 0 as a time", file=SF, targets=S,
         old='''if i !== nothing && i == 0''',
         new='''if i !== nothing && i != 0'''),
    dict(id="LB2-17 $start_consult does not record the time", file=SF, targets=S,
         old='''    sf.mtime = mtime''',
         new='''    sf.mtime = 0.0'''),
    dict(id="LB2-18 $end_consult does not release the lookup's reference", file=SF, targets=S,
         old='''            rc = endConsult(sf)
            releaseSourceFile(sf)''',
         new='''            rc = endConsult(sf)'''),
    dict(id="LB2-19 $fixup_reconsult does not release the lookup's reference", file=SF, targets=S,
         old='''            releaseSourceFile(sf)
            sf.current_procedure = nothing''',
         new='''            sf.current_procedure = nothing'''),
    # ---- the source-file table
    dict(id="LB2-20 addModuleSourceFile does not look for the module first", file=SF, targets=S,
         old='''        x === m && return true''',
         new='''        false && return true'''),
    dict(id="LB2-21 addModuleSourceFile adds at the front", file=SF, targets=S,
         old='''    push!(sf.modules, m)''',
         new='''    pushfirst!(sf.modules, m)'''),
    dict(id="LB2-22 highSourceFileIndex is off by one", file=SF, targets=S,
         old='''length(gd.files_array) + 1''',
         new='''length(gd.files_array)'''),
    dict(id="LB2-23 a boot-session file is not a system file", file=SF, targets=S,
         old='''boot = gd.bootsession ''',
         new='''boot = false '''),
    # ---- system mode
    dict(id="LB2-24 SYSTEM_MODE is never on", file="src/pl-global.jl", targets=S,
         old='''= ld.prolog_flag_access_level == ACCESS_LEVEL_SYSTEM''',
         new='''= false'''),
    dict(id="LB2-25 assert_term locks without P_LOCKED", file="src/pl-comp.jl", targets=S,
         old='''(def.flags & P_LOCKED) == 0 && (def.flags |= HIDE_CHILDS | P_LOCKED)''',
         new='''(def.flags & P_LOCKED) == 0 && (def.flags |= HIDE_CHILDS)'''),
    dict(id="LB2-26 associateSource locks without P_LOCKED", file=SF, targets=S,
         old='''def.flags |= P_LOCKED | HIDE_CHILDS''',
         new='''def.flags |= HIDE_CHILDS'''),
    dict(id="LB2-27 isStaticSystemProcedure ignores system mode", file="src/pl-proc.jl", targets=S,
         old='''    SYSTEM_MODE(ld) && return nothing ''',
         new='''    false && return nothing '''),
    dict(id="LB2-28 the access_level flag is swapped", file="src/os/pl-prologflag.jl", targets=S,
         old='''SYSTEM_MODE(ld) ? :system : :user''',
         new='''SYSTEM_MODE(ld) ? :user : :system'''),
    dict(id="LB2-29 op/3 ignores system mode", file="src/pl-op.jl", targets=S,
         old='''if !force && !SYSTEM_MODE(ld::PL_local_data{T})''',
         new='''if !force && SYSTEM_MODE(ld::PL_local_data{T})'''),
    # ---- source_location/2
    dict(id="LB2-31 ReadingSource is false at line 0 again", file="src/pl-modul.jl", targets=S,
         old='''ld.read_source.position.lineno >= 0 && ''',
         new='''ld.read_source.position.lineno > 0 && '''),
    dict(id="LB2-32 source_location/2 answers the line plus one", file="src/os/pl-file.jl", targets=S,
         old='''PL_unify_integer(ld, A2, ld.read_source.position.lineno)''',
         new='''PL_unify_integer(ld, A2, ld.read_source.position.lineno + 1)'''),
]
