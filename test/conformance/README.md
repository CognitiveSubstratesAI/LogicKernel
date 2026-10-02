# `test/conformance/` — the term-interface conformance suite

ONE suite, run against EVERY implementation of the term interface: the default term type here
(the reference) and MeTTaCore's `Atom` (the second implementation, which includes these files from
Core's own tests). Written as functions that take the term type and a fixture set, never against one
concrete type. With only one implementation the interface is whatever that implementation does.
