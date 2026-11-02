#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — the READ-ONLY CI API ROUTE shared by tools/ci_triage.sh and
# tools/battery_table.sh (audit D-0327). SOURCED, never run:  . "$ROOT/tools/ci_api.sh"
#
#   ci_slug                   the OWNER/NAME of `origin`
#   ci_jobs_page RUN PAGE     one page (100 jobs) of  GET /repos/<slug>/actions/runs/RUN/jobs  as JSON
#   ci_job_log JOB [RUN]      the log of one job (GET /repos/<slug>/actions/jobs/JOB/logs), ANSI colour
#                             codes and the byte-order mark removed; nothing and status 1 if unreadable
#
# The route is the one tools/ci_status.sh and tools/ci_wait.sh use: curl, anonymous first, then the stored
# token read with `git credential fill` and handed to curl on STDIN (`-K -`), never in argv, a variable that
# is exported, a file or the output. A job log is served to a signed-in caller only, so ci_job_log goes
# straight to the token and follows the redirect (curl drops the header on the host change). Only GET.
# `gh run view` is not used: it fails on a large run (HTTP 403 on the numeric paths through the proxy).
# Seam for tools/test_ci_tools.sh: LOGICKERNEL_CI_FIXTURE_DIR=<dir> reads <dir>/<run>/jobs_<page>.json and
# <dir>/<run>/<job>.log (saved real answers, tools/fixtures/ci/) instead of the network.

ci_slug() {
    git -C "${ROOT:-.}" remote get-url origin 2> /dev/null | sed -E 's#^.*github\.com[:/]##; s#\.git$##'
}

_ci_token() {
    printf 'protocol=https\nhost=github.com\n\n' |
        git -c credential.useHttpPath=false credential fill 2> /dev/null | sed -n 's/^password=//p'
}

ci_jobs_page() {   # ci_jobs_page RUN PAGE
    local run="$1" page="$2" out tok url
    if [ -n "${LOGICKERNEL_CI_FIXTURE_DIR:-}" ]; then
        if [ -f "$LOGICKERNEL_CI_FIXTURE_DIR/$run/jobs_$page.json" ]; then
            cat "$LOGICKERNEL_CI_FIXTURE_DIR/$run/jobs_$page.json"
        else
            printf '{"total_count":0,"jobs":[]}\n'
        fi
        return 0
    fi
    url="https://api.github.com/repos/$(ci_slug)/actions/runs/$run/jobs?per_page=100&page=$page"
    out="$(curl -s -m 25 "$url")"
    if ! printf '%s' "$out" | grep -q '"jobs"'; then
        tok="$(_ci_token)"
        [ -n "$tok" ] && out="$(printf 'header = "Authorization: Bearer %s"\n' "$tok" | curl -s -m 25 -K - "$url")"
        unset tok
    fi
    printf '%s\n' "$out"
}

ci_job_log() {   # ci_job_log JOB [RUN]
    local job="$1" run="${2:-}" f tok url tmp code
    if [ -n "${LOGICKERNEL_CI_FIXTURE_DIR:-}" ]; then
        if [ -n "$run" ]; then f="$LOGICKERNEL_CI_FIXTURE_DIR/$run/$job.log"
        else f="$(ls "$LOGICKERNEL_CI_FIXTURE_DIR"/*/"$job".log 2> /dev/null | sed -n 1p)"; fi
        [ -n "$f" ] && [ -f "$f" ] || return 1
        sed 's/\x1b\[[0-9;?]*[A-Za-z]//g; 1s/^\xef\xbb\xbf//' "$f"
        return 0
    fi
    url="https://api.github.com/repos/$(ci_slug)/actions/jobs/$job/logs"
    tok="$(_ci_token)"
    [ -n "$tok" ] || return 1
    tmp="$(mktemp "${TMPDIR:-/tmp}/ci_log.XXXXXX")"
    code="$(printf 'header = "Authorization: Bearer %s"\n' "$tok" | curl -s -L -m 120 -K - -o "$tmp" -w '%{http_code}' "$url")"
    unset tok
    if [ "$code" = 200 ]; then
        sed 's/\x1b\[[0-9;?]*[A-Za-z]//g; 1s/^\xef\xbb\xbf//' "$tmp"
        rm -f "$tmp"
        return 0
    fi
    rm -f "$tmp"
    return 1
}
