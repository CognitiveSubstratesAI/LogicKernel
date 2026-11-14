# UPSTREAM: swipl-devel src/os/pl-apple.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2022, SWI-Prolog Solutions b.v.
# allow-new-artifact: a 1:1 port of swipl-devel src/os/pl-apple.c (the upstream file was read at the pin; handoff evidence/S2/lane_d_handoff11.md)
#
# THE APPLE PLATFORM (pl-apple.c), LB5-LB7 relay 11, owner step APPLE1. UNTESTED, nothing compiled. pl-apple.c is
# a macOS-only file (`#include <CoreFoundation/CoreFoundation.h>`): its one predicate asks CoreFoundation for the
# identifier of the current locale. The kernel has no CoreFoundation binding, so the predicate is refused by name;
# a Linux build of swipl (the pin's) has no such predicate and answers `existence_error(procedure, ...)`.

# PORT: pl-apple.c apple_current_locale_identifier as pl_apple_current_locale_identifier1_va
# (PRED_IMPL("apple_current_locale_identifier", 1, apple_current_locale_identifier, 0), pl-apple.c:56-79:
#     CFLocaleCopyCurrent(), CFLocaleGetIdentifier(), cStringFromCFString(identifier, kCFStringEncodingUTF8),
#     then `PL_unify_chars(A1, PL_ATOM|REP_UTF8, (size_t)-1, buffer)`; `PL_resource_error("memory")` when the
#     conversion fails; failure when there is no current locale)
# DIVERGES: refused by name (platform): the file has no meaning without CoreFoundation, and the helper
# `cStringFromCFString` (pl-apple.c:38-53) is a CoreFoundation call chain.
"`apple_current_locale_identifier(-Id)`: refused by name, macOS only (pl-apple.c:56-79)."
function pl_apple_current_locale_identifier1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    throw(
        NotPortedError{T}(
            mk_sym(T, :apple_current_locale_identifier),
            "apple_current_locale_identifier/1: macOS only, CoreFoundation (pl-apple.c:56-79)",
            "APPLE1"
        )
    )
end

# PORT: pl-apple.c BeginPredDefs as PL_predicates_from_apple
# DIVERGES: none in the table (one entry, flags 0 upstream; the kernel's varargs form adds PL_FA_VARARGS).
"pl-apple.c's registration table (`BeginPredDefs(apple)`)."
const PL_predicates_from_apple = (
    PL_extension(
        "apple_current_locale_identifier", 1, pl_apple_current_locale_identifier1_va,
        PL_FA_VARARGS
    ),
)
