# Port inventory

One row per kernel file that ports or re-expresses upstream code. A port is not done until its row
is here, its file header records the same upstream file and commit, and (for ported code) the
header reproduces the upstream file's copyright line verbatim — see `NOTICE`.

**Class** decides the method:

* **code** — the algorithm carries over (tries, variant checking, term hashing, WFS delays and
  completion, index assessment, attributed-variable hooks). Upstream's tests come WITH the port,
  and SWI-Prolog runs as a live differential under `test/oracle/`.
* **design** — re-expressed for every-clause-fires, multiset semantics, never transliterated
  (clause compilation, instructions, frames, generations, clause GC).
* **skip** — Prolog-the-language runtime: modules, streams, threads, the foreign interface, the
  debugger, ISO built-ins. Listed only when a reader might expect it here.

**Upstream commit** is the commit the file was READ at, so a later upstream sweep knows what to diff
against.

| SWI file | class | upstream commit | kernel file |
|---|---|---|---|
