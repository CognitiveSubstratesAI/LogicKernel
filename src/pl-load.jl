# UPSTREAM: swipl-devel src/pl-load.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2022, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# allow-new-artifact: a 1:1 port of swipl-devel src/pl-load.c (the upstream file was read at the pin; handoff evidence/S2/lane_d_handoff11.md)
#
# FOREIGN EXTENSIONS (pl-load.c), LB5-LB7 relay 11. UNTESTED, nothing compiled. The kernel loads no shared object
# and links no static extension, so the file holds the one predicate of the `O_STATIC_EXTENSIONS` block as a refusal
# by name: `$activate_static_extension/1` (pl-load.c:450-540 at the pin; the predicate is defined only in a build with
# static extensions, the pin's own swipl answers `existence_error(procedure, ...)`). `open_shared_object/2,3`,
# `close_shared_object/1` and `call_shared_object_function/2` (pl-load.c, `HAVE_SHARED_OBJECTS`) are written by the
# step that gives the kernel a foreign interface; this file does not define them.

# PORT: pl-load.c activate_static_extension as pl_activate_static_extension1_va
# (PRED_IMPL("$activate_static_extension", 1, activate_static_extension, PL_FA_TRANSPARENT), pl-load.c:501-512;
# the helper `activate_static_extension(ename)` is pl-load.c:449-498: `dlsym(handle, "install_<ename>")` with
# `USE_DLOPEN_SELF`, else the table `static_extensions` of `static_packages.h`; upstream's order is
# `PL_get_chars(A1, &ename, CVT_ATOM|CVT_STRING|CVT_EXCEPTION)`, then the install function, else
# `PL_existence_error("foreign_extension", A1)`)
# DIVERGES: refused by name. The kernel has no `static_packages.h` table and no dynamic symbol table of its own
# executable to look an `install_<ename>` function up in.
"`\$activate_static_extension(+Name)`: refused by name, the kernel links no static extension (pl-load.c:450-540)."
function pl_activate_static_extension1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    throw(
        NotPortedError{T}(
            mk_sym(T, :activate_static_extension),
            "activate_static_extension/1: no static extensions in the kernel (pl-load.c:450-540)",
            "LB5-LB7"
        )
    )
end

# PORT: pl-load.c BeginPredDefs as PL_predicates_from_load
# DIVERGES: only the `O_STATIC_EXTENSIONS` entry; the `HAVE_SHARED_OBJECTS` entries are left out (see the file header).
"pl-load.c's registration table (`BeginPredDefs(dlopen)`): `\$activate_static_extension/1`."
const PL_predicates_from_load = (
    PL_extension(
        "\$activate_static_extension", 1, pl_activate_static_extension1_va,
        PL_FA_TRANSPARENT | PL_FA_VARARGS
    ),
)
