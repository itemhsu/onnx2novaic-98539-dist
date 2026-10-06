#!/bin/sh
# Fetch a board artifact from the public mirror. Runs ON the NT98539A, needs
# no credentials.
#
#   sh fetch_board.sh --bootstrap              install the CA bundle, once
#   sh fetch_board.sh --list                   what is in the release
#   sh fetch_board.sh ai3_bench
#   sh fetch_board.sh nvt_model-539A-opmode2-5.bin model.bin
#
# The private repository cannot be used from here: a private asset has to be
# fetched through the API by asset id with a token, and this board's curl is
# built without TLS ("Protocols: file ftp http tftp"). The public mirror needs
# no token, and https_get.sh does the TLS with /bin/openssl, which the board
# does have.
#
# --bootstrap fetches the CA bundle unverified -- there is nothing to verify
# against yet -- and then checks it against the hash below before installing
# it. Update the hash when the bundle is refreshed upstream.
set -e

REPO=${REPO:-itemhsu/onnx2novaic-98539-dist}
TAG=${TAG:-v1}
BASE=https://github.com/$REPO/releases/download/$TAG
CA_BUNDLE=${CA_BUNDLE:-/etc/ssl/cacert.pem}
CA_URL=${CA_URL:-https://curl.se/ca/cacert.pem}
CA_SHA256=a41b5d356aea97a529fe27e0f7316d2f9d946d75927476cf9cf1b90637d00505

HERE=$(dirname "$0")
die() { echo "fetch_board: $*" >&2; exit 1; }

if [ "$1" = "--bootstrap" ]; then
    tmp=${TMPDIR:-/tmp}/cacert.$$
    sh "$HERE/https_get.sh" "$CA_URL" "$tmp" --insecure \
      || die "could not fetch the CA bundle"
    got=$(sha256sum "$tmp" | cut -d' ' -f1)
    if [ "$got" != "$CA_SHA256" ]; then
        rm -f "$tmp"
        die "CA bundle hash mismatch
  expected $CA_SHA256
  got      $got
The bundle was fetched without verification, so a mismatch means either it
was refreshed upstream -- check https://curl.se/docs/caextract.html and update
CA_SHA256 -- or something tampered with it. Not installing."
    fi
    mkdir -p "$(dirname "$CA_BUNDLE")"
    mv "$tmp" "$CA_BUNDLE"
    echo "installed $CA_BUNDLE ($(wc -c < "$CA_BUNDLE") bytes, hash verified)"
    exit 0
fi

if [ "$1" = "--list" ]; then
    [ -r "$CA_BUNDLE" ] || die "no CA bundle at $CA_BUNDLE -- run: sh $0 --bootstrap"
    tmp=${TMPDIR:-/tmp}/rel.$$
    # A public repository's release API needs no credentials.
    sh "$HERE/https_get.sh" "https://api.github.com/repos/$REPO/releases/tags/$TAG" \
       "$tmp" >/dev/null || die "could not read the release list"
    # The API returns compact JSON here but pretty-printed for an
    # authenticated request, so normalise first: splitting on commas puts one
    # field per line either way. Names after "assets":[ only -- the release
    # object has a "name" of its own, which is its title.
    tr ',' '\n' < "$tmp" | awk '
        /"assets": *\[/ { inassets = 1 }
        inassets && /"name": *"/ {
            line = $0
            sub(/.*"name": *"/, "", line); sub(/".*/, "", line)
            print line
        }'
    rm -f "$tmp"
    exit 0
fi

ASSET=${1:?usage: fetch_board.sh [--bootstrap|--list] <asset> [outfile]}
OUT=${2:-$ASSET}

[ -r "$CA_BUNDLE" ] || die "no CA bundle at $CA_BUNDLE -- run: sh $0 --bootstrap"

# A public release redirects github.com -> objects.githubusercontent.com, which
# https_get.sh follows.
sh "$HERE/https_get.sh" "$BASE/$ASSET" "$OUT" || die "could not fetch $ASSET"
case "$ASSET" in
    ai3_bench|*.sh) chmod +x "$OUT" ;;
esac
