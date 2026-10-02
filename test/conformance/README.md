# `test/conformance/` — the term-interface conformance suite

ONE suite, run against EVERY implementation of the term interface, starting with the default term
type here (the reference). Written as functions that take the term type and a fixture set, never
against one concrete type, so any package implementing the interface can run it from its own tests. With only one implementation the interface is whatever that implementation does.
