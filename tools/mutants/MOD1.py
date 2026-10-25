# ORIGINAL: MOD1's mutant list — no swipl-devel counterpart.
# tools/mutants/MOD1.py — the mutation battery of MOD1 (the module table, the super modules, the source and typein
# modules, '$module_property'/2, set_module/1; audit D-0149), run ONCE, in CI (.github/workflows/mutation.yml; locally:
# tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`,
# optional `equivalent` and `targets`. One mutant per decision of src/pl-modul.jl: the creation of a module (its class,
# its super, its flags, its place in the table), the super-module list (add at either end, no duplicate, delete, set,
# clear, the cycle check, the level), set_module's properties and errors, '$module_property' and the byte counts.
# TS is the live differential and the white-box testsets (test/core_lang/test_module_swipl.jl), TP the unit file of
# the module path (test/core_lang/test_module_path.jl).
# EQUIVALENT, with the reason: MOD1-S15 (the last super tested by the loop or by the recursion gives one truth value);
# MOD1-P17 (the only limit that reaches the store is 0, which `code_limit` already is); MOD1-B4 (a foreign
# definition has no clauses to count).
# BOOT-SAFE (5b257b3's battery, run 40212283129): T1, T3 and T4 first broke EVERY module, `system` and `user` included;
# the precompile workload (src/precompile_workload.jl) builds a database while a fresh CI process precompiles, so the
# package did not load and no test could run (NO VERDICT (does not load), D-0050). They now break only a module made
# after boot (index > 2: pl-global.jl makes system, then user), which every module row of TS makes.
# NOT mutated: the exports loop over `keys(m.public_)` (a Julia Dict iterates in insertion order while nothing is
# deleted — indistinguishable from `public_order` in a test); the level of a module made by `_lookupModule!` is
# the same code as `addSuperModule_no_lock`'s (S5).
# The `old` strings were written BEFORE `tools/warm.sh fmt`: re-check them after it (mutate_drive.py refuses a string
# that does not occur exactly once).
TS = ["test/core_lang/test_module_swipl.jl"]
TP = ["test/core_lang/test_module_path.jl"]
TARGETS = TS + TP                                   # the baseline's targets (mutate_ci.py plan reads TARGETS)
M = "src/pl-modul.jl"
I = "src/pl-incl.jl"
MUTANTS = [
    # ---- the table and the creation of a module
    dict(id="MOD1-T1 a lookup never finds a module made after boot", file=M, targets=TS,
         old='''    return i == 0 ? nothing : modules.modules[i]''',
         new='''    return i == 0 || i > 2 ? nothing : modules.modules[i]'''),
    dict(id="MOD1-T2 a module is created again on every lookup", file=M, targets=TS,
         old='''    m0 === nothing || return m0''',
         new='''    nothing'''),
    dict(id="MOD1-T3 a module made after boot is not entered in the name index", file=M, targets=TS + TP,
         old='''    modules.names[m.name] = m.index''',
         new='''    m.index > 2 || (modules.names[m.name] = m.index)'''),
    dict(id="MOD1-T4 a module made after boot gets its predecessor's index", file=M, targets=TS,
         old='''        sym_key(name), name, length(modules.modules) + 1, class, 0,''',
         new='''        sym_key(name), name, length(modules.modules) + (length(modules.modules) < 2), class, 0,'''),
    dict(id="MOD1-T5 a module's syntax flags are not set", file=M, targets=TS + TP,
         old='''    flags |= DBLQ_STRING | BQ_CODES | O_RATIONAL_SYNTAX     # !GD->options.traditional''',
         new='''    flags |= O_RATIONAL_SYNTAX     # !GD->options.traditional'''),
    dict(id="MOD1-T6 user's class is system", file=M, targets=TS,
         old='''    class = mk_sym(T, :user)                        # m->class = ATOM_user''',
         new='''    class = mk_sym(T, :system)                      # m->class = ATOM_user'''),
    dict(id="MOD1-T7 system's class is user", file=M, targets=TS,
         old='''        flags |= M_SYSTEM | UInt32(UNKNOWN_ERROR)   # set(m, M_SYSTEM|UNKNOWN_ERROR)
        class = mk_sym(T, :system)''',
         new='''        flags |= M_SYSTEM | UInt32(UNKNOWN_ERROR)   # set(m, M_SYSTEM|UNKNOWN_ERROR)
        class = mk_sym(T, :user)'''),
    dict(id="MOD1-T8 a name starting with $ is not a system module", file=M, targets=TS,
         old='''    elseif sym_first_byte(name) == 0x24             # stringAtom(name)[0] == '$\'''',
         new='''    elseif false                                    # stringAtom(name)[0] == '$\''''),
    dict(id="MOD1-T9 a $-module is not flagged M_SYSTEM", file=M, targets=TS,
         old='''        flags |= M_SYSTEM
        class = mk_sym(T, :system)
        super =''',
         new='''        class = mk_sym(T, :system)
        super ='''),
    dict(id="MOD1-T10 a $-module's super is user", file=M, targets=TS,
         old='''        class = mk_sym(T, :system)
        super = isCurrentModule(modules, mk_sym(T, :system))
        super === nothing && error("_lookupModule: `\\$`-module before `system`")''',
         new='''        class = mk_sym(T, :system)
        super = isCurrentModule(modules, mk_sym(T, :user))
        super === nothing && error("_lookupModule: `\\$`-module before `system`")'''),
    dict(id="MOD1-T11 an ordinary module's super is system", file=M, targets=TS + TP,
         old='''        super = isCurrentModule(modules, mk_sym(T, :user))
        super === nothing && error("_lookupModule: a module before `user`")''',
         new='''        super = isCurrentModule(modules, mk_sym(T, :system))
        super === nothing && error("_lookupModule: a module before `user`")'''),
    dict(id="MOD1-T12 a qualifier's module is user", file=M, targets=TP,
         old='''        m = lookupModule(gd, _atom_value(ld, nm)).index''',
         new='''        m = MODULE_user(gd).index'''),
    # ---- the super modules
    dict(id="MOD1-S1 a module is not reachable from itself", file=M, targets=TS,
         old='''    here === end_ && return true''',
         new='''    here === end_ && return false'''),
    dict(id="MOD1-S2 reachability does not follow the supers", file=M, targets=TS,
         old='''        reachableModule(modules, modules[c], end_) && return true''',
         new='''        false && return true'''),
    dict(id="MOD1-S3 a super already there is added again", file=M, targets=TS,
         old='''        c == s.index && return true                 # already a super-module''',
         new='''        false && return true                        # already a super-module'''),
    dict(id="MOD1-S4 start and end are swapped", file=M, targets=TS,
         old='''    if where_ == 'A\'''',
         new='''    if where_ != 'A\''''),
    dict(id="MOD1-S5 a new super does not update the level", file=M, targets=TS,
         old='''        push!(m.supers, s.index)
    end
    updateLevelModule(modules, m)''',
         new='''        push!(m.supers, s.index)
    end'''),
    dict(id="MOD1-S6 the level is one less than the highest super's", file=M, targets=TS,
         old='''    m.level = l + 1''',
         new='''    m.level = l'''),
    dict(id="MOD1-S7 the level is taken from the lowest super", file=M, targets=TS,
         old='''        if m2.level > l''',
         new='''        if l < 0 || m2.level < l'''),
    dict(id="MOD1-S8 a super is not deleted", file=M, targets=TS,
         old='''    deleteat!(m.supers, i)''',
         new='''    nothing'''),
    dict(id="MOD1-S9 a delete does not update the level", file=M, targets=TS,
         old='''    deleteat!(m.supers, i)
    updateLevelModule(modules, m)''',
         new='''    deleteat!(m.supers, i)'''),
    dict(id="MOD1-S10 clearing the supers keeps the level", file=M, targets=TS,
         old='''    empty!(m.supers)
    m.level = 0''',
         new='''    empty!(m.supers)'''),
    dict(id="MOD1-S11 clearing the supers leaves them", file=M, targets=TS,
         old='''    empty!(m.supers)''',
         new='''    nothing'''),
    dict(id="MOD1-S12 setting the only super keeps the level", file=M, targets=TS,
         old='''            m.level = s.level + 1
            return true''',
         new='''            return true'''),
    dict(id="MOD1-S13 a module can be its own super by set_module", file=M, targets=TS,
         old='''    s === m && return cannotSetSuperModule(ld, m, s)''',
         new='''    false && return cannotSetSuperModule(ld, m, s)'''),
    dict(id="MOD1-S14 several supers are replaced in place, not cleared", file=M, targets=TS,
         old='''    if length(m.supers) == 1                        # m->supers && !m->supers->next''',
         new='''    if length(m.supers) >= 1                        # m->supers && !m->supers->next'''),
    dict(id="MOD1-S15 the last super is searched by the recursion too", file=M, targets=TS,
         old='''        for i in 1:(length(sup) - 1)                # (c->next)''',
         new='''        for i in 1:length(sup)                      # (c->next)''',
         equivalent="src/pl-modul.jl isSuperModule: recursing into the last super instead of looping on it "
                    "gives the same truth value; only the depth of the stack differs"),
    dict(id="MOD1-S16 isSuperModule does not search the earlier supers", file=M, targets=TS,
         old='''            isSuperModule(modules, s, modules[sup[i]]) && return true''',
         new='''            false && return true'''),
    dict(id="MOD1-S17 isSuperModule follows the first super, not the last", file=M, targets=TS,
         old='''        m = modules[sup[end]]                       # m = c->value; goto next''',
         new='''        m = modules[sup[1]]                         # m = c->value; goto next'''),
    dict(id="MOD1-S18 the cycle error names the new super", file=M, targets=TS,
         old='''    PL_put_atom(ld, t, m.atom)''',
         new='''    PL_put_atom(ld, t, s.atom)'''),
    dict(id="MOD1-S19 the cycle error has another message", file=M, targets=TS,
         old='''"would create a cycle"''',
         new='''"cycle"'''),
    dict(id="MOD1-S20 the cycle error has another action", file=M, targets=TS,
         old='''ERR_PERMISSION, mk_sym(T, :add_import),''',
         new='''ERR_PERMISSION, mk_sym(T, :import),'''),
    # ---- the predicates
    dict(id="MOD1-P1 get_module does not create", file=M, targets=TS,
         old='''    create && return lookupModule(gd, name)''',
         new='''    false && return lookupModule(gd, name)'''),
    dict(id="MOD1-P2 add_import_module appends at start", file=M, targets=TS,
         old='''    return addSuperModule(gd.modules, ld, me, super, start ? 'A' : 'Z') ? FTRUE : FFALSE''',
         new='''    return addSuperModule(gd.modules, ld, me, super, start ? 'Z' : 'A') ? FTRUE : FFALSE'''),
    dict(id="MOD1-P3 add_import_module always adds at start", file=M, targets=TS,
         old='''    start = sym_key(at) == sym_key(mk_sym(T, :start))''',
         new='''    start = true'''),
    dict(id="MOD1-P4 delete_import_module always succeeds", file=M, targets=TS,
         old='''    return delSuperModule(gd.modules, me, super) ? FTRUE : FFALSE''',
         new='''    return delSuperModule(gd.modules, me, super) ? FTRUE : FTRUE'''),
    dict(id="MOD1-P5 set_module(base(M)) adds M first instead of setting it", file=M, targets=TS,
         old='''            return setSuperModule(gd.modules, ld, m, lookupModule(gd, mname))''',
         new='''            return addSuperModule(gd.modules, ld, m, lookupModule(gd, mname), 'A')'''),
    dict(id="MOD1-P6 class user is not a class", file=M, targets=TS,
         old='''            if sym_key(class) == sym_key(mk_sym(T, :user)) ||''',
         new='''            if false ||'''),
    dict(id="MOD1-P7 class system is not a class", file=M, targets=TS,
         old='''                sym_key(class) == sym_key(mk_sym(T, :system)) ||''',
         new='''                false ||'''),
    dict(id="MOD1-P8 class library is not a class", file=M, targets=TS,
         old='''                sym_key(class) == sym_key(mk_sym(T, :library)) ||''',
         new='''                false ||'''),
    dict(id="MOD1-P9 class test is not a class", file=M, targets=TS,
         old='''                sym_key(class) == sym_key(mk_sym(T, :test)) ||''',
         new='''                false ||'''),
    dict(id="MOD1-P10 class development is not a class", file=M, targets=TS,
         old='''                sym_key(class) == sym_key(mk_sym(T, :development))
''',
         new='''                false
'''),
    dict(id="MOD1-P11 a non-empty module becomes temporary", file=M, targets=TS,
         old='''                if sym_key(m.class) == sym_key(mk_sym(T, :user)) && isempty(m.procedures)''',
         new='''                if sym_key(m.class) == sym_key(mk_sym(T, :user))'''),
    dict(id="MOD1-P12 a module of another class than user becomes temporary", file=M, targets=TS,
         old='''                if sym_key(m.class) == sym_key(mk_sym(T, :user)) && isempty(m.procedures)''',
         new='''                if isempty(m.procedures)'''),
    dict(id="MOD1-P13 the temporary class is not set", file=M, targets=TS,
         old='''                    m.class = class
                else''',
         new='''                    nothing
                else'''),
    dict(id="MOD1-P14 the temporary refusals swap their messages", file=M, targets=TS,
         old='''                        if sym_key(m.class) != sym_key(mk_sym(T, :user))''',
         new='''                        if sym_key(m.class) == sym_key(mk_sym(T, :user))'''),
    dict(id="MOD1-P15 an unknown class is a property error", file=M, targets=TS,
         old='''                return PL_error(ld, ERR_DOMAIN, mk_sym(T, :module_class), arg)''',
         new='''                return PL_error(ld, ERR_DOMAIN, mk_sym(T, :module_property), arg)'''),
    dict(id="MOD1-P16 program_space(N) is stored for N > 0", file=M, targets=TS,
         old='''            limit != 0 && throw(''',
         new='''            false && throw('''),
    dict(id="MOD1-P17 program_space(N) does not store N = 0", file=M, targets=TS,
         old='''            m.code_limit = limit''',
         new='''            nothing''',
         equivalent="src/pl-modul.jl set_module: only the limit 0 reaches this store (a limit above 0 raises NotPortedError "
                    "above it), and code_limit is 0 already"),
    dict(id="MOD1-P18 an unknown property is a type error", file=M, targets=TS,
         old='''            return PL_error(ld, ERR_DOMAIN, mk_sym(T, :module_property), prop)''',
         new='''            return PL_error(ld, ERR_TYPE, mk_sym(T, :module_property), prop)'''),
    dict(id="MOD1-P19 a property of arity 0 is looked up as a property", file=M, targets=TS,
         old='''    if na !== nothing && na[2] == 1
        pname = na[1]''',
         new='''    if na !== nothing
        pname = na[1]'''),
    dict(id="MOD1-P20 set_source_module sets the typein module", file=M, targets=TS,
         old='''    ld.modules_source = lookupModule(gd, name).index''',
         new='''    ld.modules_typein = lookupModule(gd, name).index'''),
    dict(id="MOD1-P21 set_typein_module sets the source module", file=M, targets=TS,
         old='''    ld.modules_typein = lookupModule(gd, name).index''',
         new='''    ld.modules_source = lookupModule(gd, name).index'''),
    dict(id="MOD1-P22 current_source_module answers the typein module", file=M, targets=TS,
         old='''    return PL_unify_atom(ld, PL__t0, gd.modules[ld.modules_source].atom) ? FTRUE : FFALSE''',
         new='''    return PL_unify_atom(ld, PL__t0, gd.modules[ld.modules_typein].atom) ? FTRUE : FFALSE'''),
    dict(id="MOD1-P23 current_typein_module answers the source module", file=M, targets=TS,
         old='''    return PL_unify_atom(ld, PL__t0, gd.modules[ld.modules_typein].atom) ? FTRUE : FFALSE''',
         new='''    return PL_unify_atom(ld, PL__t0, gd.modules[ld.modules_source].atom) ? FTRUE : FFALSE'''),
    # ---- MODULE_parse and ReadingSource
    dict(id="MOD1-R1 MODULE_parse is the typein module while loading too", file=M, targets=TS,
         old='''    ReadingSource(ld) ? ld.modules_source : ld.modules_typein''',
         new='''    ReadingSource(ld) ? ld.modules_typein : ld.modules_typein'''),
    dict(id="MOD1-R4 MODULE_parse is the source module outside a load too", file=M, targets=TS,
         old='''    ReadingSource(ld) ? ld.modules_source : ld.modules_typein''',
         new='''    ReadingSource(ld) ? ld.modules_source : ld.modules_source'''),
    dict(id="MOD1-R2 a file at line 0 is being read", file=M, targets=TS,
         old='''    ld.read_source.position.lineno > 0 && ld.read_source.file !== nothing''',
         new='''    ld.read_source.position.lineno >= 0 && ld.read_source.file !== nothing'''),
    dict(id="MOD1-R3 a line without a file is being read", file=M, targets=TS,
         old='''    ld.read_source.position.lineno > 0 && ld.read_source.file !== nothing''',
         new='''    ld.read_source.position.lineno > 0'''),
    # ---- '$module_property'/2
    dict(id="MOD1-Q1 line_count answers when there is no line", file=M, targets=TS,
         old='''        m.line_no > 0 || return FFALSE''',
         new='''        nothing'''),
    dict(id="MOD1-Q2 file answers when there is no file", file=M, targets=TS,
         old='''        m.file != 0 || return FFALSE''',
         new='''        m.file != 0 || return FTRUE'''),
    dict(id="MOD1-Q3 program_space answers without a limit", file=M, targets=TS,
         old='''        m.code_limit != 0 || return FFALSE''',
         new='''        nothing'''),
    dict(id="MOD1-Q4 size answers the program size", file=M, targets=TS,
         old='''        return PL_unify_int64(ld, a, sizeof_module(m)) ? FTRUE : FFALSE''',
         new='''        return PL_unify_int64(ld, a, module_code_size(m)) ? FTRUE : FFALSE'''),
    dict(id="MOD1-Q5 last_modified_generation answers 0", file=M, targets=TS,
         old='''        return PL_unify_int64(ld, a, Int(m.last_modified)) ? FTRUE : FFALSE''',
         new='''        return PL_unify_int64(ld, a, 0) ? FTRUE : FFALSE'''),
    dict(id="MOD1-Q6 the exports are heads, not Name/Arity", file=M, targets=TS,
         old='''            unify_functor(ld, head, m.public_[key].definition, GP_NAMEARITY)''',
         new='''            unify_functor(ld, head, m.public_[key].definition, 0)'''),
    dict(id="MOD1-Q7 the exports list is not closed", file=M, targets=TS,
         old='''    return PL_unify_nil(ld, list)''',
         new='''    return true'''),
    dict(id="MOD1-Q8 the class property answers system", file=M, targets=TS,
         old='''        return PL_unify_atom(ld, a, m.class) ? FTRUE : FFALSE''',
         new='''        return PL_unify_atom(ld, a, mk_sym(T, :system)) ? FTRUE : FFALSE'''),
    dict(id="MOD1-Q9 a property of an unknown module creates it", file=M, targets=TS,
         old='''    m = get_module(gd, ld, A1, false)''',
         new='''    m = get_module(gd, ld, A1, true)'''),
    dict(id="MOD1-Q10 an unknown property is a type error", file=M, targets=TS,
         old='''        return PL_error(ld, ERR_DOMAIN, mk_sym(T, :module_property), A2) ? FTRUE : FFALSE''',
         new='''        return PL_error(ld, ERR_TYPE, mk_sym(T, :module_property), A2) ? FTRUE : FFALSE'''),
    # ---- the byte counts (D-0149 MQ3)
    dict(id="MOD1-B1 a clause counts 4 bytes a word", file=M, targets=TS,
         old='''                bytes += 8 * (sizeofClause(length(cl.codes)) + SIZEOF_CREF_CLAUSE)''',
         new='''                bytes += 4 * (sizeofClause(length(cl.codes)) + SIZEOF_CREF_CLAUSE)'''),
    dict(id="MOD1-B2 a clause erased still counts", file=M, targets=TS,
         old='''            if (cl.flags & CL_ERASED) == 0          # retract subtracts the clause's size at once''',
         new='''            if true                                 # retract subtracts the clause's size at once'''),
    dict(id="MOD1-B3 a procedure of another module counts", file=M, targets=TS,
         old='''        def.module_ == m.index || continue          # def->module == m''',
         new='''        nothing                                     # def->module == m'''),
    dict(id="MOD1-B4 a foreign definition is not skipped", file=M, targets=TS,
         old='''        (def.flags & P_FOREIGN) == 0 || continue''',
         new='''        nothing''',
         equivalent="src/pl-modul.jl module_code_size: a foreign definition has an empty clause list "
                    "(src/pl-ext.jl registerBuiltins! sets impl_foreign_function, never a clause), so the walk adds nothing"),
    dict(id="MOD1-B5 a procedure record is not counted in the module's size", file=M, targets=TS,
         old='''    return module_code_size(m) + 16 * length(m.procedures)''',
         new='''    return module_code_size(m)'''),
    # ---- the record (src/pl-incl.jl)
    dict(id="MOD1-I1 M_DESTROYED is another bit", file=I, targets=TS,
         old='''const M_DESTROYED = UInt32(0x00010000)''',
         new='''const M_DESTROYED = UInt32(0x00020000)'''),
]
