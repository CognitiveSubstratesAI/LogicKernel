# UPSTREAM: swipl-devel src/pl-zip.c @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-zip.h @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2018-2022, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# allow-new-artifact: a port of the pin's src/pl-zip.c, read from the pin (git show 18168e62) for this file
#
# ZIP1 (pl-zip.c), lane F: the zip archives of the resource database and of library(zip), as far as the kernel
# can follow them. Upstream drives minizip (`zipFile`, `unzFile`: a reader and a writer of the zip format over
# zlib's deflate) through three kinds of input (a file, a memory region, a Prolog stream). The kernel has no
# zip library and no deflate, so NO ZIPPER CAN BE MADE: the one maker, `unify_zipper` after a successful
# `zip_open_stream/3`, `zip_open_archive` or `zip_open_archive_mem`, sits behind a named refusal (NotPortedError,
# step ZIP1). What the kernel does follow is everything that runs BEFORE the first minizip call:
#   * `get_zipper`: a term is a zipper only if it is a blob of the `zipper` type. The type is registered by
#     `initZip` at upstream's boot and no zipper blob is ever made here, so every term fails `get_zipper` with
#     `type_error(zipper, T)` (`instantiation_error` for an unbound term, as `PL_type_error` raises it). The
#     predicates that start with `get_zipper` (`zip_clone/2`, `zip_close_/2`, `zip_lock/1`, `zip_unlock/1`,
#     `zipper_goto/2`, `zip_file_info_/3`) therefore answer what upstream answers for a non-zipper argument;
#   * the option lists (`zip_open_stream/3`: close_parent; `zipper_open_current/3`: type, encoding, bom, release,
#     reposition) and the stream argument (`PL_get_stream`), read before the archive is touched, with
#     upstream's errors;
#   * `zipper_open_new_file_in_zip/4` and `'$rc_handle'/1` are the two exceptions, see DIVERGES 2 and 3.
# Left out as unreachable without a zipper (pl-zip.c line numbers at the pin): the locking and state machine
# `zown`, `zdisown`, `zlock`, `zunlock`, `valid_transitions`, `zacquire`, `zrelease` (102-224: they work on
# a `zipper` struct and its mutex), the minizip file functions `zopen64_file` ... `zclone_mem` (235-449), the
# blob hooks `write_zipper` ... `load_zipper` (452-555), `unify_zipper` (557-565), the entry streams
# `Sread_zip_entry` ... `Szipfunctions_repositioning` (732-840), `zset_time`, `zget_time` (842-875), the mapping
# `map_file`, `unmap_file` (1207-1322) and `zip_close_archive` (1414-1421), `zipper_file` (1467-1471),
# `initZip` (1478-1482): none is
# called before a zipper exists.
#
# DIVERGES (file-wide):
#   1. NO ZIPPER BLOB: `zipper` is an empty struct that `get_zipper` can never return (upstream: a pointer to
#      `struct zipper`). The code after a successful `get_zipper` is the named refusal at the place where the
#      first minizip call of that predicate stands.
#   2. `zipper_open_new_file_in_zip/4` refuses at entry: its option table (extra, comment: `OPT_STRING`; time:
#      `OPT_DOUBLE`) uses option types `PL_scan_options` (src/os/pl-option.jl) does not read, and the entry it
#      opens is a deflate writer. A scan that dropped those options silently would be a stub.
#   3. `'$rc_handle'/1`: `GD->resources.DB` is the resource database opened at boot from the executable's zip
#      (pl-init.c `rc_open_archive`); the kernel opens none, so the field has no twin and the predicate fails
#      (the first branch of the upstream body with `GD->resources.DB == NULL`).
#   4. NO LOCKS: `SIO_OUTPUT` is read from the stream's flags without `PL_get_stream`'s lock; a stream found by
#      `term_stream_handle` has none to release (`PL_release_stream` calls of the error exits are no twin).

# PORT: pl-zip.h RC_RDONLY
"The flag of `zip_open_archive`: open for reading (pl-zip.h)."
const RC_RDONLY = Int(0x01)
# PORT: pl-zip.h RC_WRONLY
"The flag of `zip_open_archive`: open for writing (pl-zip.h)."
const RC_WRONLY = Int(0x02)
# PORT: pl-zip.h RC_CREATE
"The flag of `zip_open_archive`: create the archive (pl-zip.h)."
const RC_CREATE = Int(0x04)
# PORT: pl-zip.h RC_TRUNC
"The flag of `zip_open_archive`: truncate the archive (pl-zip.h)."
const RC_TRUNC = Int(0x08)
# PORT: pl-zip.h RC_RDWR
"The flags of `zip_open_archive`: open for reading and writing (pl-zip.h)."
const RC_RDWR = RC_RDONLY | RC_WRONLY

# PORT: pl-zip.h zipper
# DIVERGES: an empty struct that nothing constructs (see the file header, 1).
"A zipper (pl-zip.h `struct zipper`): the zip archive a `<zipper>(Address)` blob names. No value exists."
struct zipper end

# PORT: pl-zip.c rc_strerror
"The text of the resource error `eno`: upstream knows one (pl-zip.c)."
rc_strerror(eno::Int)::String = "Unknown resource error"

# PORT: pl-zip.c get_zipper
# DIVERGES: returns the zipper or `nothing` with the error raised, where upstream writes `*zipper` and returns
# a Boolean; no term is a zipper (see the file header), so the answer is always `nothing`.
"The zipper the term `t` names, or `nothing` with `type_error(zipper, T)` raised (pl-zip.c)."
function get_zipper(ld::PL_local_data{T}, t::term_t)::Union{Nothing, zipper} where {T}
    PL_type_error(ld, "zipper", t)
    return nothing
end

# PORT: pl-zip.c zip_open_stream_options
"The options of `zip_open_stream/3` (pl-zip.c)."
const zip_open_stream_options = (PL_option_t(:close_parent, OPT_BOOL),)

# PORT: pl-zip.c zip_open_stream as pl_zip_open_stream3_va
# (PRED_IMPL("zip_open_stream", 3, zip_open_stream, 0))
# DIVERGES: refused by name at the first minizip call, after the option list and the stream are read, as
# upstream's order; `close_parent` is only read by the code behind the refusal.
"`zip_open_stream(+Stream, -Zipper, +Options)`: a zipper on a Prolog stream (pl-zip.c)."
function pl_zip_open_stream3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    A3 = PL__t0 + 2
    vals = PL_scan_options(ld, A3, 0, "zip_options", zip_open_stream_options)
    vals === nothing && return FFALSE
    s = term_stream_handle(ld, A1, SH_ERRORS)
    s === nothing && return FFALSE
    if (s.flags & SIO_OUTPUT) != 0
        throw(
            NotPortedError{T}(
                mk_sym(T, :zip_open_stream),
                "zipOpen2_64: a zip writer needs minizip and deflate (pl-zip.c:620)",
                "ZIP1"
            )
        )
    end
    throw(
        NotPortedError{T}(
            mk_sym(T, :zip_open_stream),
            "unzOpen2_64: a zip reader needs minizip and inflate (pl-zip.c:628)",
            "ZIP1"
        )
    )
end

# PORT: pl-zip.c zip_clone as pl_zip_clone2_va
# (PRED_IMPL("zip_clone", 2, zip_clone, 0))
"`zip_clone(+Zipper, -Clone)`: a second reader of a memory-mapped archive (pl-zip.c)."
function pl_zip_clone2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    z = get_zipper(ld, PL__t0)
    z === nothing && return FFALSE
    throw(
        NotPortedError{T}(
            mk_sym(T, :zip_clone), "unzClone of a zipper's reader (pl-zip.c:667)", "ZIP1"
        )
    )
end

# PORT: pl-zip.c zip_close as pl_zip_close2_va
# (PRED_IMPL("zip_close_", 2, zip_close, 0))
"`zip_close_(+Zipper, +Comment)`: close a zipper (pl-zip.c)."
function pl_zip_close2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    z = get_zipper(ld, PL__t0)
    z === nothing && return FFALSE
    throw(
        NotPortedError{T}(
            mk_sym(T, :zip_close_),
            "zipClose and unzClose of a zipper (pl-zip.c:479)",
            "ZIP1"
        )
    )
end

# PORT: pl-zip.c zip_lock as pl_zip_lock1_va
# (PRED_IMPL("zip_lock", 1, zip_lock, 0))
"`zip_lock(+Zipper)`: lock a zipper for the calling thread (pl-zip.c)."
function pl_zip_lock1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    z = get_zipper(ld, PL__t0)
    z === nothing && return FFALSE
    throw(
        NotPortedError{T}(
            mk_sym(T, :zip_lock), "zlock: the lock of a zipper (pl-zip.c:127)", "ZIP1"
        )
    )
end

# PORT: pl-zip.c zip_unlock as pl_zip_unlock1_va
# (PRED_IMPL("zip_unlock", 1, zip_unlock, 0))
"`zip_unlock(+Zipper)`: release the lock of a zipper (pl-zip.c)."
function pl_zip_unlock1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    z = get_zipper(ld, PL__t0)
    z === nothing && return FFALSE
    throw(
        NotPortedError{T}(
            mk_sym(T, :zip_unlock), "zunlock: the lock of a zipper (pl-zip.c:142)", "ZIP1"
        )
    )
end

# PORT: pl-zip.c zipper_open_new_file_in_zip as pl_zipper_open_new_file_in_zip4_va
# (PRED_IMPL("zipper_open_new_file_in_zip", 4, zipper_open_new_file_in_zip, 0))
# DIVERGES: refused at entry (see the file header, 2); upstream scans the options `extra`, `comment`, `time`,
# `method`, `level` and `zip64`, checks `level` (1-9) and `method` (deflated, store), then reads the zipper.
"`zipper_open_new_file_in_zip(+Zipper, +Name, -Stream, +Options)`: an output stream for a new entry (pl-zip.c)."
function pl_zipper_open_new_file_in_zip4_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    throw(
        NotPortedError{T}(
            mk_sym(T, :zipper_open_new_file_in_zip),
            "a zip entry writer: options extra, comment, time; deflate (pl-zip.c:889)",
            "ZIP1"
        )
    )
end

# PORT: pl-zip.c zipper_goto as pl_zipper_goto2_va
# (PRED_IMPL("zipper_goto", 2, zipper_goto, 0))
"`zipper_goto(+Zipper, +File)`: make `first`, `next`, `file(Name)` or `offset(Pos)` the current entry (pl-zip.c)."
function pl_zipper_goto2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    z = get_zipper(ld, PL__t0)
    z === nothing && return FFALSE
    throw(
        NotPortedError{T}(
            mk_sym(T, :zipper_goto),
            "unzGoToFirstFile, unzGoToNextFile, unzLocateFile (pl-zip.c:989)",
            "ZIP1"
        )
    )
end

# PORT: pl-zip.c zipopen3_options
"The options of `zipper_open_current/3` (pl-zip.c)."
const zipopen3_options = (
    PL_option_t(:type, OPT_ATOM),
    PL_option_t(:encoding, OPT_ATOM),
    PL_option_t(:bom, OPT_BOOL),
    PL_option_t(:release, OPT_BOOL),
    PL_option_t(:reposition, OPT_BOOL)
)

# PORT: pl-zip.c zipper_open_current as pl_zipper_open_current3_va
# (PRED_IMPL("zipper_open_current", 3, zipper_open_current, 0))
# DIVERGES: the options' values are returned by `PL_scan_options` (`nothing`: the default); refused by name at
# `unzOpenCurrentFile`, after the option list, the encoding and the type are checked and the zipper is read.
"`zipper_open_current(+Zipper, -Stream, +Options)`: an input stream on the current entry (pl-zip.c)."
function pl_zipper_open_current3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    A3 = PL__t0 + 2
    vals = PL_scan_options(ld, A3, 0, "stream_option", zipopen3_options)
    vals === nothing && return FFALSE
    type = vals[1] isa T ? vals[1]::T : mk_sym(T, :text)
    encoding = vals[2] isa T ? vals[2]::T : nothing
    bom = vals[3] isa Bool ? (vals[3]::Bool ? 1 : 0) : -1
    eb = stream_encoding_options(ld, type, encoding, bom)
    eb === nothing && return FFALSE
    if !_sym_is(type, :text) && !_sym_is(type, :binary)
        t = PL_new_term_ref(ld)
        PL_put_atom(ld, t, type)
        PL_domain_error(ld, "type", t)
        return FFALSE
    end
    z = get_zipper(ld, A1)
    z === nothing && return FFALSE
    throw(
        NotPortedError{T}(
            mk_sym(T, :zipper_open_current),
            "unzOpenCurrentFile: an entry reader needs inflate (pl-zip.c:1118)",
            "ZIP1"
        )
    )
end

# PORT: pl-zip.c zip_file_info as pl_zip_file_info3_va
# (PRED_IMPL("zip_file_info_", 3, zip_file_info, 0))
"`zip_file_info_(+Zipper, -Name, -Info)`: the name and `info/6` of the current entry (pl-zip.c)."
function pl_zip_file_info3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    z = get_zipper(ld, PL__t0)
    z === nothing && return FFALSE
    throw(
        NotPortedError{T}(
            mk_sym(T, :zip_file_info_),
            "unzGetCurrentFileInfo64 of a zipper (pl-zip.c:1158)",
            "ZIP1"
        )
    )
end

# PORT: pl-zip.c rc_handle as pl_rc_handle1_va
# (PRED_IMPL("$rc_handle", 1, rc_handle, 0))
# DIVERGES: see the file header, 3: `GD->resources.DB` is NULL, so the body is its first branch's failure.
"`'\$rc_handle'(-Handle)`: the zipper of the resource database; fails when the system has none (pl-zip.c)."
function pl_rc_handle1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return FFALSE
end

# PORT: pl-zip.c zip_open_archive
# DIVERGES: refused by name: the caller (pl-init.c's resource database, pl-load.c) needs a zip reader.
"Open the zip archive `file` (pl-zip.c): a named refusal."
function zip_open_archive(ld::PL_local_data{T}, file::String, flags::Int)::Union{} where {T}
    throw(
        NotPortedError{T}(
            mk_sym(T, :zip_open_archive),
            "zip_open_archive: unzOpen2_64 and zipOpen2_64 of a file (pl-zip.c:1351)",
            "ZIP1"
        )
    )
end

# PORT: pl-zip.c zip_open_archive_mem
# DIVERGES: refused by name: a memory region needs a zip reader.
"Open a zip archive held in memory (pl-zip.c): a named refusal."
function zip_open_archive_mem(
    ld::PL_local_data{T}, mem::AbstractVector{UInt8}, flags::Int
)::Union{} where {T}
    throw(
        NotPortedError{T}(
            mk_sym(T, :zip_open_archive_mem),
            "zip_open_archive_mem: unzOpen2_64 of a memory region (pl-zip.c:1398)",
            "ZIP1"
        )
    )
end

# PORT: pl-zip.c SopenZIP
# DIVERGES: refused by name: a stream on an archive entry needs a zipper.
"Open the entry `name` of the archive `z` as a stream (pl-zip.c): a named refusal."
function SopenZIP(
    ld::PL_local_data{T}, z::zipper, name::String, flags::Int
)::Union{} where {T}
    throw(
        NotPortedError{T}(
            mk_sym(T, :SopenZIP),
            "SopenZIP: a stream on a zip entry (pl-zip.c:1429)",
            "ZIP1"
        )
    )
end

# PORT: pl-zip.c BeginPredDefs as PL_predicates_from_zip
"pl-zip.c's registration table (`BeginPredDefs(zip)`)."
const PL_predicates_from_zip = (
    PL_extension("zip_open_stream", 3, pl_zip_open_stream3_va, PL_FA_VARARGS),
    PL_extension("zip_clone", 2, pl_zip_clone2_va, PL_FA_VARARGS),
    PL_extension("zip_close_", 2, pl_zip_close2_va, PL_FA_VARARGS),
    PL_extension("zip_lock", 1, pl_zip_lock1_va, PL_FA_VARARGS),
    PL_extension("zip_unlock", 1, pl_zip_unlock1_va, PL_FA_VARARGS),
    PL_extension(
        "zipper_open_new_file_in_zip", 4, pl_zipper_open_new_file_in_zip4_va, PL_FA_VARARGS
    ),
    PL_extension("zipper_goto", 2, pl_zipper_goto2_va, PL_FA_VARARGS),
    PL_extension("zipper_open_current", 3, pl_zipper_open_current3_va, PL_FA_VARARGS),
    PL_extension("zip_file_info_", 3, pl_zip_file_info3_va, PL_FA_VARARGS),
    PL_extension("\$rc_handle", 1, pl_rc_handle1_va, PL_FA_VARARGS)
)
