# UPSTREAM: swipl-devel src/os/pl-file.c @ bae881a2
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# THE STREAM TABLE, the part the loader needs (R1f): the file name an open stream reads, which
# upstream keeps in the stream's context (`getStreamContext(s)->filename`) and the reader puts in a
# term's source location and a syntax error's `file(…)`. NOT PORTED: the stream table itself —
# aliases, `current_input`/`current_output`, open/close/4, the stream properties (R2).

# PORT: pl-file.c fileNameStream
# DIVERGES: the name lives in the database's `stream_filenames` (src/pl-global.jl), where upstream
# keeps it in the stream's context; no lock (no threads).
"The name of the file `s` reads, or `nothing` (pl-file.c)."
fileNameStream(gd::PL_global_data{T}, s::IOSTREAM) where {T} =
    get(gd.stream_filenames, s, nothing)::Union{Nothing, T}

# PORT: pl-file.c setFileNameStream
# DIVERGES: as `fileNameStream`; `nothing` is upstream's NULL_ATOM — it, or `''`, forgets the
# stream's name (`setFileNameStream_unlocked`); no lock.
"Record that `s` reads the file named `name` (pl-file.c)."
function setFileNameStream(
    gd::PL_global_data{T}, s::IOSTREAM, name::Union{Nothing, T}
)::Bool where {T}
    if name === nothing || sym_text(name) == ""
        delete!(gd.stream_filenames, s)
    else
        gd.stream_filenames[s] = name
    end
    return true
end
