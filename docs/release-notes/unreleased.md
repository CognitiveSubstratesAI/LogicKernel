# LogicKernel — unreleased changes (the next pre-release)

Entries are added by the step that makes the change, in the same commit; the release copies them into its
own notes file.

## Changed: the host-facing Julia API

* **`load_file!(gd, ld, path)` returns `(status, ball)`** (was `(status, ball, messages)`; R2 LB4 b2, audit
  D-0286 item 4). A database is now booted from SWI-Prolog's own boot files, and `load_file!` runs their
  `load_files(Path, [])` in `user`: `status` is `:ok`, `:failed` or `:exception` (then `ball` is the
  uncaught exception, else `nothing`). The load's messages are no longer returned: they go through
  print_message/2, as in SWI-Prolog; a host that wants them defines `user:message_hook/3`. The old return
  shape is removed, with no compatibility form.
