#!/usr/bin/env bash
# Interop test: MRI+OMQ ↔ JRuby+JeroMQ across PUSH/PULL, REQ/REP, PUB/SUB.
#
# For each pattern, runs both directions:
#   OMQ binds, JeroMQ connects
#   JeroMQ binds, OMQ connects
#
# Exits 0 if all six combinations succeed.

set -o pipefail
cd "$(dirname "$0")/../../../.."

JRUBY="${JRUBY:-/home/roadster/.rubies/jruby-10.0.5.0/bin/jruby}"
DIR="bench/scenarios/jeromq_vs_omq/interop"

source /usr/local/share/chruby/chruby.sh
chruby ruby-4.0.2

run_omq()    { timeout 15 env OMQ_DEV=1 bundle exec ruby --yjit "$DIR/omq_side.rb"    "$@"; }
run_jeromq() { timeout 15 "$JRUBY" "$DIR/jeromq_side.rb" "$@"; }

port() { echo $((20000 + RANDOM % 20000)); }

pass=0
fail=0

pair() {
  local label="$1" pattern="$2" binder_cmd="$3" connector_cmd="$4"
  local p; p=$(port)
  local ep="tcp://127.0.0.1:$p"
  echo "--- $label ---"
  $binder_cmd "$pattern" bind "$ep" &
  local bpid=$!
  sleep 0.4
  if $connector_cmd "$pattern" connect "$ep"; then
    wait $bpid && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: binder exit"; }
  else
    fail=$((fail+1))
    echo "FAIL: connector exit"
    kill $bpid 2>/dev/null
    wait $bpid 2>/dev/null
  fi
  echo
}

for pat in push_pull req_rep pub_sub; do
  pair "$pat: OMQ binds, JeroMQ connects" "$pat" run_omq    run_jeromq
  pair "$pat: JeroMQ binds, OMQ connects" "$pat" run_jeromq run_omq
done

echo "=================================="
echo "passed: $pass / $((pass+fail))"
[ $fail -eq 0 ]
