#!/bin/bash
# ORIGINAL (LB2b): the fixtures of test/files/test_lb2b_swipl.jl (its `_lb2b_fixtures`), made in the current (empty) directory
printf hello > lk_lb2b_file; : > lk_lb2b_file.txt; : > lk_lb2b_other.txt; : > lk_lb2b_other.pl; : > lk_lb2b_x.pl
mkdir lk_lb2b_dir lk_lb2b_dir/sub; : > lk_lb2b_dir/a1.txt; : > lk_lb2b_dir/b2.txt; : > lk_lb2b_dir/.hidden; : > lk_lb2b_dir/sub/deep.txt
ln -s lk_lb2b_file lk_lb2b_link; ln -s lk_lb2b_dir lk_lb2b_dlink; ln -s lk_lb2b_nowhere lk_lb2b_dangling
ln -s lk_lb2b_loop2 lk_lb2b_loop1; ln -s lk_lb2b_loop1 lk_lb2b_loop2
: > lk_lb2b_exec; chmod 755 lk_lb2b_exec; : > lk_lb2b_ro; chmod 444 lk_lb2b_ro
: > lk_lb2b_r1; : > lk_lb2b_r2; : > lk_lb2b_r3; : > lk_lb2b_r4; mkdir lk_lb2b_rd1; : > lk_lb2b_m1
