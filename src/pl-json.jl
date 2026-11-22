# CLASS: code
# COPYRIGHT: Copyright (c)  2007-2018, University of Amsterdam
# allow-new-artifact: packages/json C port (Phase 1)
#
# JSON1 (packages/json/json.c, packages-json 8be86c19 vendored at vendor/swipl-devel-extra/packages/json/json.c):
# the four foreign predicates library(json) uses for speed: `json_read_number/3`, `json_skip_ws/3`,
# `json_write_string/2`, `json_write_indent/3`. NO `# UPSTREAM:` header line: `packages/json` is a gitlink at
# the pin, not a blob of swipl-devel, so tools/port_check.jl cannot follow it yet (a tooling item, D2 of the
# JSON port handoff, evidence/R2/json_port_handoff.md).
#
# DIVERGES (file-wide):
#   1. REGISTERED IN `system` AT BOOT. Upstream's `install_json()` registers the four predicates into the
#      CALLING module (`json`) when library(json)'s `:- use_foreign_library(foreign(json))` runs. The kernel has no
#      per-module foreign registration (src/pl-ext.jl) and no shared objects, so the four predicates are a
#      table, `PL_predicates_from_json`, appended to `_PRED_TABLES` and `_FOREIGN_VA`: `json:json_skip_ws/3`
#      resolves through `system`, and `predicate_property(json:json_skip_ws(_,_,_), foreign)` holds, as upstream.
#      `use_foreign_library(foreign(json))` finds `json` in the static extensions (`$activate_static_extension/1`,
#      src/pl-load.jl); `install_json` is then the empty function. The predicates exist, and are
#      system predicates, before library(json) is loaded: that is the divergence. `system:'$foreign_registered'/2`
#      (called by `PL_register_foreign`) is therefore not called for them.
#   2. TEXT. `json_write_string/2` reads the text with ONE `PL_get_text` (CVT_EXCEPTION); upstream calls
#      `PL_get_nchars` (Latin-1) first, without CVT_EXCEPTION, then `PL_get_wchars` with it. Both branches walk the
#      same code sequence and raise the same errors, so one call is the same observable behaviour.
#   3. NO TEXT BUFFER: `json_read_number/3` collects the characters in a `Vector{UInt8}` where upstream's `text`
#      is a growing C buffer (`init_text`, `put_byte`, `free_text`), so there is no `PL_resource_error("memory")`.
#   4. `json_write_indent/3` with tab 0 divides by zero in C (the process dies): refused by name (NotPortedError,
#      step JSON1). A negative tab or indent follows C's truncating `/` and `%` (`÷`, `rem`).
#   5. `Sfprintf(out, "u%04x", c)` is not ported (`Sfprintf`): the `u` and the four or more lowercase hex digits are
#      written by `_json_put_u`.
#   6. NO LOCKS: `PL_get_stream` is `term_stream_handle`, `PL_release_stream` is `streamStatus` (src/os/pl-file.jl).

# PORT: packages/json/json.c json_put_code
# DIVERGES: see the file header, 5; the `escape` table is a `Dict`-free chain of the seven characters upstream
# names, in the same arms.
"The `u` and the hex digits of `c` (at least four, lowercase) after a backslash (`Sfprintf(out, \"u%04x\", c)`); 0, or -1."
function _json_put_u(out::IOSTREAM, c::Int)::Int
    Sputcode(Int('u'), out) < 0 && return -1
    for ch in string(c; base = 16, pad = 4)
        Sputcode(Int(ch), out) < 0 && return -1
    end
    return 0
end

# PORT: packages/json/json.c json_put_code
"Write the code `c` of a JSON string to `out`, `pc` being the previous code; 0, or -1 on a write error (json.c)."
function json_put_code(out::IOSTREAM, pc::Int, c::Int)::Int
    if c < 128
        esc = if c == Int('"')
            Int('"')
        elseif c == Int('\\')
            Int('\\')
        elseif c == 8                               # '\b'
            Int('b')
        elseif c == 12                              # '\f'
            Int('f')
        elseif c == 10                              # '\n'
            Int('n')
        elseif c == 13                              # '\r'
            Int('r')
        elseif c == 9                               # '\t'
            Int('t')
        else
            0
        end
        if esc != 0
            Sputcode(Int('\\'), out) < 0 && return -1
            Sputcode(esc, out) < 0 && return -1
        elseif c < Int(' ')                         # control characters *must* be escaped
            Sputcode(Int('\\'), out) < 0 && return -1
            _json_put_u(out, c) < 0 && return -1
        elseif pc == Int('<') && c == Int('/')      # Emit </ inside a string as <\/ to allow safe embedding in html
            Sputcode(Int('\\'), out) < 0 && return -1
            Sputcode(Int('/'), out) < 0 && return -1
        elseif pc == Int('<') && c == Int('!')      # Similar for <!, avoiding <!--
            Sputcode(Int('\\'), out) < 0 && return -1
            _json_put_u(out, c) < 0 && return -1
        else
            Sputcode(c, out) < 0 && return -1
        end
    elseif (c >= 0xD800 && c <= 0xDFFF) || c == 0x2028 || c == 0x2029
        # Surrogates cannot be represented in UTF-8, U+2028 and U+2029 are line terminators in JavaScript
        # before ES2019: emit the escape ourselves.
        Sputcode(Int('\\'), out) < 0 && return -1
        _json_put_u(out, c) < 0 && return -1
    else
        Sputcode(c, out) < 0 && return -1
    end
    return 0
end

# PORT: packages/json/json.c json_read_number
# (PRED_REGISTER: PL_register_foreign("json_read_number", 3, json_read_number, 0)) see the file header, 3.
# The characters are those `0-9 . - + e E`, peeked and read one by one; `PL_put_term_from_chars` then reads the
# number (`1.` reads as 1, `-` reads as the atom `-`: `PL_is_number` fails the second, the syntax error follows).
"`json_read_number(+Stream, +C0, -Number)`: read the JSON number that starts with the code `C0` (json.c)."
function pl_json_read_number3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    inp = term_stream_handle(ld, A1, SH_ERRORS | SH_ALIAS | SH_INPUT)  # PL_get_stream(stream, &in, SIO_INPUT)
    inp === nothing && return FFALSE
    c = PL_get_char(ld, A2)                         # PL_get_char_ex(c0, &c, false)
    c === nothing && return FFALSE

    buf = UInt8[UInt8(c & 0xff)]                    # put_byte(&t, c): `(char)c`
    rc = false
    while true
        c = Speekcode(inp)
        if (c >= Int('0') && c <= Int('9')) ||
                c == Int('.') || c == Int('-') || c == Int('+') || c == Int('e') || c == Int('E')
            push!(buf, UInt8(c))
            Sgetcode(inp)
            continue
        end
        tmp = PL_new_term_ref(ld)
        rc = PL_put_term_from_chars(ld, tmp, CVT_EXCEPTION, buf, length(buf)) &&
            PL_is_number(ld, tmp) &&
            PL_unify(ld, tmp, A3)
        break
    end

    if !rc && PL_exception(ld, 0) == 0
        rc = PL_syntax_error(ld, "illegal_number", inp)
    end

    streamStatus(ld, inp)                           # PL_release_stream(in): its value is ignored, its error is not

    return rc ? FTRUE : FFALSE
end

# PORT: packages/json/json.c is_ws
"Whether the code `c` is JSON white space (json.c)."
is_ws(c::Int)::Bool = c == Int(' ') || c == Int('\t') || c == Int('\n') || c == Int('\r')

# PORT: packages/json/json.c json_skip_ws
# (PL_register_foreign("json_skip_ws", 3, json_skip_ws, 0))
"`json_skip_ws(+Stream, +C0, -Next)`: skip white space after the code `C0`; `Next` is the first other code, -1 at end of file (json.c)."
function pl_json_skip_ws3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    c = _ct_get_char_ex(ld, A2)                     # PL_get_char_ex(c0, &c, true)
    c === nothing && return FFALSE

    if is_ws(c)
        inp = term_stream_handle(ld, A1, SH_ERRORS | SH_ALIAS | SH_INPUT)   # PL_get_stream(stream, &in, SIO_INPUT)
        inp === nothing && return FFALSE

        while true
            c = Sgetcode(inp)
            is_ws(c) || break
        end

        streamStatus(ld, inp) || return FFALSE      # PL_release_stream(in)
    end

    return PL_unify_integer(ld, A3, c) ? FTRUE : FFALSE
end

# PORT: packages/json/json.c json_write_string
# (PL_register_foreign("json_write_string", 2, json_write_string, 0)) see the file header, 2.
# CVT_INTEGER: integer keys, as may appear in dicts.
"`json_write_string(+Stream, +Text)`: write the text as a JSON string, quoted and escaped (json.c)."
function pl_json_write_string2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    out = term_stream_handle(ld, A1, SH_ERRORS | SH_ALIAS | SH_OUTPUT)  # PL_get_stream(stream, &out, SIO_OUTPUT)
    out === nothing && return FFALSE

    rc = true
    txt = PL_get_text(ld, A2, CVT_ATOM | CVT_STRING | CVT_LIST | CVT_INTEGER | CVT_EXCEPTION)
    if txt !== nothing
        codes = _text_code_points(txt)
        pc = 0
        if Sputcode(Int('"'), out) < 0
            rc = false
        else
            for c in codes
                if json_put_code(out, pc, c) < 0
                    rc = false
                    break
                end
                pc = c
            end
            if rc && Sputcode(Int('"'), out) < 0
                rc = false
            end
        end
    else
        rc = false
    end

    streamStatus(ld, out)                           # PL_release_stream(out): its value is ignored
    return rc ? FTRUE : FFALSE
end

# PORT: packages/json/json.c json_write_indent
# (PL_register_foreign("json_write_indent", 3, json_write_indent, 0)) see the file header, 4.
"`json_write_indent(+Stream, +Indent, +Tab)`: a newline (unless at the line start), then `Indent` columns as tabs and spaces (json.c)."
function pl_json_write_indent3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    i = PL_get_integer(ld, A2)
    i === nothing && return FFALSE
    t = PL_get_integer(ld, A3)
    t === nothing && return FFALSE

    out = term_stream_handle(ld, A1, SH_ERRORS | SH_ALIAS | SH_OUTPUT)  # PL_get_stream(stream, &out, SIO_OUTPUT)
    out === nothing && return FFALSE

    if t == 0
        throw(
            NotPortedError{T}(
                mk_sym(T, :json_write_indent),
                "tab 0: upstream divides by zero (json.c json_write_indent: i/t)",
                "JSON1"
            )
        )
    end

    rc = true
    pos = out.position
    if pos === nothing || pos.linepos > 0
        Sputcode(Int('\n'), out) < 0 && (rc = false)
    end
    if rc
        n = i ÷ t                                   # C's truncating `/`
        for _ in 1:max(n, 0)
            if Sputcode(Int('\t'), out) < 0
                rc = false
                break
            end
        end
    end
    if rc
        n = rem(i, t)                               # C's `%`
        for _ in 1:max(n, 0)
            if Sputcode(Int(' '), out) < 0
                rc = false
                break
            end
        end
    end

    streamStatus(ld, out)                           # PL_release_stream(out): its value is ignored
    return rc ? FTRUE : FFALSE
end

# PORT: packages/json/json.c install_json
# DIVERGES: see the file header, 1: the four predicates are registered at boot (`PL_predicates_from_json`), so
# the function `$activate_static_extension(json)` calls has nothing left to register.
"The install function of the static extension `json` (json.c `install_json`): the predicates exist already."
function install_json(ld::PL_local_data{T})::Nothing where {T}
    return nothing
end

# PORT: packages/json/json.c install_json as PL_predicates_from_json
# DIVERGES: see the file header, 1: the registration is the boot table of module `system`.
const PL_predicates_from_json = (
    PL_extension("json_read_number", 3, pl_json_read_number3_va, PL_FA_VARARGS),
    PL_extension("json_skip_ws", 3, pl_json_skip_ws3_va, PL_FA_VARARGS),
    PL_extension("json_write_string", 2, pl_json_write_string2_va, PL_FA_VARARGS),
    PL_extension("json_write_indent", 3, pl_json_write_indent3_va, PL_FA_VARARGS)
)
