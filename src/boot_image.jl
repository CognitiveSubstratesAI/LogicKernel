# ORIGINAL: the kernel's readers of a booted database (R2 LB4 b1-3, loader_boot design LD4 tables T1 and T3) — upstream reads these tables back through Prolog (boot/syspred.pl over `$get_predicate_attribute/3`, `$time_source_file/3`, `$source_file_property/3`); the kernel boots without syspred.pl (loader_boot.md:380), so b2's boot check reads them from the database itself.
#
# THE BOOT-IMAGE READERS. After the boot (b2) the database holds every predicate and source file the boot made. These two
# readers return that content as plain rows (strings, integers, booleans: no term type), in an order that does not depend
# on the hash order of the tables, so a row set can be pinned (T1: the predicates, T3: the source files) and compared
# between the term types, and with swipl's `predicate_property/2` and `$source_file_property/3`.
#   * `boot_image_predicates(gd)` — T1: a row per predicate DEFINED in a module (an entry of a module's table that the
#     module imported is the importing module's alias of a row already listed under its own module, and is left out).
#     The columns are `'$get_predicate_attribute'/3`'s (pl-proc.c:3600-3660): `defined` (isDefinedProcedure), `dynamic`,
#     `foreign`, `locked` (P_LOCKED, the property `system`), `iso`, `transparent`, `meta` (P_META), `public` (P_PUBLIC),
#     `exported` (the module's public table), `number_of_clauses`.
#   * `boot_image_source_files(gd)` — T3: a row per loaded source file, in the order of `'$time_source_file'/3`
#     (pl-srcfile.c:655-699: by index, a file with `count == 0` skipped), with `'$source_file_property'/3`'s columns
#     (pl-srcfile.c:702-733).
# Reading only: neither function changes the database.

"""
A row of T1 (`boot_image_predicates`): one predicate of a module and the attributes `'\$get_predicate_attribute'/3` answers
for it. `number_of_clauses` is `nothing` where upstream's answer FAILS (pl-proc.c:3648-3658: a foreign predicate, or a
static one with no clause).
"""
struct BootImagePredicate
    module_name::String
    name::String
    arity::Int
    defined::Bool
    dynamic::Bool
    foreign::Bool
    locked::Bool
    iso::Bool
    transparent::Bool
    meta::Bool
    public::Bool
    exported::Bool
    number_of_clauses::Union{Nothing, Int}
end

"""
A row of T3 (`boot_image_source_files`): one loaded source file. `loaded` is `nothing` where upstream's `loaded` property
FAILS (no load time); `file_time` is `'\$time_source_file'/3`'s time (the file's modification time, 0.0 for a non-file).
"""
struct BootImageSourceFile
    index::Int
    name::String
    type::Symbol
    file_time::Float64
    load_count::Int
    number_of_clauses::Int
    resource::Bool
    from_state::Bool
    loaded::Union{Nothing, Float64}
    reloading::Bool
    modules::Vector{String}
end

# PORT: pl-proc.c num_visible_clauses (the ATOM_number_of_clauses case)
# DIVERGES: the reload context is NOT PORTED (`LD->reload.generation` stays invalid), so only a dynamic predicate counts the visible
# clauses; the generation is the database's (`current_generation(def)` without a transaction).
"The number of clauses of `def` visible now: the list's count, recounted for a dynamic predicate (pl-proc.c)."
function _num_visible_clauses(gd::PL_global_data{T}, def::Definition{T})::Int where {T}
    count = Int(def.impl_clauses.number_of_clauses)
    if count > 0 && (def.flags & P_DYNAMIC) != 0
        gen = global_generation(gd)
        count = 0
        cref = def.impl_clauses.first_clause
        while cref !== nothing
            visibleClauseCNT(cref.clause::Clause{T}, gen) && (count += 1)
            cref = cref.next
        end
    end
    return count
end

# PORT: pl-proc.c pl_get_predicate_attribute, the number_of_clauses case (pl-proc.c:3648-3658)
"The `number_of_clauses` attribute of `def`, or `nothing` where upstream's attribute fails (pl-proc.c:3648-3658)."
function _predicate_number_of_clauses(
    gd::PL_global_data{T}, def::Definition{T}
)::Union{Nothing, Int} where {T}
    (def.flags & P_FOREIGN) != 0 && return nothing
    n = _num_visible_clauses(gd, def)
    (n == 0 && (def.flags & P_DYNAMIC) == 0) && return nothing
    return n
end

"""
    boot_image_predicates(gd) -> Vector{BootImagePredicate}

T1 of the boot image: a row per predicate defined in a module of `gd`, sorted by module name, predicate name and arity
(see the comment at the top of src/boot_image.jl). Reads the definition tables; runs no Prolog.
"""
function boot_image_predicates(gd::PL_global_data{T})::Vector{BootImagePredicate} where {T}
    rows = BootImagePredicate[]
    for m in gd.modules
        mname = sym_text(m.atom)
        for (key, proc) in m.procedures
            def = proc.definition
            def.module_ == m.index || continue          # an import: listed under its own module
            fl = def.flags
            push!(
                rows,
                BootImagePredicate(
                    mname,
                    sym_text(def.name),
                    def.arity,
                    isDefinedProcedure(gd, proc),
                    (fl & P_DYNAMIC) != 0,
                    (fl & P_FOREIGN) != 0,
                    (fl & P_LOCKED) != 0,
                    (fl & P_ISO) != 0,
                    (fl & P_TRANSPARENT) != 0,
                    (fl & P_META) != 0,
                    (fl & P_PUBLIC) != 0,
                    haskey(m.public_, key),
                    _predicate_number_of_clauses(gd, def)
                )
            )
        end
    end
    sort!(rows; by = r -> (r.module_name, r.name, r.arity))
    return rows
end

"""
    boot_image_source_files(gd) -> Vector{BootImageSourceFile}

T3 of the boot image: a row per loaded source file of `gd` (`count != 0`), in the order of `'\$time_source_file'/3`: by
index (see the comment at the top of src/boot_image.jl).
"""
function boot_image_source_files(gd::PL_global_data{T})::Vector{BootImageSourceFile} where {T}
    rows = BootImageSourceFile[]
    mx = highSourceFileIndex(gd)
    index = 0
    while index < mx                                    # pl-srcfile.c:296-330's loop
        f = indexToSourceFile(gd, index)
        if f !== nothing && f.count != 0
            push!(
                rows,
                BootImageSourceFile(
                    f.index,
                    sym_text(f.name),
                    f.system ? :system : :user,
                    f.isfile ? f.mtime : 0.0,           # unify_src_file_time
                    f.count,
                    Int(f.number_of_clauses),
                    f.resource,
                    f.from_state,
                    f.ltime == 0.0 ? nothing : f.ltime,
                    false,                              # `reloading`: the reload context is NOT PORTED
                    String[sym_text(mm.atom) for mm in f.modules]
                )
            )
        end
        index += 1
    end
    return rows
end
