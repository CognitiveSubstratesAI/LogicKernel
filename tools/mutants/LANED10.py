# ORIGINAL: lane D's mutant list (piece 10, laned) — no swipl-devel counterpart.
# tools/mutants/LANED10.py — S2b: open/4's lock(Lock) and wait(Bool) options (pl-file.c openStream, pl-stream.c Sopen_file's fcntl lock).
# Format: as LANED7.py. UNTESTED: nothing was compiled. Every `old` occurs exactly once in its file (tools/oldscan.py-style count).
# TARGETS: test_lane_d_swipl.jl (rows l01-l12, the holder rows x01-x08, the lock-letter testset) and test_open_close_swipl.jl (the how-letter
# rows of Sopen_file); every other test file opens a file but takes no lock, so none reaches the mutated branches.
# EQUIVALENT: LD10-4 (the EINTR retry): no signal reaches the test process during the fcntl call.
TL = ["test/core_lang/test_lane_d_swipl.jl", "test/files/test_open_close_swipl.jl"]
TARGETS = TL
F = "src/os/pl-file.jl"
G = "src/os/pl-stream.jl"
MUTANTS = [
    dict(id="LD10-1 _fcntl_lock: the lock types are swapped (KILL: the lock-letter testset: rlr is EBADF; rows l01, l03)", file=G, targets=TL,
         old="    buf[1] = lock == 1 ? 0x00 : 0x01                    # l_type: F_RDLCK, F_WRLCK (little endian short)\n",
         new="    buf[1] = lock == 1 ? 0x01 : 0x00                    # l_type: F_RDLCK, F_WRLCK (little endian short)\n"),
    dict(id="LD10-2 _fcntl_lock: never waits, F_SETLK always (KILL: x07, x08: the holder lets go after 0.5 s)", file=G, targets=TL,
         old="    cmd = wait ? Cint(7) : Cint(6)                      # F_SETLKW, F_SETLK\n",
         new="    cmd = Cint(6)                                       # F_SETLKW, F_SETLK\n"),
    dict(id="LD10-3 _fcntl_lock: always waits, F_SETLKW (KILL: x01, x02, x05, x06: the holder lets go after 3 s and the open answers `opened`)", file=G, targets=TL,
         old="    cmd = wait ? Cint(7) : Cint(6)                      # F_SETLKW, F_SETLK\n",
         new="    cmd = Cint(7)                                       # F_SETLKW, F_SETLK\n"),
    dict(id="LD10-4 _fcntl_lock: an EINTR is an error, not a retry", file=G, targets=TL,
         old="        e == 4 || return e                              # EINTR: try again\n",
         new="        return e                                        # EINTR: try again\n",
         equivalent="no signal reaches the test process while fcntl runs; the retry branch has no caller in the tests (upstream's loop is the same)"),
    dict(id="LD10-5 Sopen_file: L does not clear wait (KILL: x01, x02, x05, x06)", file=G, targets=TL,
         old="            c == 'L' && (wait = false)\n",
         new=""),
    dict(id="LD10-6 Sopen_file: the r letter is a write lock (KILL: l01, rlr)", file=G, targets=TL,
         old="            if i <= lastindex(how) && how[i] == 'r'\n                lock = 1\n",
         new="            if i <= lastindex(how) && how[i] == 'r'\n                lock = 2\n"),
    dict(id="LD10-7 Sopen_file: the w letter is a read lock (KILL: l03, wlw)", file=G, targets=TL,
         old="            elseif i <= lastindex(how) && how[i] == 'w'\n                lock = 2\n",
         new="            elseif i <= lastindex(how) && how[i] == 'w'\n                lock = 1\n"),
    dict(id="LD10-8 Sopen_file: a bad lock letter is accepted (KILL: rlx, rl)", file=G, targets=TL,
         old="            else\n                return (nothing, EINVAL)\n            end\n        elseif c == 'm'",
         new="            else\n                lock = 1\n            end\n        elseif c == 'm'"),
    dict(id="LD10-9 Sopen_file: a failed lock opens the stream anyway (KILL: l05, l10, rlw: EBADF)", file=G, targets=TL,
         old="        if lerr != 0\n            close(io)\n            return (nothing, lerr)\n        end\n",
         new="        if lerr != 0\n            close(io)\n        end\n"),
    dict(id="LD10-10 Sopen_file: a failed lock answers errno 0 (KILL: l05, rlw: the errno must be EBADF)", file=G, targets=TL,
         old="            return (nothing, lerr)\n",
         new="            return (nothing, 0)\n"),
    dict(id="LD10-11 Sopen_file: the lock is never taken (KILL: x01, x02, x05, x06, l05, rlw)", file=G, targets=TL,
         old="    if lock != 0\n        lerr = _fcntl_lock(io, lock, wait)\n",
         new="    if false\n        lerr = _fcntl_lock(io, lock, wait)\n"),
    dict(id="LD10-12 openStream: the lock letter is always l (KILL: x01, x02, x05, x06)", file=F, targets=TL,
         old="        push!(how, wait ? 'l' : 'L')\n",
         new="        push!(how, 'l')\n"),
    dict(id="LD10-13 openStream: lock(shared) is a write lock (KILL: l02)", file=F, targets=TL,
         old="        push!(how, (_sym_is(lock, :read) || _sym_is(lock, :shared)) ? 'r' : 'w')\n",
         new="        push!(how, _sym_is(lock, :read) ? 'r' : 'w')\n"),
    dict(id="LD10-14 openStream: the wait option is not read (KILL: x01, x02, x05, x06: wait(false) would wait)", file=F, targets=TL,
         old="        b8 = vals[8]\n        b8 isa Bool && (wait = b8)\n",
         new="        b8 = vals[8]\n"),
    dict(id="LD10-15 openStream: lock(exclusive) is a domain error (KILL: l04)", file=F, targets=TL,
         old="            _sym_is(lock, :read) || _sym_is(lock, :shared) || _sym_is(lock, :write) ||\n            _sym_is(lock, :exclusive)\n",
         new="            _sym_is(lock, :read) || _sym_is(lock, :shared) || _sym_is(lock, :write)\n"),
]
