# `ext/` — package extensions

Glue code that loads only when an optional package is present (Julia `[weakdeps]` +
`[extensions]`). Empty: the kernel has no optional integrations yet. An extension may depend on a
weak dependency; `src/` may not.
