# UPSTREAM: swipl-devel src/pl-load.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2022, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# allow-new-artifact: packages/json C port (Phase 1): the static-extension form of pl-load.c, read from the pin (git show 18168e62)
#
# pl-load.c (loading foreign code), the O_STATIC_EXTENSIONS form ONLY: `$activate_static_extension/1`, which
# boot/syspred.pl's static branch of `use_foreign_library/1` calls (`:- elif(current_predicate(
# '$activate_static_extension'/1))`). Upstream builds this form for the WASM and static builds, where the
# packages' C files are linked in and `static_packages.h` lists `{name, install function}`.
#
# Left out (the shared-object form, `#ifndef O_STATIC_EXTENSIONS`): `open_shared_object`, `close_shared_object`,
# `call_shared_object_function`, the dlopen emulation and `cleanupForeign`'s list of loaded objects.
#
# The shared-object form (`open_shared_object/2,3`, `close_shared_object/1`, `call_shared_object_function/2`,
# the dlopen emulation) stays with the flag `open_shared_object` (undefined: D-0151, FLAG F8). The kernel can load no
# shared object, so every foreign library is a static extension.
#
# DIVERGES (file-wide):
#   1. `static_extensions` is the table `static_packages.h` generates: a tuple of `(name, install function)`,
#      filled by the ported packages (JSON1: json, src/pl-json.jl).
#   2. The install function takes the local data and registers nothing: the extension's predicates are registered in
#      module `system` at boot (the file header of src/pl-json.jl, 1), since the kernel has no per-module foreign
#      registration. `$activate_static_extension(json)` therefore succeeds and the predicates already exist.

# ORIGINAL (JSON1): upstream's `static_extensions`, the generated `static_packages.h`.
# DIVERGES: see the file header, 1.
"The static extensions, `(name, install function)` (pl-load.c `static_extensions`, generated `static_packages.h`)."
const static_extensions = (
    ("json", install_json), ("pcre4pl", install_pcre4pl), ("zlib4pl", install_zlib4pl)
)

# PORT: pl-load.c activate_static_extension
# DIVERGES: the extension is looked up by name in `static_extensions`, as the `USE_DLOPEN_SELF` == 0 branch does
# (the other branch's `dlsym(handle, "install_<name>")` has no twin); see the file header, 2.
"Call the install function of the static extension `ename`; false if there is none (pl-load.c)."
function activate_static_extension(ld::PL_local_data{T}, ename::String)::Bool where {T}
    for (name, install) in static_extensions
        if name == ename
            install(ld)
            return true
        end
    end
    return false
end

# PORT: pl-load.c activate_static_extension as pl_activate_static_extension1_va
# (PRED_IMPL("$activate_static_extension", 1, activate_static_extension, PL_FA_TRANSPARENT))
"`'\$activate_static_extension'(+Name)`: install the static extension `Name`; `existence_error(foreign_extension, Name)` if there is none (pl-load.c)."
function pl_activate_static_extension1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    txt = PL_get_text(ld, A1, CVT_ATOM | CVT_STRING | CVT_EXCEPTION)     # PL_get_chars(A1, &ename, …)
    txt === nothing && return FFALSE
    activate_static_extension(ld, text_string(txt)) && return FTRUE
    return PL_error(ld, ERR_EXISTENCE, mk_sym(T, :foreign_extension), A1) ? FTRUE : FFALSE
end

# PORT: pl-load.c BeginPredDefs as PL_predicates_from_load
# DIVERGES: the table of the static-extension form only (`PRED_DEF("$activate_static_extension", …)`).
const PL_predicates_from_load = (
    PL_extension(
        "\$activate_static_extension", 1, pl_activate_static_extension1_va,
        PL_FA_TRANSPARENT | PL_FA_VARARGS
    ),
)
