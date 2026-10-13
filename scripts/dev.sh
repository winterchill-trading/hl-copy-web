#!/usr/bin/env bash
# Builds the app, assembles _site/ (index.html, main.js, the dev/ fixtures) and serves it.
#
#   scripts/dev.sh [-p PORT] [-r]     -r builds with the release profile (small main.js)
#
# Open http://localhost:PORT/ for mock data, or http://localhost:PORT/?api=<url> to talk
# to a running hl-copy-api (it must allow this origin with CORS).
set -euo pipefail

port=8000
profile=dev
while getopts "p:r" opt; do
  case $opt in
    p) port=$OPTARG ;;
    r) profile=release ;;
    *) exit 2 ;;
  esac
done

root=$(cd "$(dirname "$0")/.." && pwd)
build_dir=${DUNE_BUILD_DIR:-$root/_build}
cd "$root"
opam exec -- dune build --root . --profile "$profile" ./bin/main.bc.js

site=$root/_site
rm -rf "$site"
mkdir -p "$site"
cp static/index.html "$site/"
cp "$build_dir/default/bin/main.bc.js" "$site/main.js"
cp -R dev "$site/dev"
chmod -R u+w "$site"
echo "serving $site on http://localhost:$port/"
exec python3 -m http.server "$port" --bind 127.0.0.1 --directory "$site"
