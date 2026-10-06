#!/bin/sh
# Fetch an https URL on a device that has OpenSSL but no TLS-capable client.
#
#   sh https_get.sh <url> <outfile> [--insecure]
#
# This board's curl is built without TLS -- `curl -V` says
# "Protocols: file ftp http tftp" -- and its busybox wget sends a plain HTTP
# request to port 443 and gets reset. But /bin/openssl is a full OpenSSL 3.5,
# so s_client can be the transport and the HTTP can be done by hand.
#
# The body is taken with `tail -c $content_length` rather than by hunting for
# the end of the headers: busybox grep has no -b, so there is no way to find a
# byte offset, and sed and awk are not safe on binary. The body is the last
# Content-Length bytes of the stream, which tail -c gets exactly.
#
# Progress is reported on stderr while the body arrives -- 21 MB over s_client
# takes long enough that a silent terminal looks like a hang. Only when stderr
# is a terminal; under a redirect it stays quiet, so logs are not filled with
# carriage returns.
#
# Certificates are verified against CA_BUNDLE (default /etc/ssl/cacert.pem).
# --insecure skips that, which is only for bootstrapping the bundle itself --
# and then only if you check what you got against a known hash.
set -e

URL=${1:?usage: https_get.sh <url> <outfile> [--insecure]}
OUT=${2:?usage: https_get.sh <url> <outfile> [--insecure]}
INSECURE=${3:-}
CA_BUNDLE=${CA_BUNDLE:-/etc/ssl/cacert.pem}
MAX_REDIRECT=${MAX_REDIRECT:-5}

die() { echo "https_get: $*" >&2; exit 1; }

verify_args() {
    if [ "$INSECURE" = "--insecure" ]; then
        # Nothing: s_client warns about the chain and carries on. Passing
        # -verify_return_error here would do the opposite of what the flag
        # name suggests and abort on the very failure we mean to ignore.
        echo ""
    elif [ -r "$CA_BUNDLE" ]; then
        echo "-CAfile $CA_BUNDLE -verify_return_error -verify 5"
    else
        die "no CA bundle at $CA_BUNDLE; fetch it first (see fetch_board.sh --bootstrap) or pass --insecure"
    fi
}

filesize() { wc -c < "$1" 2>/dev/null | tr -d ' ' || echo 0; }

# A one-line progress report, rewritten in place. Only when stderr is a
# terminal: under nohup or a redirect, carriage returns would turn the log into
# one unreadable line.
progress() {
    _file=$1 _pid=$2
    [ -t 2 ] || { wait "$_pid"; return $?; }
    _total=0 _spin=0
    while kill -0 "$_pid" 2>/dev/null; do
        _have=$(filesize "$_file")
        if [ "$_total" = 0 ]; then
            # Content-Length arrives in the first packet, so this resolves
            # almost at once and then stops being re-read.
            _total=$(sed -n 's/^[Cc]ontent-[Ll]ength: *//p' "$_file" 2>/dev/null \
                     | tr -d '\r' | head -1)
            [ -n "$_total" ] || _total=0
        fi
        if [ "$_total" -gt 0 ] 2>/dev/null; then
            _pct=$(( _have * 100 / _total ))
            [ "$_pct" -gt 100 ] && _pct=100
            _done=$(( _pct / 5 )) _bar= _k=0
            while [ "$_k" -lt 20 ]; do
                if [ "$_k" -lt "$_done" ]; then _bar="$_bar#"; else _bar="$_bar."; fi
                _k=$(( _k + 1 ))
            done
            printf '\r  [%s] %3d%%  %s / %s bytes' \
                "$_bar" "$_pct" "$_have" "$_total" >&2
        else
            _spin=$(( (_spin + 1) % 4 ))
            printf '\r  connecting%.*s   ' "$_spin" "..." >&2
        fi
        sleep 1
    done
    wait "$_pid"
    _rc=$?
    printf '\r%-56s\r' '' >&2
    return $_rc
}

# One request. Writes the raw response (headers + body) to $1.
request() {
    _raw=$1 _host=$2 _port=$3 _path=$4 _method=$5
    printf '%s %s HTTP/1.1\r\nHost: %s\r\nUser-Agent: nt98539a-board\r\nAccept: */*\r\nConnection: close\r\n\r\n' \
        "$_method" "$_path" "$_host" \
      | openssl s_client -quiet -connect "$_host:$_port" -servername "$_host" \
          $(verify_args) 2>"$_raw.err" > "$_raw" &
    _pid=$!
    progress "$_raw" "$_pid" || {
        sed -n '1,4p' "$_raw.err" >&2; return 1; }
    [ -s "$_raw" ] || return 1
}

# Header lines only: everything up to the first empty line. Safe to read as
# text, since HTTP headers are text by definition.
headers() { sed -n '1,/^\r*$/p' "$1" 2>/dev/null; }

split_url() {  # sets SCHEME HOST PORT PATHQ
    case "$1" in
        https://*) SCHEME=https; rest=${1#https://}; PORT=443 ;;
        *) die "not an https url: $1" ;;
    esac
    HOST=${rest%%/*}
    case "$HOST" in *:*) PORT=${HOST##*:}; HOST=${HOST%%:*} ;; esac
    # A case, not `[ ... ] && PATHQ=/`: under set -e a trailing && list that
    # tests false returns non-zero, which takes the whole script down. That
    # cost a debugging round.
    case "$rest" in
        */*) PATHQ=/${rest#*/} ;;
        *)   PATHQ=/ ;;
    esac
}

TMP=${TMPDIR:-/tmp}/https_get.$$
trap 'rm -f "$TMP" "$TMP.h" "$TMP.err"' EXIT

n=0
while :; do
    n=$((n + 1))
    [ "$n" -le "$MAX_REDIRECT" ] || die "too many redirects"
    split_url "$URL"

    request "$TMP" "$HOST" "$PORT" "$PATHQ" GET \
      || die "connection to $HOST failed (certificate? try --insecure to test)"
    headers "$TMP" > "$TMP.h"

    status=$(sed -n '1s/^HTTP\/[0-9.]* \([0-9]*\).*/\1/p' "$TMP.h")
    case "$status" in
        30[12378])
            URL=$(sed -n 's/^[Ll]ocation: *//p' "$TMP.h" | tr -d '\r' | head -1)
            [ -n "$URL" ] || die "$status with no Location"
            continue
            ;;
        200) ;;
        *) die "HTTP $status for $PATHQ"; ;;
    esac

    len=$(sed -n 's/^[Cc]ontent-[Ll]ength: *//p' "$TMP.h" | tr -d '\r' | head -1)
    [ -n "$len" ] || die "no Content-Length; cannot split the body safely"
    tail -c "$len" "$TMP" > "$OUT" || die "could not write $OUT"
    got=$(wc -c < "$OUT")
    [ "$got" = "$len" ] || die "expected $len bytes, wrote $got"
    echo "$OUT  $got bytes"
    exit 0
done
