#!/usr/bin/env bash
# ORIGINAL: no swipl-devel counterpart — the READ-ONLY CI API ROUTE shared by tools/ci_triage.sh and
# tools/battery_table.sh (audit D-0327). SOURCED, never run:  . "$ROOT/tools/ci_api.sh"
#
#   ci_slug                   the OWNER/NAME of `origin`
#   ci_jobs_page RUN PAGE     one page (100 jobs) of  GET /repos/<slug>/actions/runs/RUN/jobs  as JSON
#   ci_runs_for_sha SHA       the workflow runs of one commit: GET /repos/<slug>/actions/runs?head_sha=SHA (tools/ci_marker.sh)
#   ci_job_log JOB [RUN]      the log of one job (GET /repos/<slug>/actions/jobs/JOB/logs), ANSI colour
#                             codes and the byte-order mark removed; nothing and status 1 if unreadable
#
# The route is the one tools/ci_status.sh and tools/ci_wait.sh use: curl, anonymous first, then the stored
# token read with `git credential fill` and handed to curl on STDIN (`-K -`), never in argv, a variable that
# is exported, a file or the output. A job log is served to a signed-in caller only, so ci_job_log goes
# straight to the token and follows the redirect (curl drops the header on the host change). Only GET.
# Every curl call here starts with `-q --noproxy '*'` (review4 F2, tools/ci_marker.sh reads a verdict through it): no ~/.curlrc and no
# proxy of the caller can redirect the read to another server.
# `gh run view` is not used: it fails on a large run (HTTP 403 on the numeric paths through the proxy).
# Seam for tools/test_ci_tools.sh: LOGICKERNEL_CI_FIXTURE_DIR=<dir> reads <dir>/<run>/jobs_<page>.json and
# <dir>/<run>/<job>.log (saved real answers, tools/fixtures/ci/) instead of the network.
# <dir>/runs_<sha>.json answers ci_runs_for_sha (an empty list when the file is not there).

ci_slug() {
    git -C "${ROOT:-.}" remote get-url origin 2> /dev/null | sed -E 's#^.*github\.com[:/]##; s#\.git$##'
}

_ci_token() {
    printf 'protocol=https\nhost=github.com\n\n' |
        git -c credential.useHttpPath=false credential fill 2> /dev/null | sed -n 's/^password=//p'
}

# _ci_get_authed URL [curl options...]: GET with the stored token, handed to curl on STDIN. ONE copy for the three callers
# (review TOOL4B N8): xtrace is switched off for the token's lifetime (`bash -x`, SHELLOPTS=xtrace would echo the printf line
# with the token to stderr) and restored afterwards. Status 1 when there is no token.
_ci_get_authed() {
    local _xt=0 url="$1" tok rc
    shift
    case $- in *x*) _xt=1 ;; esac
    { set +x; } 2> /dev/null
    tok="$(_ci_token)"
    if [ -z "$tok" ]; then
        rc=1
    else
        printf 'header = "Authorization: Bearer %s"\n' "$tok" | curl -q --noproxy '*' -s -K - "$@" "$url"
        rc=$?
    fi
    unset tok
    [ "$_xt" = 1 ] && set -x
    return "$rc"
}

ci_jobs_page() {   # ci_jobs_page RUN PAGE
    local run="$1" page="$2" out alt url
    if [ -n "${LOGICKERNEL_CI_FIXTURE_DIR:-}" ]; then
        if [ -f "$LOGICKERNEL_CI_FIXTURE_DIR/$run/jobs_$page.json" ]; then
            cat "$LOGICKERNEL_CI_FIXTURE_DIR/$run/jobs_$page.json"
        else
            printf '{"total_count":0,"jobs":[]}\n'
        fi
        return 0
    fi
    url="https://api.github.com/repos/$(ci_slug)/actions/runs/$run/jobs?per_page=100&page=$page"
    out="$(curl -q --noproxy '*' -s -m 25 "$url")"
    if ! printf '%s' "$out" | grep -q '"jobs"'; then
        alt="$(_ci_get_authed "$url" -m 25)" && out="$alt"
    fi
    printf '%s\n' "$out"
}

ci_runs_for_sha() {   # ci_runs_for_sha SHA (the full 40 hex)
    local sha="$1" out alt url
    if [ -n "${LOGICKERNEL_CI_FIXTURE_DIR:-}" ]; then
        if [ -f "$LOGICKERNEL_CI_FIXTURE_DIR/runs_$sha.json" ]; then
            cat "$LOGICKERNEL_CI_FIXTURE_DIR/runs_$sha.json"
        else
            printf '{"total_count":0,"workflow_runs":[]}\n'
        fi
        return 0
    fi
    url="https://api.github.com/repos/$(ci_slug)/actions/runs?head_sha=$sha&per_page=100"
    out="$(curl -q --noproxy '*' -s -m 25 "$url")"
    if ! printf '%s' "$out" | grep -q '"workflow_runs"'; then
        alt="$(_ci_get_authed "$url" -m 25)" && out="$alt"
    fi
    printf '%s\n' "$out"
}

ci_job_log() {   # ci_job_log JOB [RUN]
    local job="$1" run="${2:-}" f url tmp code
    if [ -n "${LOGICKERNEL_CI_FIXTURE_DIR:-}" ]; then
        if [ -n "$run" ]; then f="$LOGICKERNEL_CI_FIXTURE_DIR/$run/$job.log"
        else f="$(ls "$LOGICKERNEL_CI_FIXTURE_DIR"/*/"$job".log 2> /dev/null | sed -n 1p)"; fi
        [ -n "$f" ] && [ -f "$f" ] || return 1
        sed 's/\x1b\[[0-9;?]*[A-Za-z]//g; 1s/^\xef\xbb\xbf//' "$f"
        return 0
    fi
    url="https://api.github.com/repos/$(ci_slug)/actions/jobs/$job/logs"
    tmp="$(mktemp "${TMPDIR:-/tmp}/ci_log.XXXXXX")"
    code="$(_ci_get_authed "$url" -L -m 120 -o "$tmp" -w '%{http_code}')"
    if [ "$code" = 200 ]; then
        sed 's/\x1b\[[0-9;?]*[A-Za-z]//g; 1s/^\xef\xbb\xbf//' "$tmp"
        rm -f "$tmp"
        return 0
    fi
    rm -f "$tmp"
    return 1
}
