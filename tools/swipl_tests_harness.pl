% ORIGINAL: no swipl-devel counterpart. The Prolog half of tools/swipl_tests_kernel.jl (R2 acceptance item (c),
% audit D-0624/D-0625): load ONE swipl-devel test file into the kernel and run what it holds the way
% tests/test.pl's run_test_script/1 does (load_files/2, then `call_test(Pred)` for a script file), plus
% plunit's run_tests/2 for the files that declare units (begin_tests/1). It prints `LK-RESULT <kind> <text>`
% lines on user_output; tools/swipl_tests_run.py reads only those lines.
%
% UNVERIFIED: written without running a kernel. A lane's first run decides it; every predicate used here is
% one boot/*.pl or library(plunit) defines, and the file loads no library itself (a test file that needs
% plunit loads it, as upstream's test files do).
%
% Kinds (the driver's table, tools/swipl_tests_run.py `classify`):
%   load-error <ball>        load_files/2 raised
%   load-failed              load_files/2 failed
%   summary total=N passed=N failed=N timeout=N blocked=N fixme=N     plunit's run_tests/2 summary dict
%   script passed|failed     the module-file's `Name/0` (tests/README: the exported predicate named as the file)
%   run-error <ball>         running the tests raised
%   no-tests                 neither units nor a script predicate
%   not-runnable <reason>    the file declares a prerequisite the kernel states it lacks

:- module(lk_swipl_tests, [lk_run_test_file/1]).

lk_run_test_file(File) :-
    (   catch(load_files(user:File, [silent(true), if(changed)]), E, true)
    ->  (   var(E)
        ->  lk_after_load(File)
        ;   lk_emit_ball('load-error', E)
        )
    ;   lk_emit('load-failed', '')
    ).

lk_after_load(File) :-
    file_base_name(File, Base),
    file_name_extension(Name, _, Base),
    lk_units(HaveUnits),
    lk_script(Name, HaveScript),
    (   HaveUnits == false,
        HaveScript == false
    ->  lk_emit('no-tests', '')
    ;   true
    ).

% plunit: run the units this file declared; the summary option makes run_tests/2 succeed with failures.
lk_units(Have) :-
    (   current_module(plunit),
        catch(plunit:current_test_unit(_, _), _, fail)
    ->  Have = true,
        catch(plunit:set_test_options([output(on_failure)]), _, true),
        catch(plunit:run_tests(all, [summary(S)]), E, true),
        (   nonvar(E)
        ->  lk_emit_ball('run-error', E)
        ;   var(S)
        ->  lk_emit('run-error', 'run_tests/2 gave no summary')
        ;   lk_dget(total, S, Total),
            lk_dget(passed, S, Passed),
            lk_dget(failed, S, Failed),
            lk_dget(timeout, S, Timeout),
            lk_dget(blocked, S, Blocked),
            lk_dget(fixme, S, Fixme),
            format(atom(T), 'total=~d passed=~d failed=~d timeout=~d blocked=~d fixme=~d',
                   [Total, Passed, Failed, Timeout, Blocked, Fixme]),
            lk_emit(summary, T)
        )
    ;   Have = false
    ).

lk_dget(Key, Dict, Value) :-
    (   get_dict(Key, Dict, V0)
    ->  Value = V0
    ;   Value = 0
    ).

% tests/README: a test file is a module named as the file, exporting Name/0, which succeeds when the test does.
lk_script(Name, Have) :-
    (   current_module(Name),
        Name \== lk_swipl_tests,
        current_predicate(Name:Name/0)
    ->  Have = true,
        catch(( Name:Name -> Outcome = passed ; Outcome = failed ), E, Outcome = error(E)),
        (   Outcome = error(Ball)
        ->  lk_emit_ball('run-error', Ball)
        ;   lk_emit(script, Outcome)
        )
    ;   Have = false
    ).

lk_emit_ball(Kind, Ball) :-
    format(atom(Q), '~q', [Ball]),
    lk_emit(Kind, Q).

% `~N` starts a fresh line: a test that printed without a newline does not swallow the marker.
lk_emit(Kind, Text) :-
    format(user_output, '~NLK-RESULT ~w ~w~n', [Kind, Text]),
    flush_output(user_output).
