# UPSTREAM: swipl-devel src/os/pl-files.c @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2023, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# FILES (pl-files.c), since Y1: the file name a term holds (`PL_get_file_name`) and delete_file/1; since LB2b
# the file helpers (LastModifiedFile, SizeFile, AccessFile, ExistsFile, ExistsDirectory, ReadLink, DeRefLink,
# SameFile, RenameFile, MarkExecutable) and, as the groups land, the predicates of upstream's table.
#
# LB2b: `PL_get_file_name` honours `PL_FILE_ABSOLUTE`, `PL_FILE_OSPATH`, `PL_FILE_EXIST`, `PL_FILE_READ`,
# `PL_FILE_WRITE`, `PL_FILE_EXECUTE` and the `file_name_variables` flag; `PL_FILE_SEARCH`, which calls
# `system:absolute_file_name/3` of init.pl, is refused by name (left to LB4); `DeleteTemporaryFile`
# (delete_file/1 first tries the registry of `tmp_file/2`'s names, which is empty until tmp_file/2 lands,
# so the call fails, as upstream's does with no registry).

# ORIGINAL (Y1): `PATH_MAX` (<limits.h>) on Linux.
"The longest file name `get_file_name` accepts, in bytes, the terminating NUL included (Linux)."
const PATH_MAX = 4096

# PORT: pl-file.c file_name_is_iri
# DIVERGES: lives here, where the file-name functions are (pl-file.jl holds the stream layer); the
# name is a `String`.
"""
    file_name_is_iri(path) -> Int

The length of the IRI scheme `path` starts with — two or more lower-case letters followed by `://`, 4 for
`http://` — and else 0 (pl-file.c).
"""
function file_name_is_iri(path::AbstractString)::Int
    b = codeunits(path)
    n = length(b)
    s = 1
    while s <= n && UInt8('a') <= b[s] <= UInt8('z')
        s += 1
    end
    if s - 1 >= 2 && s + 2 <= n && b[s] == UInt8(':') && b[s + 1] == UInt8('/') &&
        b[s + 2] == UInt8('/')
        return s - 1
    end
    return 0
end

# PORT: pl-files.h ACCESS_EXIST
"`AccessFile` mode: the file exists (pl-files.h, 0x0000)."
const ACCESS_EXIST = 0
# PORT: pl-files.h ACCESS_EXECUTE
"`AccessFile` mode bit: execute access (pl-files.h, 0x0001)."
const ACCESS_EXECUTE = 1
# PORT: pl-files.h ACCESS_READ
"`AccessFile` mode bit: read access (pl-files.h, 0x0002)."
const ACCESS_READ = 2
# PORT: pl-files.h ACCESS_WRITE
"`AccessFile` mode bit: write access (pl-files.h, 0x0004)."
const ACCESS_WRITE = 4
# PORT: pl-files.h ACCESS_FILE
"`AccessFile` mode bit, the IRI extension: a regular file (pl-files.h, 0x0008)."
const ACCESS_FILE = 8
# PORT: pl-files.h ACCESS_DIRECTORY
"`AccessFile` mode bit, the IRI extension: a directory (pl-files.h, 0x0010)."
const ACCESS_DIRECTORY = 16

# ORIGINAL (LB2b): `access(2)` modes of <unistd.h> on Linux.
const F_OK = 0
const X_OK = 1
const W_OK = 2
const R_OK = 4

# ORIGINAL (LB2b): `stat(2)` through libuv. `Base.stat` returns the status of a missing file (`ENOENT`,
# `ENOTDIR`, `EINVAL`) as a field and throws `Base.IOError` for the other errors; both come back here as the
# negative libuv status, which is the negated `errno`.
"""
    statfunc(path) -> StatStruct or Int

`stat(2)` of `path`: the status, or the negated `errno` of the failure (pl-files.c `statfunc`).
"""
function statfunc(path::String)::Union{Base.Filesystem.StatStruct, Int}
    st = try
        stat(path)
    catch e
        e isa Base.IOError || rethrow()
        return Int(e.code)
    end
    return st.ioerrno == 0 ? st : Int(st.ioerrno)
end

# PORT: pl-files.c LastModifiedFile
# DIVERGES: returns `(time, errno)`, `errno` 0 for success (upstream: a Bool and `*tp`); the time is Julia's
# `sec + nsec*1.0e-9` where upstream computes `sec + nsec/1.0e9` (representation only: a last-bit difference).
"The last modification time of `name` as a POSIX timestamp and an `errno` (0 = ok) (pl-files.c)."
function LastModifiedFile(name::String)::Tuple{Float64, Int}
    st = statfunc(OsPath(name))
    st isa Int && return (0.0, -st)
    return (st.mtime, 0)
end

# PORT: pl-files.c SizeFile
# DIVERGES: returns `(size, errno)`, `errno` 0 for success (upstream: the size, or -1).
"The size of the file `path` in bytes and an `errno` (0 = ok) (pl-files.c)."
function SizeFile(path::String)::Tuple{Int64, Int}
    st = statfunc(OsPath(path))
    st isa Int && return (Int64(-1), -st)
    return (st.size, 0)
end

# PORT: pl-files.c access_mode
"The `access(2)` mode of the `ACCESS_*` mode `mode` (pl-files.c)."
function access_mode(mode::Int)::Int
    mode == ACCESS_EXIST && return F_OK
    m = 0
    (mode & ACCESS_READ) != 0 && (m |= R_OK)
    (mode & ACCESS_WRITE) != 0 && (m |= W_OK)
    (mode & ACCESS_EXECUTE) != 0 && (m |= X_OK)
    return m
end

# PORT: pl-files.c AccessFile
"Can `path` be accessed in the `ACCESS_*` mode `mode` (pl-files.c)."
function AccessFile(path::String, mode::Int)::Bool
    return ccall((:access, LIBC), Cint, (Cstring, Cint), OsPath(path), access_mode(mode)) == 0
end

# PORT: pl-files.c AccessDirectory
"Can the directory `path` be accessed in the `ACCESS_*` mode `mode`: `AccessFile` off Windows (pl-files.c)."
AccessDirectory(path::String, mode::Int)::Bool = AccessFile(path, mode)

# PORT: pl-files.c ExistsFile
"Is `path` a regular file (pl-files.c)."
function ExistsFile(path::String)::Bool
    st = statfunc(OsPath(path))
    return !(st isa Int) && isfile(st)
end

# PORT: pl-files.c ExistsDirectory
"Is `path` a directory (pl-files.c)."
function ExistsDirectory(path::String)::Bool
    st = statfunc(OsPath(path))
    return !(st isa Int) && isdir(st)
end

# PORT: pl-files.c ReadLink
# DIVERGES: returns the link text or `nothing` (upstream: `buf` or NULL). A link of `PATH_MAX-1` bytes or
# more is cut as upstream's buffer cuts it.
"The text of the symbolic link `f`, or `nothing` if `f` is not one (pl-files.c)."
function ReadLink(f::String)::Union{Nothing, String}
    buf = Vector{UInt8}(undef, PATH_MAX)
    n = ccall(
        (:readlink, LIBC), Int, (Cstring, Ptr{UInt8}, Csize_t), f, buf, Csize_t(PATH_MAX - 1)
    )
    n > 0 || return nothing
    return String(buf[1:n])
end

# PORT: pl-files.c DeRefLink1
# DIVERGES: returns the new name or `nothing` (upstream: `lbuf` or NULL); no buffer, so no overflow.
"One step of dereferencing the symbolic link `f`: its target, canonical, or `nothing` if `f` is no link (pl-files.c)."
function DeRefLink1(f::String)::Union{Nothing, String}
    l = ReadLink(f)
    l === nothing && return nothing
    startswith(l, '/') && return l                              # absolute path
    q = findlast('/', f)
    dir = q === nothing ? "" : f[1:q]
    return canonicaliseFileName(dir * l)
end

# PORT: pl-files.c DeRefLink
# DIVERGES: `ld` is an argument and the result a `String` or `nothing`; the exception of a too long name
# cannot arise (`canonicaliseFileName` takes no buffer).
"""
    DeRefLink(ld, link) -> String or nothing

The final destination of the symbolic link `link`, canonical; `nothing` after `permission_error(dereference,
symlink, Link)` when more than 20 links were followed (pl-files.c).
"""
function DeRefLink(ld::PL_local_data{T}, link::String)::Union{Nothing, String} where {T}
    n = 20                                                      # avoid loop!
    while true
        f = DeRefLink1(link)
        f === nothing && break
        old = n                                                 # `&& n-- > 0`
        n -= 1
        old > 0 || break
        link = f
    end
    if n > 0
        return link
    end
    t = PL_new_term_ref(ld)
    PL_put_atom(ld, t, mk_sym(T, Symbol(link)))
    PL_error(
        ld, "", 0, "too many (>20) levels of symbolic links", ERR_PERMISSION,
        mk_sym(T, :dereference), mk_sym(T, :symlink), t
    )
    return nothing
end

# PORT: pl-files.c SameFile
# DIVERGES: `strcasecmp` is a comparison of ASCII letters (the C locale).
"Do `f1` and `f2` name the same file: equal names (case-folded unless `file_name_case_sensitive`), or one inode (pl-files.c)."
function SameFile(ld::PL_local_data, f1::String, f2::String)::Bool
    if truePrologFlag(ld, PLFLAG_FILE_CASE)
        f1 == f2 && return true
    else
        _ascii_lower(f1) == _ascii_lower(f2) && return true
    end
    st1 = statfunc(OsPath(f1))
    st2 = statfunc(OsPath(f2))
    (st1 isa Int || st2 isa Int) && return false
    return st1.inode == st2.inode && st1.device == st2.device
end

# ORIGINAL (LB2b): the case folding of `strcasecmp(3)` in the C locale: ASCII letters only.
_ascii_lower(s::AbstractVector{UInt8})::Vector{UInt8} =
    [(UInt8('A') <= c <= UInt8('Z')) ? c + 0x20 : c for c in s]
_ascii_lower(s::String)::Vector{UInt8} = _ascii_lower(codeunits(s))

# PORT: pl-files.c get_file_name
# DIVERGES: the name is a `String` (UTF-8, which is `REP_FN` in a UTF-8 locale) or `nothing` where upstream
# writes `char *` and returns a Bool; `PL_FILE_SEARCH` raises `NotPortedError` (left to LB4). `OsPath` is the
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
    (flags & PL_FILE_SEARCH) == 0 || throw(
        NotPortedError{T}(
            mk_sym(T, :file_name),
            "PL_get_file_name flag PL_FILE_SEARCH (system:absolute_file_name/3 of init.pl)", "LB4"
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
    if truePrologFlag(ld, PLFLAG_FILEVARS)
        name = expandVars(ld, name)
        name === nothing && return nothing
    end
    if (flags & PL_FILE_NOERRORS) == 0
        op = nothing
        if (flags & (PL_FILE_READ | PL_FILE_WRITE | PL_FILE_EXECUTE | PL_FILE_EXIST)) != 0 &&
            !AccessFile(name, ACCESS_EXIST)
            PL_error(ld, ERR_EXISTENCE, mk_sym(T, :file), n)
            return nothing
        end
        (flags & PL_FILE_READ) != 0 && !AccessFile(name, ACCESS_READ) && (op = :read)
        op === nothing && (flags & PL_FILE_WRITE) != 0 && !AccessFile(name, ACCESS_WRITE) &&
            (op = :write)
        op === nothing && (flags & PL_FILE_EXECUTE) != 0 &&
            !AccessFile(name, ACCESS_EXECUTE) && (op = :execute)
        if op !== nothing
            PL_error(ld, "", 0, "", ERR_PERMISSION, mk_sym(T, op), mk_sym(T, :file), n)
            return nothing
        end
    end
    if (flags & PL_FILE_ABSOLUTE) != 0
        name = AbsoluteFile(ld, name)
        name === nothing && return nothing
    end
    return name
end

# PORT: pl-files.c PL_get_file_name
# DIVERGES: returns the name, or `nothing` (see `get_file_name`); `PL_FILE_OSPATH` applies `OsPath`, the
# identity on Unix.
"The file name the term reference `n` holds, or `nothing` after raising an error (pl-files.c)."
function PL_get_file_name(ld::PL_local_data{T}, n::term_t, flags::Int) where {T}
    name = get_file_name(ld, n, flags)
    name === nothing && return nothing
    (flags & PL_FILE_OSPATH) != 0 && (name = OsPath(name))
    return name
end

# PORT: pl-files.c RemoveFile
# DIVERGES: returns 0 on success and else the `errno` of the failure (upstream: a Bool, `errno` read by
# the caller); `remove(3)` is `ccall`ed, as upstream's HAVE_REMOVE branch (it deletes an empty directory
# too).
"Remove the file `path` from the file system: 0, or the `errno` of the failure (pl-files.c)."
function RemoveFile(path::String)::Int
    rc = ccall((:remove, LIBC), Cint, (Cstring,), path)
    return rc == 0 ? 0 : Int(Base.Libc.errno())
end

# PORT: pl-files.c RenameFile
# DIVERGES: returns 0 on success and else the `errno` of the failure (upstream: a Bool); `rename(2)` is `ccall`ed,
# as upstream's HAVE_RENAME branch.
"Rename the file `old` to `new`: 0, or the `errno` of the failure (pl-files.c)."
function RenameFile(old::String, new::String)::Int
    rc = ccall((:rename, LIBC), Cint, (Cstring, Cstring), OsPath(old), OsPath(new))
    return rc == 0 ? 0 : Int(Base.Libc.errno())
end

# ORIGINAL (LB2b): `umask(2)`, which sets the mask and returns the old one.
_umask(mask::Integer)::Cuint = ccall((:umask, LIBC), Cuint, (Cuint,), mask % Cuint)

# PORT: pl-files.c MarkExecutable
# DIVERGES: `ld` is an argument; the `errno` of the failed call is read here and handed to `PL_error`.
"""
    MarkExecutable(ld, name) -> Bool

Set the execute bits of the file `name` that the process mask allows; `false` after raising the error of a
failed `stat(2)` or `chmod(2)` (pl-files.c).
"""
function MarkExecutable(ld::PL_local_data{T}, name::String)::Bool where {T}
    um = _umask(0o777)
    _umask(um)
    st = statfunc(name)
    if st isa Int
        file = PL_new_term_ref(ld)
        PL_put_atom(ld, file, mk_sym(T, Symbol(name)))
        return PL_error(
            ld, "", 0, MSG_ERRNO, ERR_FILE_OPERATION, mk_sym(T, :stat), mk_sym(T, :file), file,
            -st
        )
    end
    mode = st.mode
    (mode & 0o111) == (~um & 0o111) && return true
    mode |= 0o111 & ~um
    if ccall((:chmod, LIBC), Cint, (Cstring, Cuint), name, mode % Cuint) == -1
        errno = Int(Base.Libc.errno())
        file = PL_new_term_ref(ld)
        PL_put_atom(ld, file, mk_sym(T, Symbol(name)))
        return PL_error(
            ld, "", 0, MSG_ERRNO, ERR_FILE_OPERATION, mk_sym(T, :chmod), mk_sym(T, :file), file,
            errno
        )
    end
    return true
end

# ORIGINAL (LB2b): the IRI hook of pl-file.c `iri_hook` calls the Prolog `$iri`:iri_hook/4 of init.pl; it is
# refused by name, left to LB4. `what` is the operation (`IRI_TIME`, `IRI_SIZE`, `IRI_ACCESS`).
function _iri_hook_refused(ld::PL_local_data{T}, fn::String, what::String) where {T}
    throw(NotPortedError{T}(mk_sym(T, Symbol(fn)), "iri_hook $what (`\$iri`:iri_hook/4 of init.pl)", "LB4"))
end

# ORIGINAL (LB2b): `sym_key` equality of an atom with the atom named `name`, for `PL_get_atom`'s result.
_is_atom_named(a, ::Type{T}, name::Symbol) where {T} = sym_key(a) == sym_key(mk_sym(T, name))

# ORIGINAL (LB2b): unify the term `t` with the atom whose text is `s` (`PL_unify_chars(t, PL_ATOM|REP_FN, -1, s)`).
_unify_atom_chars(ld::PL_local_data{T}, t::term_t, s::String) where {T} =
    PL_unify_atom(ld, t, mk_sym(T, Symbol(s)))

# PORT: pl-files.c time_file as pl_time_file2_va
# (PRED_IMPL("time_file", 2, time_file, 0))
# DIVERGES: an IRI raises `NotPortedError` (`iri_hook`, left to LB4).
"`time_file(+File, -Time)`: the modification time of the file as a float; `existence_error` etc. by `errno` (pl-files.c)."
function pl_time_file2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    fn = PL_get_file_name(ld, A1, 0)
    fn === nothing && return FFALSE
    file_name_is_iri(fn) != 0 && _iri_hook_refused(ld, fn, "IRI_TIME")
    time, errno = LastModifiedFile(fn)
    errno == 0 && return PL_unify_float(ld, A2, time) ? FTRUE : FFALSE
    rc = PL_error(ld, "", 0, "", ERR_FILE_OPERATION, mk_sym(T, :time), mk_sym(T, :file), A1, errno)
    return rc ? FTRUE : FFALSE
end

# PORT: pl-files.c size_file as pl_size_file2_va
# (PRED_IMPL("size_file", 2, size_file, 0))
# DIVERGES: an IRI raises `NotPortedError` (`iri_hook`, left to LB4).
"`size_file(+File, -Size)`: the size of the file in bytes (pl-files.c)."
function pl_size_file2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    n = PL_get_file_name(ld, A1, 0)
    n === nothing && return FFALSE
    file_name_is_iri(n) != 0 && _iri_hook_refused(ld, n, "IRI_SIZE")
    size, errno = SizeFile(n)
    if size < 0
        rc = PL_error(
            ld, "size_file", 2, MSG_ERRNO, ERR_FILE_OPERATION, mk_sym(T, :size), mk_sym(T, :file), A1,
            errno
        )
        return rc ? FTRUE : FFALSE
    end
    return PL_unify_int64(ld, A2, Int(size)) ? FTRUE : FFALSE
end

# PORT: pl-files.c access_file as pl_access_file2_va
# (PRED_IMPL("access_file", 2, access_file, 0))
# DIVERGES: an IRI raises `NotPortedError` (`iri_hook`, left to LB4).
"`access_file(+File, +Mode)`: the file can be accessed in `Mode` (pl-files.c)."
function pl_access_file2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    name, mode = PL__t0, PL__t0 + 1
    m = PL_get_atom(ld, mode)
    if m === nothing
        PL_error(ld, "access_file", 2, "", ERR_TYPE, mk_sym(T, :atom), mode)
        return FFALSE
    end
    n = PL_get_file_name(ld, name, 0)
    n === nothing && return FFALSE
    _is_atom_named(m, T, :none) && return FTRUE
    md = if _is_atom_named(m, T, :write) || _is_atom_named(m, T, :append)
        ACCESS_WRITE
    elseif _is_atom_named(m, T, :read)
        ACCESS_READ
    elseif _is_atom_named(m, T, :execute) || _is_atom_named(m, T, :search)
        ACCESS_EXECUTE
    elseif _is_atom_named(m, T, :exist)
        ACCESS_EXIST
    else
        PL_error(ld, "access_file", 2, "", ERR_DOMAIN, mk_sym(T, :io_mode), mode)
        return FFALSE
    end
    file_name_is_iri(n) != 0 && _iri_hook_refused(ld, n, "IRI_ACCESS")
    AccessFile(n, md) && return FTRUE
    if md == ACCESS_WRITE && !AccessFile(n, ACCESS_EXIST)
        dir = DirName(n)
        if dir === nothing
            PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :max_path_length))
            return FFALSE
        end
        if !isempty(dir)
            ExistsDirectory(dir) || return FFALSE
        end
        AccessDirectory(isempty(dir) ? "." : dir, md) && return FTRUE
    end
    return FFALSE
end

# PORT: pl-files.c read_link as pl_read_link3_va
# (PRED_IMPL("read_link", 3, read_link, 0))
"`read_link(+File, -Link, -Target)`: the text of the symbolic link and its final destination (pl-files.c)."
function pl_read_link3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    file, link, to = PL__t0, PL__t0 + 1, PL__t0 + 2
    n = PL_get_file_name(ld, file, 0)
    n === nothing && return FFALSE
    l = ReadLink(n)
    l === nothing && return FFALSE
    _unify_atom_chars(ld, link, l) || return FFALSE
    t = DeRefLink(ld, n)
    t === nothing && return FFALSE
    return _unify_atom_chars(ld, to, t) ? FTRUE : FFALSE
end

# PORT: pl-files.c exists_file as pl_exists_file1_va
# (PRED_IMPL("exists_file", 1, exists_file, 0))
# DIVERGES: an IRI raises `NotPortedError` (`iri_hook`, left to LB4).
"`exists_file(+File)`: the file exists and is a regular file (pl-files.c)."
function pl_exists_file1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    n = PL_get_file_name(ld, PL__t0, 0)
    n === nothing && return FFALSE
    file_name_is_iri(n) != 0 && _iri_hook_refused(ld, n, "IRI_ACCESS ACCESS_FILE")
    return ExistsFile(n) ? FTRUE : FFALSE
end

# PORT: pl-files.c exists_directory as pl_exists_directory1_va
# (PRED_IMPL("exists_directory", 1, exists_directory, 0))
# DIVERGES: an IRI raises `NotPortedError` (`iri_hook`, left to LB4).
"`exists_directory(+Dir)`: the directory exists (pl-files.c)."
function pl_exists_directory1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    n = PL_get_file_name(ld, PL__t0, 0)
    n === nothing && return FFALSE
    file_name_is_iri(n) != 0 && _iri_hook_refused(ld, n, "IRI_ACCESS ACCESS_DIRECTORY")
    return ExistsDirectory(n) ? FTRUE : FFALSE
end

# PORT: pl-files.c is_absolute_file_name as pl_is_absolute_file_name1_va
# (PRED_IMPL("is_absolute_file_name", 1, is_absolute_file_name, 0))
"`is_absolute_file_name(+File)`: the name is absolute or an IRI (pl-files.c)."
function pl_is_absolute_file_name1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    n = PL_get_file_name(ld, PL__t0, 0)
    n === nothing && return FFALSE
    return (IsAbsolutePath(n) || file_name_is_iri(n) != 0) ? FTRUE : FFALSE
end

# PORT: pl-files.c same_file as pl_same_file2_va
# (PRED_IMPL("same_file", 2, same_file, 0))
"`same_file(+File1, +File2)`: the two names denote the same file (pl-files.c)."
function pl_same_file2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    n1 = PL_get_file_name(ld, PL__t0, 0)
    n1 === nothing && return FFALSE
    n2 = PL_get_file_name(ld, PL__t0 + 1, 0)
    n2 === nothing && return FFALSE
    return SameFile(ld, n1, n2) ? FTRUE : FFALSE
end

# PORT: pl-files.c file_base_name as pl_file_base_name2_va
# (PRED_IMPL("file_base_name", 2, file_base_name, 0))
"`file_base_name(+Path, -Base)`: the last component of the path (pl-files.c)."
function pl_file_base_name2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    txt = PL_get_text(ld, PL__t0, CVT_ALL | CVT_EXCEPTION)
    txt === nothing && return FFALSE
    b = BaseName(text_string(txt))
    if b === nothing
        PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :max_path_length))
        return FFALSE
    end
    return _unify_atom_chars(ld, PL__t0 + 1, b) ? FTRUE : FFALSE
end

# PORT: pl-files.c file_directory_name as pl_file_directory_name2_va
# (PRED_IMPL("file_directory_name", 2, file_directory_name, 0))
"`file_directory_name(+Path, -Dir)`: the directory part of the path (pl-files.c)."
function pl_file_directory_name2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    txt = PL_get_text(ld, PL__t0, CVT_ALL | CVT_EXCEPTION)
    txt === nothing && return FFALSE
    d = DirName(text_string(txt))
    if d === nothing
        PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :max_path_length))
        return FFALSE
    end
    return _unify_atom_chars(ld, PL__t0 + 1, d) ? FTRUE : FFALSE
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

# ORIGINAL (LB2b): `rmdir(2)`.
_rmdir(path::String)::Int =
    ccall((:rmdir, LIBC), Cint, (Cstring,), path) == 0 ? 0 : Int(Base.Libc.errno())

# ORIGINAL (LB2b): `mkdir(2)`.
_mkdir(path::String, mode::Integer)::Int =
    ccall((:mkdir, LIBC), Cint, (Cstring, Cuint), path, mode % Cuint) == 0 ? 0 :
    Int(Base.Libc.errno())

# PORT: pl-files.c delete_directory as pl_delete_directory1_va
# (PRED_IMPL("delete_directory", 1, delete_directory, 0))
"`delete_directory(+Dir)`: remove an empty directory (pl-files.c)."
function pl_delete_directory1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    n = PL_get_file_name(ld, A1, 0)
    n === nothing && return FFALSE
    errno = _rmdir(n)
    errno == 0 && return FTRUE
    rc = PL_error(
        ld, "", 0, MSG_ERRNO, ERR_FILE_OPERATION, mk_sym(T, :delete), mk_sym(T, :directory), A1,
        errno
    )
    return rc ? FTRUE : FFALSE
end

# PORT: pl-files.c make_directory as pl_make_directory1_va
# (PRED_IMPL("make_directory", 1, make_directory, 0))
"The directory-creating predicate of `mkdir(2)`, mode 0777 (pl-files.c)."
function pl_make_directory1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    n = PL_get_file_name(ld, A1, 0)
    n === nothing && return FFALSE
    errno = _mkdir(n, 0o777)
    errno == 0 && return FTRUE
    rc = PL_error(
        ld, "", 0, MSG_ERRNO, ERR_FILE_OPERATION, mk_sym(T, :create), mk_sym(T, :directory), A1,
        errno
    )
    return rc ? FTRUE : FFALSE
end

# PORT: pl-files.c rename_file as pl_rename_file2_va
# (PRED_IMPL("rename_file", 2, rename_file, 0))
"`rename_file(+Old, +New)`: rename a file; with `file_errors` `fail` a failure just fails (pl-files.c)."
function pl_rename_file2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    old, new = PL__t0, PL__t0 + 1
    o = PL_get_file_name(ld, old, 0)
    o === nothing && return FFALSE
    n = PL_get_file_name(ld, new, 0)
    n === nothing && return FFALSE
    if SameFile(ld, o, n)
        if truePrologFlag(ld, PLFLAG_FILEERRORS)
            PL_error(
                ld, "rename_file", 2, "same file", ERR_PERMISSION, mk_sym(T, :rename),
                mk_sym(T, :file), old
            )
        end
        return FFALSE
    end
    errno = RenameFile(o, n)
    errno == 0 && return FTRUE
    if truePrologFlag(ld, PLFLAG_FILEERRORS)
        rc = PL_error(
            ld, "rename_file", 2, MSG_ERRNO, ERR_FILE_OPERATION, mk_sym(T, :rename),
            mk_sym(T, :file), old, errno
        )
        return rc ? FTRUE : FFALSE
    end
    return FFALSE
end

# PORT: pl-files.c absolute_file_name as pl_absolute_file_name2_va
# (PRED_IMPL("$absolute_file_name", 2, absolute_file_name, 0))
"`'\$absolute_file_name'(+Name, -Abs)`: the canonical absolute name (pl-files.c)."
function pl_absolute_file_name2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    n = PL_get_file_name(ld, PL__t0, 0)
    n === nothing && return FFALSE
    n = AbsoluteFile(ld, n)
    n === nothing && return FFALSE
    return _unify_atom_chars(ld, PL__t0 + 1, n) ? FTRUE : FFALSE
end

# PORT: pl-files.c cwd as pl_cwd1_va
# (PRED_IMPL("$cwd", 1, cwd, 0))
"`'\$cwd'(-Dir)`: the working directory, ending in `/` (pl-files.c)."
function pl_cwd1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    wd = PL_cwd(ld)
    wd === nothing && return FFALSE
    return _unify_atom_chars(ld, PL__t0, wd) ? FTRUE : FFALSE
end

# PORT: pl-files.c chdir as pl_chdir1_va
# (PRED_IMPL("$chdir", 1, chdir, 0))
# DIVERGES: when `ChDir` could not make the name absolute (-1) its error is the one raised and the predicate
# fails; upstream raises `ERR_FILE_OPERATION` over the stale `errno`.
"`'\$chdir'(+Dir)`: change the working directory (pl-files.c)."
function pl_chdir1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    n = PL_get_file_name(ld, A1, 0)
    n === nothing && return FFALSE
    errno = ChDir(ld, n)
    errno == 0 && return FTRUE
    if errno > 0 && truePrologFlag(ld, PLFLAG_FILEERRORS)
        rc = PL_error(
            ld, "", 0, "", ERR_FILE_OPERATION, mk_sym(T, :chdir), mk_sym(T, :directory), A1, errno
        )
        return rc ? FTRUE : FFALSE
    end
    return FFALSE
end

# PORT: pl-files.c has_extension
"Does the file name `name` end in the extension `ext` (a leading `.` of `ext` already removed) (pl-files.c)."
function has_extension(ld::PL_local_data, name::String, ext::String)::Bool
    isempty(ext) && return true
    b = codeunits(name)
    n = length(b)
    at(i) = i < n ? b[i + 1] : 0x00                    # C reads the NUL at `name + strlen(name)`
    s = n
    while at(s) != UInt8('.') && at(s) != UInt8('/') && s > 0
        s -= 1
    end
    if at(s) == UInt8('.') && s > 0 && at(s - 1) != UInt8('/')
        e = codeunits(ext)
        e = (!isempty(e) && e[1] == UInt8('.')) ? e[2:end] : e
        rest = b[(s + 2):n]
        truePrologFlag(ld, PLFLAG_FILE_CASE) && return rest == e
        return _ascii_lower(rest) == _ascii_lower(e)
    end
    return false
end

# PORT: pl-files.c file_name_extension as pl_file_name_extension3_va
# (PRED_IMPL("file_name_extension", 3, file_name_extension, 0), name_too_long)
# DIVERGES: the C `char *` scans are 0-based byte offsets into the name's UTF-8 bytes.
"`file_name_extension(?Base, ?Ext, ?Full)`: split or join a file name and its extension (pl-files.c)."
function pl_file_name_extension3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    base, ext, full = PL__t0, PL__t0 + 1, PL__t0 + 2
    if !PL_is_variable(ld, full)
        ftxt = PL_get_text(ld, full, CVT_ALL | CVT_EXCEPTION)
        if ftxt !== nothing
            f = codeunits(text_string(ftxt))
            n = length(f)
            at(i) = i < n ? f[i + 1] : 0x00
            s = n                                       # ?base, ?ext, +full
            while at(s) != UInt8('.') && at(s) != UInt8('/') && s > 0
                s -= 1
            end
            if at(s) == UInt8('.')
                after = f[(s + 2):n]
                etxt = PL_get_text(ld, ext, CVT_ALL)
                if etxt !== nothing
                    e = codeunits(text_string(etxt))
                    (!isempty(e) && e[1] == UInt8('.')) && (e = e[2:end])
                    same =
                        truePrologFlag(ld, PLFLAG_FILE_CASE) ? after == e :
                        _ascii_lower(after) == _ascii_lower(e)
                    same || return FFALSE
                else
                    _unify_atom_chars(ld, ext, String(copy(after))) || return FFALSE
                end
                return _unify_atom_chars(ld, base, String(f[1:s])) ? FTRUE : FFALSE
            end
            if _unify_atom_chars(ld, ext, "") && PL_unify(ld, full, base)
                return FTRUE
            end
        end
        return FFALSE
    end
    btxt = PL_get_text(ld, base, CVT_ALL | CVT_EXCEPTION)
    btxt === nothing && return FFALSE
    etxt = PL_get_text(ld, ext, CVT_ALL | CVT_EXCEPTION)
    etxt === nothing && return FFALSE
    b = text_string(btxt)
    e = text_string(etxt)
    startswith(e, '.') && (e = e[2:end])                # +Base, +Extension, -Full
    (has_extension(ld, b, e) || isempty(e)) && return PL_unify(ld, base, full) ? FTRUE : FFALSE
    if ncodeunits(b) + 1 + ncodeunits(e) + 1 > PATH_MAX
        PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :max_path_length))      # name_too_long()
        return FFALSE
    end
    return _unify_atom_chars(ld, full, b * "." * e) ? FTRUE : FFALSE
end

# PORT: pl-files.c prolog_to_os_filename as pl_prolog_to_os_filename2_va
# (PRED_IMPL("prolog_to_os_filename", 2, prolog_to_os_filename, 0))
# DIVERGES: the non-`O_XOS` branch, the only one on Unix: the two names are one.
"`prolog_to_os_filename(?Prolog, ?OS)`: the identity on Unix (pl-files.c)."
function pl_prolog_to_os_filename2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return PL_unify(ld, PL__t0, PL__t0 + 1) ? FTRUE : FFALSE
end

# PORT: pl-files.c mark_executable as pl_mark_executable1_va
# (PRED_IMPL("$mark_executable", 1, mark_executable, 0))
"`'\$mark_executable'(+File)`: set the execute bits the process mask allows (pl-files.c)."
function pl_mark_executable1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    name = PL_get_file_name(ld, PL__t0, 0)
    if name === nothing
        PL_error(ld, "", 0, "", ERR_DOMAIN, mk_sym(T, :source_sink), PL__t0)
        return FFALSE
    end
    return MarkExecutable(ld, name) ? FTRUE : FFALSE
end

# PORT: pl-files.c my_file as pl_my_file1_va
# (PRED_IMPL("$my_file", 1, my_file, 0))
# DIVERGES: `perror(3)` of a failed `stat(2)` writes `Name: strerror` to the standard error stream.
"""
    '\$my_file'(+Path)

True if Path exists and is owned by the user of the process (pl-files.c).
"""
function pl_my_file1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    n = PL_get_file_name(ld, PL__t0, 0)
    (n === nothing || file_name_is_iri(n) != 0) && return FFALSE
    st = statfunc(OsPath(n))
    if st isa Int
        println(stderr, OsPath(n), ": ", Base.Libc.strerror(-st))      # perror(tmp)
        return FFALSE
    end
    st.uid != ccall((:getuid, LIBC), Cuint, ()) && return FFALSE
    return FTRUE
end

# PORT: pl-files.c BeginPredDefs as PL_predicates_from_files
# DIVERGES: the entries ported so far (upstream's table has twenty-three; the two tmp_file entries follow in group G8).
"pl-files.c's registration table (`BeginPredDefs(files)`): the ported entries."
const PL_predicates_from_files = (
    PL_extension("\$cwd", 1, pl_cwd1_va, PL_FA_VARARGS),
    PL_extension("\$chdir", 1, pl_chdir1_va, PL_FA_VARARGS),
    PL_extension("access_file", 2, pl_access_file2_va, PL_FA_VARARGS),
    PL_extension("time_file", 2, pl_time_file2_va, PL_FA_VARARGS),
    PL_extension("size_file", 2, pl_size_file2_va, PL_FA_VARARGS),
    PL_extension("read_link", 3, pl_read_link3_va, PL_FA_VARARGS),
    PL_extension("exists_file", 1, pl_exists_file1_va, PL_FA_VARARGS),
    PL_extension("exists_directory", 1, pl_exists_directory1_va, PL_FA_VARARGS),
    PL_extension("delete_file", 1, pl_delete_file1_va, PL_FA_VARARGS),
    PL_extension("delete_directory", 1, pl_delete_directory1_va, PL_FA_VARARGS),
    PL_extension("make_directory", 1, pl_make_directory1_va, PL_FA_VARARGS),
    PL_extension("same_file", 2, pl_same_file2_va, PL_FA_VARARGS),
    PL_extension("rename_file", 2, pl_rename_file2_va, PL_FA_VARARGS),
    PL_extension("is_absolute_file_name", 1, pl_is_absolute_file_name1_va, PL_FA_VARARGS),
    PL_extension("file_base_name", 2, pl_file_base_name2_va, PL_FA_VARARGS),
    PL_extension("file_directory_name", 2, pl_file_directory_name2_va, PL_FA_VARARGS),
    PL_extension("file_name_extension", 3, pl_file_name_extension3_va, PL_FA_VARARGS),
    PL_extension("prolog_to_os_filename", 2, pl_prolog_to_os_filename2_va, PL_FA_VARARGS),
    PL_extension("\$mark_executable", 1, pl_mark_executable1_va, PL_FA_VARARGS),
    PL_extension("\$absolute_file_name", 2, pl_absolute_file_name2_va, PL_FA_VARARGS),
    PL_extension("\$my_file", 1, pl_my_file1_va, PL_FA_VARARGS),
)
