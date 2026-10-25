# UPSTREAM: swipl-devel src/os/pl-files.c @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2023, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# FILES (pl-files.c), since Y1: the file name a term holds (`PL_get_file_name`) and delete_file/1.
#
# NOT PORTED: the rest of the file predicates (`exists_file/1`, `tmp_file/2`, `delete_directory/1`,
# `size_file/2`, …) with their `PRED_DEF`s; the `PL_get_file_name` flags that need a file system
# search or a path — `PL_FILE_ABSOLUTE`, `PL_FILE_OSPATH`, `PL_FILE_SEARCH`, `PL_FILE_EXIST`,
# `PL_FILE_READ`, `PL_FILE_WRITE`, `PL_FILE_EXECUTE` (refused by name, with their first caller);
# `expandVars` under the `file_name_variables` flag (the flag table, F1: the flag is false by default);
# `DeleteTemporaryFile` (delete_file/1 first tries the registry of `tmp_file/2`'s names, which is empty
# until tmp_file/2 is ported, so the call fails, as upstream's does with no registry).

# ORIGINAL (Y1): `PATH_MAX` (<limits.h>) on Linux.
"The longest file name `get_file_name` accepts, in bytes, the terminating NUL included (Linux)."
const PATH_MAX = 4096

# PORT: pl-files.c get_file_name
# DIVERGES: the name is a `String` (UTF-8, which is `REP_FN` in a UTF-8 locale) or `nothing` where upstream
# writes `char *` and returns a Bool; the unported flags above raise `NotPortedError`. `OsPath` is the
# identity on Unix.
"""
    get_file_name(ld, n, flags) -> String or nothing

The file name the term reference `n` holds — an atom, a string or a code or character list —, or `nothing`
after raising `type_error` (unless `PL_FILE_NOERRORS`), `domain_error(file_name, N)` for a name with a
NUL, or `representation_error(max_path_length)` (pl-files.c).
"""
function get_file_name(
    ld::PL_local_data{T}, n::term_t, flags::Int
)::Union{Nothing, String} where {T}
    unported =
        flags & (
            PL_FILE_ABSOLUTE | PL_FILE_OSPATH | PL_FILE_SEARCH | PL_FILE_EXIST |
            PL_FILE_READ |
            PL_FILE_WRITE | PL_FILE_EXECUTE
        )
    unported == 0 || throw(
        NotPortedError{T}(
            mk_sym(T, :file_name),
            "PL_get_file_name flags $(string(unported; base=16))", "R2"
        )
    )
    chflags = CVT_ATOM | CVT_STRING | CVT_LIST                  # CVT_FILENAME
    (flags & PL_FILE_NOERRORS) == 0 && (chflags |= CVT_EXCEPTION)
    txt = PL_get_text(ld, n, chflags)                           # PL_get_nchars(n, &len, &name, …)
    txt === nothing && return nothing
    name = text_string(txt)
    if 0x00 in codeunits(name)                                  # strlen(name) != len
        PL_error(
            ld, "", 0, "file name contains a 0-code", ERR_DOMAIN, mk_sym(T, :file_name), n
        )
        return nothing
    end
    if ncodeunits(name) >= PATH_MAX
        PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :max_path_length))
        return nothing
    end
    return name
end

# PORT: pl-files.c PL_get_file_name
# DIVERGES: returns the name, or `nothing` (see `get_file_name`).
"The file name the term reference `n` holds, or `nothing` after raising an error (pl-files.c)."
PL_get_file_name(ld::PL_local_data{T}, n::term_t, flags::Int) where {T} =
    get_file_name(ld, n, flags)

# PORT: pl-files.c RemoveFile
# DIVERGES: returns 0 on success and else the `errno` of the failure (upstream: a Bool, `errno` read by
# the caller); `remove(3)` is `ccall`ed, as upstream's HAVE_REMOVE branch (it deletes an empty directory
# too).
"Remove the file `path` from the file system: 0, or the `errno` of the failure (pl-files.c)."
function RemoveFile(path::String)::Int
    rc = ccall((:remove, LIBC), Cint, (Cstring,), path)
    return rc == 0 ? 0 : Int(Base.Libc.errno())
end

# PORT: pl-files.c delete_file as pl_delete_file1_va
# (PRED_IMPL("delete_file", 1, delete_file, 0))
# DIVERGES: NOT PORTED: `DeleteTemporaryFile` (see the file's header).
"""
`delete_file(+File)`: remove the file; `existence_error(file, File)` when it cannot be (`permission_error`
for an access error; the context holds `strerror(errno)`) (pl-files.c).
"""
function pl_delete_file1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    n = PL_get_file_name(ld, A1, 0)
    n === nothing && return FFALSE
    errno = RemoveFile(n)
    errno == 0 && return FTRUE
    rc = PL_error(
        ld, "", 0, MSG_ERRNO, ERR_FILE_OPERATION, mk_sym(T, :delete), mk_sym(T, :file), A1,
        errno
    )
    return rc ? FTRUE : FFALSE
end

# PORT: pl-files.c BeginPredDefs as PL_predicates_from_files
# DIVERGES: the ported entries (upstream's table has twenty-three).
"pl-files.c's registration table (`BeginPredDefs(files)`): the ported entries."
const PL_predicates_from_files = (
    PL_extension("delete_file", 1, pl_delete_file1_va, PL_FA_VARARGS),
)
