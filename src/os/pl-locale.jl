# UPSTREAM: swipl-devel src/os/pl-locale.c @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-thread.h @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-thread.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2013-2022, VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# LOCALES (pl-locale.c), CT1 LOCALE: the locale object (`PL_locale_rec`, src/pl-global.jl), the table of the aliased locales,
# the system default and the current locale, the `locale` blob, and `locale_property/2`, `locale_create/3`,
# `locale_destroy/1`, `set_locale/1`, `current_locale/1`. The host parts (`newlocale`, `uselocale`, `freelocale`, `localeconv`)
# are `ccall`s to libc. UNTESTED: written without a compile (CT1 writer lane E, edit-only).
#
# DIVERGES (the design changes, all of them):
#   * The locale table is a `Vector` in creation order, not a hash table: the order in which `locale_property(-L, ...)`
#     enumerates several locales is NOT upstream's (rows must not enumerate more than one locale).
#   * The strings are `String`s (upstream `wchar_t *`). `ls_to_wcs` reads the bytes of `localeconv()` as UTF-8: invalid UTF-8,
#     or 16 or more characters (`LSTR_MAX`), print "Illegal locale string: ..." on stderr (`Sdprintf`) and give the fallback.
#   * A stream carries its locale (`IOSTREAM.locale`, LOCALE-FMT-1) and format/2's `~:d` and `~:f` read it. `Snew` (src/os/
#     pl-stream.jl) has no database, so it does not call `initStreamLocale`: the places that make a stream Prolog writes to
#     and have the database call it (`openStream`, `setupOutputRedirect`, `tellString`, `set_standard_stream!`); a stream the
#     stream layer makes for itself (`Sopen_text`, `Sopenmem` in the reader and the string predicates) keeps NULL, which
#     `format/3` never writes to. `initDefaultsStreamsLocale` is `initIO`'s (the two input/output standard streams, as
#     upstream: the error stream gets its locale from the first `set_locale/1`). `locale(L)` of open/4 and set_stream/2
#     stays the refusal of src/os/pl-file.jl, and the `locale(L)` stream property stays false (src/os/pl-file.jl).
#   * The blob type has no hook slots (`PL_blob_t` has none, as src/pl-dbref.jl): `acquire_locale_ref` is called by
#     `unifyLocale` for an atom it has just made; `release_locale_ref`, `write_locale_ref`, `save_locale_ref` and
#     `load_locale_ref` are NOT PORTED (no atom GC: a blob keeps its locale for ever). The blob's payload is the number of the
#     locale in `gd.locale.refs` (`PL_locale_rec.serial`).
#   * `LD->locale.current` lives in `gd.locale.current` (the kernel runs one thread; TH1 moves it).
#   * `fill_locale_from_name!` returns `(ok, errno)`; the `#else` branch (`setlocale` save/restore under `L_LOCALE`) is NOT
#     PORTED (glibc has `newlocale`). `PL_no_memory` paths are dropped (Julia throws).
#   * `locale_property/2`'s retry state is one `Int` (`_lenc`): the position in the table (or the number of the locale), the two
#     flags and the property index; upstream's `lprop_enum` is a foreign state. A locale destroyed between two retries is
#     seen as the next table position.
#   * `get_prop_def` (pl-thread.c) has no other user in the kernel yet: `_locale_get_prop_def` is its twin for `lprop_list`.
# allow-new-artifact: a port of the pin's src/os/pl-locale.c, read at 18168e62 (git show); no new design

# ── constants ────────────────────────────────────────────────────────────────────────────────────────

# PORT: pl-locale.c LSTR_MAX
"The size of `ls_to_wcs`'s buffer: a numeric string of 16 or more characters is refused (pl-locale.c)."
const LSTR_MAX = 16

# PORT: pl-locale.c MAX_GROUPING
"The size of `set_grouping`'s buffer (pl-locale.c)."
const MAX_GROUPING = 10

# ORIGINAL: `CHAR_MAX` of limits.h (signed `char`): the grouping entry that ends the groups.
"`CHAR_MAX`, the grouping entry for `no more groups`."
const CHAR_MAX = 127

# ORIGINAL: glibc's `LC_CTYPE_MASK | LC_NUMERIC_MASK` (`1 << category`), the categories `newlocale` is asked for.
"`LC_NUMERIC_MASK|LC_CTYPE_MASK` (glibc: a bit per category)."
const LOCALE_NEWLOCALE_MASK = (1 << Int(LC_CTYPE)) | (1 << Int(LC_NUMERIC))

# ── the numeric strings ──────────────────────────────────────────────────────────────────────────────

# PORT: pl-locale.c ls_to_wcs
# DIVERGES: the bytes of the C string are the argument; see the header (UTF-8, `Sdprintf` is a line on stderr: the kernel's
# `Serror` IO, `_std_io(Base.stderr, 2)`, a concrete union of IO types so the call does not dispatch at run time).
"The wide text of the C string `bytes` (a numeric string of a locale); `on_error` when it has no valid text (pl-locale.c)."
function ls_to_wcs(bytes::Vector{UInt8}, on_error::String)::String
    s = String(copy(bytes))
    if isvalid(s) && length(s) < LSTR_MAX                       # mbsrtowcs(buf, &in, LSTR_MAX, &state); in == NULL
        return s
    end
    println(_std_io(Base.stderr, 2), "Illegal locale string: ", s)   # Sdprintf("Illegal locale string: %s\n", in): to Serror
    return on_error
end

# ORIGINAL: the three strings of libc's `struct lconv` that pl-locale.c reads (`decimal_point`, `thousands_sep`,
# `grouping`: the first three fields), as byte vectors copied while the thread's locale is still the one asked for.
"`(decimal_point, thousands_sep, grouping)` of `localeconv()` as the bytes of the C strings."
function _read_lconv()::NTuple{3, Vector{UInt8}}
    p = ccall((:localeconv, LIBC), Ptr{Ptr{UInt8}}, ())
    return (
        _c_string_bytes(unsafe_load(p, 1)),
        _c_string_bytes(unsafe_load(p, 2)),
        _c_string_bytes(unsafe_load(p, 3))
    )
end

# ORIGINAL: the bytes of a NUL terminated C string (a NULL pointer: none).
"The bytes of the C string `q` (without its NUL), copied."
function _c_string_bytes(q::Ptr{UInt8})::Vector{UInt8}
    q == C_NULL && return UInt8[]
    return Vector{UInt8}(codeunits(unsafe_string(q)))
end

# PORT: pl-locale.c init_locale_strings
# DIVERGES: `conv` is `_read_lconv`'s answer (`nothing`: NULL); `grouping` is the group sizes as `Int`s (a C `char`, so a
# byte above 127 is negative) ended by a 0, as the C string is by its NUL.
"Fill the numeric strings of `l` from `conv`, or with the C defaults `.`, `,` and `3`; true when `conv` was given (pl-locale.c)."
function init_locale_strings!(
    l::PL_locale_rec{T}, conv::Union{Nothing, NTuple{3, Vector{UInt8}}}
)::Bool where {T}
    if conv !== nothing
        l.decimal_point = ls_to_wcs(conv[1], ".")
        l.thousands_sep = ls_to_wcs(conv[2], ",")
        g = Int[Int(reinterpret(Int8, b)) for b in conv[3]]     # strdup(conv->grouping)
        push!(g, 0)
        l.grouping = g
        return true
    else
        l.decimal_point = "."
        l.thousands_sep = ","
        l.grouping = Int[3, 0]                                  # "\003"
        return false
    end
end

# PORT: pl-locale.c fill_locale_from_name
# DIVERGES: returns `(ok, errno)`: `errno` is cleared before `newlocale` and read after it (the pl-sys.jl `_libc_setlocale`
# note: glibc leaves it 0 for a name it has failed to find before); the `#else` branch is NOT PORTED. The thread's locale is
# set by `uselocale` between two ccalls without a yield, so no other OS thread can run this task in between.
"Fill `l` with the LC_NUMERIC conventions of the locale `lname` (\"\": the environment) without changing the process locale; `(false, errno)` when libc has no such locale (pl-locale.c)."
function fill_locale_from_name!(
    l::PL_locale_rec{T}, lname::String
)::Tuple{Bool, Int} where {T}
    Base.Libc.errno(0)
    loc = ccall(
        (:newlocale, LIBC), Ptr{Cvoid}, (Cint, Cstring, Ptr{Cvoid}),
        LOCALE_NEWLOCALE_MASK, lname, C_NULL
    )
    e = Int(Base.Libc.errno())
    loc == C_NULL && return (false, e)
    old = ccall((:uselocale, LIBC), Ptr{Cvoid}, (Ptr{Cvoid},), loc)
    rc = init_locale_strings!(l, _read_lconv())
    ccall((:uselocale, LIBC), Ptr{Cvoid}, (Ptr{Cvoid},), old)
    ccall((:freelocale, LIBC), Cvoid, (Ptr{Cvoid},), loc)
    return (rc, 0)
end

# ── the locale object ────────────────────────────────────────────────────────────────────────────────

# PORT: pl-locale.c new_locale
# DIVERGES: the type is the argument; `PL_malloc` is Julia's allocation.
"A new locale with no references: a copy of `proto`, or the conventions of the environment (pl-locale.c)."
function new_locale(
    ::Type{T}, proto::Union{Nothing, PL_locale_rec{T}}
)::PL_locale_rec{T} where {T}
    l = PL_locale_rec{T}(nothing, nothing, LOCALE_MAGIC, 0, "", "", Int[0], 0)
    if proto !== nothing
        l.decimal_point = proto.decimal_point                   # wcsdup(proto->decimal_point)
        l.thousands_sep = proto.thousands_sep
        l.grouping = copy(proto.grouping)                       # strdup(proto->grouping)
    else
        ok, _ = fill_locale_from_name!(l, "")
        ok || init_locale_strings!(l, nothing)
    end
    return l
end

# PORT: pl-locale.c free_locale_strings
# DIVERGES: the strings are Julia's to free; they are reset to the empty text.
"Drop the numeric strings of `l` (pl-locale.c)."
function free_locale_strings!(l::PL_locale_rec{T})::Nothing where {T}
    l.decimal_point = ""
    l.thousands_sep = ""
    l.grouping = Int[0]
    return nothing
end

# PORT: pl-locale.c free_locale
# DIVERGES: `PL_unregister_atom(l->alias)` and `PL_free` have no twin (no atom GC, Julia's GC); the locale is marked freed
# (`magic` 0) so `getLocale`'s assertion would see a stale reference.
"Free the locale `l` (pl-locale.c)."
function free_locale(l::PL_locale_rec{T})::Nothing where {T}
    free_locale_strings!(l)
    l.alias = nothing
    l.magic = 0
    return nothing
end

# PORT: pl-locale.c update_locale
"Refresh the numeric conventions of `l` after `setlocale/3` changed LC_NUMERIC or LC_ALL (pl-locale.c)."
function update_locale(
    l::PL_locale_rec{T}, category::Cint, locale::Union{Nothing, String}
)::Nothing where {T}
    if category == LC_NUMERIC || category == LC_ALL
        free_locale_strings!(l)
        init_locale_strings!(l, _read_lconv())
    end
    return nothing
end

# `acquireLocale` and `releaseLocale` (pl-locale.c) are not here: they are defined in src/os/pl-stream.jl, on the abstract `IOLocale` (the type of `IOSTREAM.locale`); a stream holds a locale.

# ── the table of aliased locales ─────────────────────────────────────────────────────────────────────

# ORIGINAL: equality of two atoms: the symbol of a text atom, the handle of a blob.
# (untyped arguments: a stored alias and a looked-up atom may be different concrete subtypes of the term type, as on the alt types.)
"Are the atoms `a` and `b` the same atom?"
function _loc_atoms_equal(a, b)::Bool
    a === b && return true
    return !is_blob(a) && !is_blob(b) && sym_key(a) == sym_key(b)
end

# ORIGINAL: `lookupHTableWP(GD->locale.localeTable, alias)` on the table vector: its position, 0 when absent.
"The position of the locale named `alias` in the table, or 0."
function _locale_table_index(gd::PL_global_data{T}, alias::T)::Int where {T}
    tbl = gd.locale.table
    for i in eachindex(tbl)
        la = tbl[i].alias
        la === nothing && continue
        _loc_atoms_equal(la, alias) && return i
    end
    return 0
end

# ORIGINAL: `lookupHTableWP(GD->locale.localeTable, alias)`.
"The locale named `alias`, or `nothing`."
function _locale_lookup(
    gd::PL_global_data{T}, alias::T
)::Union{Nothing, PL_locale_rec{T}} where {T}
    i = _locale_table_index(gd, alias)
    return i == 0 ? nothing : gd.locale.table[i]
end

# PORT: pl-locale.c alias_locale as _alias_locale_table!
# DIVERGES: split in two: this is the success branch (`addNewHTableWP`, `l->alias`, `l->references++`), false when the alias is
# taken; `alias_locale` raises the error. `PL_register_atom` has no twin (no atom GC).
"Enter `l` in the table under `alias`; false when the alias is taken, with nothing changed (pl-locale.c)."
function _alias_locale_table!(
    gd::PL_global_data{T}, l::PL_locale_rec{T}, alias::T
)::Bool where {T}
    _locale_table_index(gd, alias) == 0 || return false
    push!(gd.locale.table, l)                                   # addNewHTableWP(GD->locale.localeTable, alias, l)
    l.alias = alias
    l.references += 1                                           # acquireLocale(), but that will deadlock
    return true
end

# PORT: pl-locale.c alias_locale
"Give `l` the alias `alias`: `permission_error(create, locale, Alias)` when it is taken (pl-locale.c)."
function alias_locale(
    gd::PL_global_data{T}, ld::PL_local_data{T}, l::PL_locale_rec{T}, alias::T
)::Bool where {T}
    if _locale_table_index(gd, alias) != 0
        obj = PL_new_term_ref(ld)
        PL_put_atom(ld, obj, alias)
        return PL_error(
            ld, "locale_create", 2, "Alias name already taken",
            ERR_PERMISSION, mk_sym(T, :create), mk_sym(T, :locale), obj
        )
    end
    return _alias_locale_table!(gd, l, alias)
end

# PORT: pl-locale.c free_locale_symbol
# DIVERGES: the locale is the argument (upstream: the table entry's key and value); `PL_unregister_atom` has no twin.
"A table entry goes: the locale loses its alias and its reference (pl-locale.c)."
function free_locale_symbol(l::PL_locale_rec{T})::Nothing where {T}
    l.alias = nothing
    releaseLocale(l)
    return nothing
end

# ── the blob and the Prolog handle ───────────────────────────────────────────────────────────────────

# PORT: pl-locale.c locale_blob
# DIVERGES: no hook slots (see the header): unique by payload, non-text, named `locale`.
"The blob type of a locale handle (pl-locale.c `locale_blob`)."
const locale_blob = PL_blob_t(PL_BLOB_UNIQUE, "locale")

# ORIGINAL: the number of a locale as the 8 bytes of its blob (`locale_ref.data` upstream, a pointer).
"The 8 bytes of a locale blob: the locale's number in `gd.locale.refs`, little-endian."
_locale_ref_bytes(serial::Int)::Vector{UInt8} = collect(reinterpret(UInt8, Int64[serial]))

# ORIGINAL: upstream's `((locale_ref*)PL_blob_data(a, NULL, &bt))->data` with the type test `bt == &locale_blob`.
"The locale the blob `a` names, or `nothing` when `a` is no locale blob."
function _locale_blob_ref(
    gd::PL_global_data{T}, a::T
)::Union{Nothing, PL_locale_rec{T}} where {T}
    is_blob(a) || return nothing
    at = atomValue(gd.atoms, blob_handle(a))
    at.type === locale_blob || return nothing
    serial = reinterpret(Int64, at.name[1:8])[1]
    return gd.locale.refs[Int(serial)]
end

# ORIGINAL: the number of `l` in `gd.locale.refs` (the blob's payload), given on first need.
"The number of the locale `l` in `gd.locale.refs`; a locale gets its number the first time it needs one."
function _locale_serial!(gd::PL_global_data{T}, l::PL_locale_rec{T})::Int where {T}
    if l.serial == 0
        push!(gd.locale.refs, l)
        l.serial = length(gd.locale.refs)
    end
    return l.serial
end

# PORT: pl-locale.c acquire_locale_ref
# DIVERGES: the locale is the argument; called by `unifyLocale` for an atom it has just made.
"A locale blob was created: the blob holds a reference to its locale (pl-locale.c)."
function acquire_locale_ref(l::PL_locale_rec{T})::Nothing where {T}
    acquireLocale(l)
    return nothing
end

# PORT: pl-locale.c unifyLocale
# DIVERGES: the database and the local data are arguments; the blob is made by `lookupBlob` (see the header).
"Unify `t` with the handle of `l`: its alias (when `alias`), else its blob (pl-locale.c)."
function unifyLocale(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t, l::PL_locale_rec{T}, alias::Bool
)::Bool where {T}
    la = l.alias
    if la !== nothing && alias
        return PL_unify_atom(ld, t, la)
    end
    ls = l.symbol
    if ls !== nothing
        return PL_unify_atom(ld, t, ls)
    end
    bytes = _locale_ref_bytes(_locale_serial!(gd, l))
    w, fresh = lookupBlob(gd.atoms, bytes, length(bytes), locale_blob)    # PL_put_blob(b, &l, sizeof(l), &locale_blob)
    a = _blob_term!(gd.atoms, gd.atom_symbols, T, w)
    fresh && acquire_locale_ref(l)
    l.symbol = a                                                # PL_get_atom(b, &l->symbol)
    return PL_unify_atom(ld, t, a)
end

# PORT: pl-locale.c getLocale
# DIVERGES: the database and the local data are arguments; the locale or `nothing` (acquired) for upstream's `*lp` and bool.
"The locale `t` names (`current_locale`, a locale blob or an alias), acquired; `nothing` when it names none (pl-locale.c)."
function getLocale(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t
)::Union{Nothing, PL_locale_rec{T}} where {T}
    a = PL_get_atom(ld, t)
    a === nothing && return nothing
    l::Union{Nothing, PL_locale_rec{T}} = nothing
    if _atom_is(a, "current_locale")                            # a == ATOM_current_locale
        l = gd.locale.current
    else
        l = _locale_blob_ref(gd, a)
        if l === nothing
            l = _locale_lookup(gd, a)
        end
    end
    l === nothing && return nothing
    @assert l.magic == LOCALE_MAGIC
    return acquireLocale(l)
end

# PORT: pl-locale.c getLocaleEx
"As `getLocale`, raising `existence_error(locale, T)` for an atom and `type_error(locale, T)` for another term (pl-locale.c)."
function getLocaleEx(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t
)::Union{Nothing, PL_locale_rec{T}} where {T}
    l = getLocale(gd, ld, t)
    l === nothing || return l
    if PL_is_atom(ld, t)
        PL_error(ld, ERR_EXISTENCE, mk_sym(T, :locale), t)      # PL_existence_error("locale", t)
    else
        PL_type_error(ld, "locale", t)
    end
    return nothing
end

# ── the properties ───────────────────────────────────────────────────────────────────────────────────

# PORT: pl-locale.c locale_alias_property
"`locale_property(Locale, alias(Name))` (pl-locale.c)."
function locale_alias_property(
    ld::PL_local_data{T}, l::PL_locale_rec{T}, prop::term_t
)::Bool where {T}
    la = l.alias
    la === nothing && return false
    return PL_unify_atom(ld, prop, la)
end

# PORT: pl-locale.c locale_decimal_point_property
"`locale_property(Locale, decimal_point(Atom))` (pl-locale.c)."
function locale_decimal_point_property(
    ld::PL_local_data{T}, l::PL_locale_rec{T}, prop::term_t
)::Bool where {T}
    isempty(l.decimal_point) && return false
    return PL_unify_atom(ld, prop, mk_sym(T, Symbol(l.decimal_point)))      # PL_unify_wchars(prop, PL_ATOM, ...)
end

# PORT: pl-locale.c locale_thousands_sep_property
"`locale_property(Locale, thousands_sep(Atom))` (pl-locale.c)."
function locale_thousands_sep_property(
    ld::PL_local_data{T}, l::PL_locale_rec{T}, prop::term_t
)::Bool where {T}
    isempty(l.thousands_sep) && return false
    return PL_unify_atom(ld, prop, mk_sym(T, Symbol(l.thousands_sep)))
end

# ORIGINAL: `s[i]` of a C string held as a vector ended by 0: the 0 past its end.
"Entry `i` of the grouping vector `g`, 0 past its end."
_grouping_at(g::Vector{Int}, i::Int)::Int = i <= length(g) ? g[i] : 0

# PORT: pl-locale.c locale_grouping_property
"`locale_property(Locale, grouping(List))` (pl-locale.c)."
function locale_grouping_property(
    ld::PL_local_data{T}, l::PL_locale_rec{T}, prop::term_t
)::Bool where {T}
    g = l.grouping
    if _grouping_at(g, 1) != 0                                  # l->grouping && l->grouping[0]
        tail = PL_copy_term_ref(ld, prop)
        head = PL_new_term_ref(ld)
        i = 1
        while true
            PL_unify_list(ld, tail, head, tail) || return false
            s0 = _grouping_at(g, i)
            s1 = _grouping_at(g, i + 1)
            s2 = _grouping_at(g, i + 2)
            if s1 == 0 || (s1 == s0 && s2 == 0)
                PL_unify_functor(ld, head, mk_sym(T, :repeat), 1) || return false   # PL_unify_term(head, PL_FUNCTOR, FUNCTOR_repeat1, PL_INT, s[0])
                a = PL_new_term_ref(ld)
                _PL_get_arg(ld, 1, head, a)
                PL_unify_integer(ld, a, s0) || return false
                return PL_unify_nil(ld, tail)
            end
            s0 == CHAR_MAX && return PL_unify_nil(ld, tail)
            PL_unify_integer(ld, head, s0) || return false
            i += 1
        end
    end
    return false
end

# PORT: pl-thread.h tprop
# DIVERGES: `functor` is the name of the functor (arity 1); `fn` is the index of its property function in `_lprop_call`
# (upstream: a function pointer).
"A property of a locale: the functor's name and the number of its function (pl-thread.h `tprop`)."
struct tprop
    functor::Symbol
    fn::Int
end

# PORT: pl-locale.c lprop_list
"The properties of a locale, in upstream's order."
const lprop_list = (
    tprop(:alias, 1), tprop(:decimal_point, 2), tprop(:thousands_sep, 3),
    tprop(:grouping, 4)
)

# ORIGINAL: the call `LDFUNCP(*state->p->function)(state->l, arg)` on the function number `p.fn`.
"Run the property function number `fn` of `lprop_list` on the locale `l` and the argument `arg`."
function _lprop_call(
    ld::PL_local_data{T}, fn::Int, l::PL_locale_rec{T}, arg::term_t
)::Bool where {T}
    fn == 1 && return locale_alias_property(ld, l, arg)
    fn == 2 && return locale_decimal_point_property(ld, l, arg)
    fn == 3 && return locale_thousands_sep_property(ld, l, arg)
    return locale_grouping_property(ld, l, arg)
end

# PORT: pl-thread.c get_prop_def as _locale_get_prop_def
# DIVERGES: returns `(status, index)`: status 1 (found, the index in `lprop_list`), 0 (variable) or -1 (the error is raised);
# written for `lprop_list` only (its other callers, the mutex and thread properties, are unwritten).
"Find the property `t` names in `lprop_list` (pl-thread.c)."
function _locale_get_prop_def(ld::PL_local_data{T}, t::term_t)::Tuple{Int, Int} where {T}
    na = PL_get_name_arity(ld, t)                               # PL_get_functor(t, &f)
    if na !== nothing
        name, arity = na
        if arity == 1
            for i in 1:length(lprop_list)
                if _atom_is(name, String(lprop_list[i].functor))
                    return (1, i)
                end
            end
        end
        PL_error(ld, ERR_DOMAIN, mk_sym(T, :locale_property), t)
        return (-1, 0)
    end
    PL_is_variable(ld, t) && return (0, 0)
    PL_error(ld, ERR_TYPE, mk_sym(T, :locale_property), t)
    return (-1, 0)
end

# ORIGINAL: the state of `locale_property/2` (upstream `lprop_enum`) as one `Int`: `x` is the position in the locale table
# (`e`: the locales are enumerated) or the number of the locale in `gd.locale.refs`; `e` and `ep` (the properties are
# enumerated) are 0 or 1; `p` is the property index 1..4.
"Encode the state of `locale_property/2`."
_lenc(x::Int, e::Int, ep::Int, p::Int)::Int = (((x * 2 + e) * 2 + ep) * 8) + p

# ORIGINAL: the inverse of `_lenc`: `(x, e, ep, p)`.
"Decode the state of `locale_property/2`."
function _ldec(c::Int)::NTuple{4, Int}
    p = c & 7
    c >>= 3
    ep = c & 1
    c >>= 1
    e = c & 1
    c >>= 1
    return (c, e, ep, p)
end

# PORT: pl-locale.c advance_lstate
# DIVERGES: the state is `(x, e, ep, p)`, see `_lenc`; returns `(more, x, p)`.
"Step the state of `locale_property/2` to the next property, then to the next locale (pl-locale.c)."
function advance_lstate(
    gd::PL_global_data{T}, x::Int, e::Int, ep::Int, p::Int
)::Tuple{Bool, Int, Int} where {T}
    if ep != 0
        p += 1
        if p <= length(lprop_list)
            return (true, x, p)
        end
        p = 1
    end
    if e != 0 && x < length(gd.locale.table)                    # advanceTableEnum(state->e, NULL, &tv)
        return (true, x + 1, p)
    end
    return (false, x, p)
end

# PORT: pl-locale.c free_lstate
# DIVERGES: the state is `(x, e)`; no table enumerator, no foreign state to free.
"End the enumeration: release the locale a bound `Locale` acquired (pl-locale.c)."
function free_lstate(gd::PL_global_data{T}, x::Int, e::Int)::Nothing where {T}
    if e == 0 && x != 0
        releaseLocale(gd.locale.refs[x])
    end
    return nothing
end

# PORT: pl-locale.c get_atom_arg
"The atom that is the first argument of the compound `t`, or `nothing` (pl-locale.c)."
function get_atom_arg(ld::PL_local_data{T}, t::term_t)::Union{Nothing, T} where {T}
    t2 = PL_new_term_ref(ld)
    _PL_get_arg(ld, 1, t, t2) || return nothing
    return PL_get_atom(ld, t2)
end

# PORT: pl-locale.c locale_property as pl_locale_property2_va
# (PRED_IMPL("locale_property", 2, locale_property, PL_FA_NONDETERMINISTIC))
# DIVERGES: the retry state is an `Int` (`_lenc`); see the header. The control flow is upstream's.
"`locale_property(?Locale, ?Property)`, non-deterministic (pl-locale.c)."
function pl_locale_property2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = ld.GD::PL_global_data{T}
    locale = PL__t0
    property = PL__t0 + 1
    ctl = PL_foreign_control(PL__ctx)
    x = 0
    e = 0
    ep = 0
    p = 1

    if ctl == FRG_FIRST_CALL
        if PL_is_variable(ld, locale)
            st, pidx = _locale_get_prop_def(ld, property)
            if st == 1
                p = pidx
                if p == 1                                       # state->p->functor == FUNCTOR_alias1
                    alias = get_atom_arg(ld, property)
                    if alias !== nothing
                        l = _locale_lookup(gd, alias)
                        l === nothing && return FFALSE
                        return unifyLocale(gd, ld, locale, l, false) ? FTRUE : FFALSE
                    end
                end
                e = 1
            elseif st == 0
                e = 1
                p = 1
                ep = 1
            else
                return FFALSE
            end
        else
            l = getLocale(gd, ld, locale)
            l === nothing && return FFALSE
            st, pidx = _locale_get_prop_def(ld, property)
            if st == 1
                p = pidx
            elseif st == 0
                p = 1
                ep = 1
            else
                releaseLocale(l)                                # free_lstate(state)
                return FFALSE
            end
            x = _locale_serial!(gd, l)                          # (so a redo finds it)
        end
    elseif ctl == FRG_REDO
        x, e, ep, p = _ldec(PL_foreign_context(PL__ctx))
    elseif ctl == FRG_CUTTED
        x, e, ep, p = _ldec(PL_foreign_context(PL__ctx))
        free_lstate(gd, x, e)
        return FTRUE
    else
        return FFALSE
    end

    # enumerate:
    if e != 0 && x == 0                                         # first time, enumerating locales
        isempty(gd.locale.table) && return FFALSE
        x = 1
    end

    arg = PL_new_term_ref(ld)
    if ep == 0
        _PL_get_arg(ld, 1, property, arg)
    end

    while true
        l = e != 0 ? gd.locale.table[x] : gd.locale.refs[x]
        if _lprop_call(ld, lprop_list[p].fn, l, arg)
            if ep != 0
                PL_unify_functor(ld, property, mk_sym(T, lprop_list[p].functor), 1) ||
                    (free_lstate(gd, x, e); return FFALSE)
                a = PL_new_term_ref(ld)
                _PL_get_arg(ld, 1, property, a)                 # PL_unify_term(property, PL_FUNCTOR, f, PL_TERM, arg)
                PL_unify(ld, a, arg) || (free_lstate(gd, x, e); return FFALSE)
            end
            if e != 0
                unifyLocale(gd, ld, locale, l, true) ||
                    (free_lstate(gd, x, e); return FFALSE)
            end

            more, x, p = advance_lstate(gd, x, e, ep, p)
            if more
                return PL_retry(_lenc(x, e, ep, p))             # ForeignRedoPtr(state)
            end
            free_lstate(gd, x, e)
            return FTRUE
        end

        more, x, p = advance_lstate(gd, x, e, ep, p)
        if !more
            free_lstate(gd, x, e)                               # error:
            return FFALSE
        end
    end
end

# ── locale_create/3 ──────────────────────────────────────────────────────────────────────────────────

# ORIGINAL: the text up to its first NUL, as a C string sees it.
"The text `s` up to its first NUL."
function _cstr(s::String)::String
    i = findfirst('\0', s)
    i === nothing && return s
    return s[1:prevind(s, i)]
end

# ORIGINAL: a text of any encoding as a `String` (`text_string` refuses a wide text).
"The text `txt` holds as a `String`, from its code points."
_locale_text_string(txt::PL_chars_t)::String =
    String(Char[Char(c) for c in _text_code_points(txt)])

# PORT: pl-locale.c set_chars
# DIVERGES: returns the new text or `nothing` (after the type error), where upstream stores it in `*valp`.
"The atom text of `t` (`type_error(atom, T)` when `t` is no atom) for `decimal_point` or `thousands_sep` (pl-locale.c)."
function set_chars(ld::PL_local_data{T}, t::term_t)::Union{Nothing, String} where {T}
    txt = PL_get_text(ld, t, UInt32(CVT_ATOM | CVT_EXCEPTION))  # PL_get_wchars(t, NULL, &s, CVT_ATOM|CVT_EXCEPTION)
    txt === nothing && return nothing
    return _cstr(_locale_text_string(txt))
end

# PORT: pl-locale.c get_group_size_ex
# DIVERGES: returns the size or `nothing` (after the error).
"A group size: an integer in 1..CHAR_MAX-1, else `domain_error(digit_group_size, T)` (pl-locale.c)."
function get_group_size_ex(ld::PL_local_data{T}, t::term_t)::Union{Nothing, Int} where {T}
    i = PL_get_integer_ex(ld, t)
    i === nothing && return nothing
    if i > 0 && i < CHAR_MAX
        return i
    end
    PL_domain_error(ld, "digit_group_size", t)
    return nothing
end

# PORT: pl-locale.c set_grouping
# DIVERGES: returns the grouping as `Int`s ended by 0 (the C string), or `nothing` after the error.
"The grouping of the list `t`: group sizes, the last possibly `repeat(Size)` (pl-locale.c)."
function set_grouping(
    ld::PL_local_data{T}, t::term_t
)::Union{Nothing, Vector{Int}} where {T}
    s = Int[]
    tail = PL_copy_term_ref(ld, t)
    head = PL_new_term_ref(ld)
    while PL_get_list_ex(ld, tail, head, tail)
        if length(s) + 2 >= MAX_GROUPING                        # o-s+2 >= MAX_GROUPING
            PL_error(ld, "", 0, "", ERR_REPRESENTATION, mk_sym(T, :digit_groups))
            return nothing
        end
        if PL_is_functor(ld, head, mk_sym(T, :repeat), 1)
            PL_get_nil_ex(ld, tail) || return nothing
            _PL_get_arg(ld, 1, head, head)
            g = get_group_size_ex(ld, head)
            g === nothing && return nothing
            push!(s, g)
            push!(s, 0)                                         # end:
            return s
        end
        g = get_group_size_ex(ld, head)
        g === nothing && return nothing
        push!(s, g)
    end
    if PL_get_nil_ex(ld, tail)
        push!(s, CHAR_MAX)                                      # no more grouping
        push!(s, 0)
        return s
    end
    return nothing
end

# PORT: pl-locale.c locale_create as pl_locale_create3_va
# (PRED_IMPL("locale_create", 3, locale_create, 0))
# DIVERGES: a failed `newlocale` that left errno 0 is the not-found case (the pl-sys.jl `setlocale/3` note); a name with a
# NUL is cut there as a C string; the options are read before the alias is entered, as upstream.
"`locale_create(-Locale, +Default, +Options)` (pl-locale.c)."
function pl_locale_create3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = ld.GD::PL_global_data{T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    local nl::PL_locale_rec{T}

    def = getLocale(gd, ld, A2)
    if def !== nothing
        nl = new_locale(T, def)
        releaseLocale(def)
    else
        txt = PL_get_text(ld, A2, UInt32(CVT_LIST | CVT_STRING | CVT_ATOM))
        if txt !== nothing
            lname = _cstr(_locale_text_string(txt))
            if lname == "default"
                nl = new_locale(T, nothing)
            else
                nl = PL_locale_rec{T}(nothing, nothing, LOCALE_MAGIC, 0, "", "", Int[0], 0)
                ok, e = fill_locale_from_name!(nl, lname)
                if !ok
                    if e == ENOENT || e == 0
                        PL_error(ld, ERR_EXISTENCE, mk_sym(T, :locale), A2)     # PL_existence_error("locale", A2)
                        return FFALSE
                    end
                    PL_error(ld, "", 0, MSG_ERRNO, ERR_SYSCALL, "setlocale", e)
                    return FFALSE
                end
            end
        else
            getLocaleEx(gd, ld, A2)
            return FFALSE
        end
    end

    alias::Union{Nothing, T} = nothing
    tail = PL_copy_term_ref(ld, A3)
    head = PL_new_term_ref(ld)
    arg = PL_new_term_ref(ld)

    while PL_get_list_ex(ld, tail, head, tail)
        na = PL_get_name_arity(ld, head)
        if na === nothing || na[2] != 1 || !_PL_get_arg(ld, 1, head, arg)
            PL_type_error(ld, "locale_property", head)
            free_locale(nl)
            return FFALSE
        end
        pname = na[1]
        if _atom_is(pname, "alias")
            alias = PL_get_atom_ex(ld, arg)
            if alias === nothing
                free_locale(nl)
                return FFALSE
            end
        elseif _atom_is(pname, "decimal_point")
            s = set_chars(ld, arg)
            if s === nothing
                free_locale(nl)
                return FFALSE
            end
            nl.decimal_point = s
        elseif _atom_is(pname, "thousands_sep")
            s = set_chars(ld, arg)
            if s === nothing
                free_locale(nl)
                return FFALSE
            end
            nl.thousands_sep = s
        elseif _atom_is(pname, "grouping")
            g = set_grouping(ld, arg)
            if g === nothing
                free_locale(nl)
                return FFALSE
            end
            nl.grouping = g
        end
    end
    if !PL_get_nil_ex(ld, tail)
        free_locale(nl)
        return FFALSE
    end

    if alias !== nothing && !alias_locale(gd, ld, nl, alias)
        free_locale(nl)
        return FFALSE
    end

    return unifyLocale(gd, ld, A1, nl, true) ? FTRUE : FFALSE
end

# PORT: pl-locale.c locale_destroy as pl_locale_destroy1_va
# (PRED_IMPL("locale_destroy", 1, locale_destroy, 0))
"`locale_destroy(+Locale)`: remove the alias, drop the reference (pl-locale.c)."
function pl_locale_destroy1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = ld.GD::PL_global_data{T}
    l = getLocaleEx(gd, ld, PL__t0)
    l === nothing && return FFALSE
    la = l.alias
    if la !== nothing
        i = _locale_table_index(gd, la)
        if i != 0 && gd.locale.table[i] === l                   # deleteHTableWP(GD->locale.localeTable, alias) == l
            deleteat!(gd.locale.table, i)
            l.alias = nothing
            l.references -= 1
        end
    end
    releaseLocale(l)
    return FTRUE
end

# PORT: pl-locale.c set_locale as pl_set_locale1_va
# (PRED_IMPL("set_locale", 1, set_locale, 0))
# DIVERGES: `_PL_streams()` is the first five entries of `ld.IO_streams` (the user and current streams; `nothing` is skipped).
# As upstream, the reference `getLocaleEx` acquired is not released when `l` is the current locale already.
"`set_locale(+Locale)`: make `Locale` the current locale (pl-locale.c)."
function pl_set_locale1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = ld.GD::PL_global_data{T}
    l = getLocaleEx(gd, ld, PL__t0)
    l === nothing && return FFALSE
    ol = gd.locale.current
    if l !== ol
        gd.locale.current = l                                   # already acquired
        ol === nothing || releaseLocale(ol)
        for i in 1:5                                            # set locale of standard streams
            si = ld.IO_streams[i]
            si === nothing || Ssetlocale(si, l)
        end
    end
    return FTRUE
end

# PORT: pl-locale.c current_locale as pl_current_locale1_va
# (PRED_IMPL("current_locale", 1, current_locale, 0))
"`current_locale(-Locale)`: the current locale (pl-locale.c)."
function pl_current_locale1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = ld.GD::PL_global_data{T}
    cur = gd.locale.current
    cur === nothing && return FFALSE
    return unifyLocale(gd, ld, PL__t0, cur, true) ? FTRUE : FFALSE
end

# ── the C interface ──────────────────────────────────────────────────────────────────────────────────

# PORT: pl-locale.c initLocale
# DIVERGES: the database is the argument (called by `setupProlog`, src/pl-setup.jl, where pl-setup.c:176 calls it);
# `initDefaultsStreamsLocale` is `initDefaultsStreamsLocale!` below, called by `initIO` (the streams are per local data).
"Register the locale blob type and make the default locale `default`, the system default and the current locale (pl-locale.c)."
function initLocale!(gd::PL_global_data{T})::Nothing where {T}
    PL_register_blob_type(gd.atoms, locale_blob, builtin_atom("locale"))
    def = new_locale(T, nothing)
    _alias_locale_table!(gd, def, mk_sym(T, :default))
    gd.locale.default_locale = acquireLocale(def)
    gd.locale.current = acquireLocale(def)
    return nothing
end

# PORT: pl-locale.c initDefaultsStreamsLocale
# DIVERGES: the two streams are the arguments (upstream: `S__iob`'s first two, the input and the output), the locale is the
# database's default locale.
"Give the standard input and output streams `sin` and `sout` the default locale when they have none (pl-locale.c)."
function initDefaultsStreamsLocale!(
    gd::PL_global_data, sin::IOSTREAM, sout::IOSTREAM
)::Nothing
    l = gd.locale.default_locale
    l === nothing && return nothing
    for s in (sin, sout)
        s.locale === nothing && (s.locale = acquireLocale(l))
    end
    return nothing
end

# PORT: pl-locale.c initStreamLocale
# DIVERGES: the database is the argument; `HAS_LD` is always true (a thread has `current`), so no `default_locale` branch.
"Give the new stream `s` the current locale (pl-locale.c)."
function initStreamLocale(gd::PL_global_data, s::IOSTREAM)::Bool
    l = gd.locale.current
    l === nothing || (s.locale = acquireLocale(l))
    return true
end

# PORT: pl-locale.c updateLocale
# DIVERGES: the database is the argument; `locale` is `nothing` for a query.
"`setlocale/3` changed `category`: refresh the system default locale (pl-locale.c)."
function updateLocale(
    gd::PL_global_data{T}, category::Cint, locale::Union{Nothing, String}
)::Nothing where {T}
    dl = gd.locale.default_locale
    dl === nothing || update_locale(dl, category, locale)
    return nothing
end

# PORT: pl-locale.c cleanupLocale
# DIVERGES: `destroyHTableWP` is `free_locale_symbol` on each entry; the blobs' locales stay (no atom GC).
"Release the default locale and the table (pl-locale.c)."
function cleanupLocale(gd::PL_global_data{T})::Nothing where {T}
    dl = gd.locale.default_locale
    if dl !== nothing
        releaseLocale(dl)
        gd.locale.default_locale = nothing
    end
    tbl = copy(gd.locale.table)
    empty!(gd.locale.table)
    for l in tbl
        free_locale_symbol(l)
    end
    return nothing
end

# ── the registration ─────────────────────────────────────────────────────────────────────────────────

# PORT: pl-locale.c BeginPredDefs as PL_predicates_from_locale
# DIVERGES: appended last in `_PRED_TABLES` (src/pl-ext.jl), so the dispatch indices of the earlier tables stay as they were.
"pl-locale.c's registration table (`BeginPredDefs(locale)`)."
const PL_predicates_from_locale = (
    PL_extension(
        "locale_property", 2, pl_locale_property2_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    ),
    PL_extension("locale_create", 3, pl_locale_create3_va, PL_FA_VARARGS),
    PL_extension("locale_destroy", 1, pl_locale_destroy1_va, PL_FA_VARARGS),
    PL_extension("set_locale", 1, pl_set_locale1_va, PL_FA_VARARGS),
    PL_extension("current_locale", 1, pl_current_locale1_va, PL_FA_VARARGS)
)
