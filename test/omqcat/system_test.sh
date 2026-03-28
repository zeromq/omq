#!/bin/sh
#
# System tests for omqcat. Run from the repo root:
#   sh test/omqcat/system_test.sh
#
# Escape bundler's gem isolation so subprocesses see all installed gems.
unset BUNDLE_GEMFILE BUNDLE_BIN_PATH BUNDLE_LOCKFILE BUNDLER_SETUP BUNDLER_VERSION RUBYOPT RUBYLIB 2>/dev/null || true

set -u

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

OMQCAT="ruby exe/omqcat"
PASS=0
FAIL=0
PORT=17100

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1 — expected: '$2', got: '$3'"; FAIL=$((FAIL + 1)); }

check() {
  name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$name"
  else
    fail "$name" "$expected" "$actual"
  fi
}

next_port() { PORT=$((PORT + 1)); echo $PORT; }

run_bg() { timeout 5 "$@" & }

echo "=== omqcat system tests ==="
echo

# ── REQ/REP ─────────────────────────────────────────────────────────

echo "REQ/REP:"
P=$(next_port)
run_bg $OMQCAT rep -b tcp://:$P -D "PONG" -n 1 > $TMPDIR/rep_out.txt 2>/dev/null
sleep 0.5
REQ_OUT=$(timeout 5 sh -c "echo hello | $OMQCAT req -c tcp://localhost:$P -d 0.3 -n 1 2>/dev/null")
wait 2>/dev/null
REP_OUT=$(cat $TMPDIR/rep_out.txt)
check "req receives reply" "PONG" "$REQ_OUT"
check "rep receives request" "hello" "$REP_OUT"

# ── REP echo mode ───────────────────────────────────────────────────

echo "REP echo:"
P=$(next_port)
run_bg $OMQCAT rep -b tcp://:$P --echo -n 1 > $TMPDIR/rep_echo_out.txt 2>/dev/null
sleep 0.5
REQ_OUT=$(timeout 5 sh -c "echo 'echo me' | $OMQCAT req -c tcp://localhost:$P -d 0.3 -n 1 2>/dev/null")
wait 2>/dev/null
check "rep --echo echoes back" "echo me" "$REQ_OUT"

# ── PUSH/PULL ───────────────────────────────────────────────────────

echo "PUSH/PULL:"
P=$(next_port)
run_bg $OMQCAT pull -b tcp://:$P -n 1 > $TMPDIR/pull_out.txt 2>/dev/null
sleep 0.5
timeout 5 sh -c "echo task-1 | $OMQCAT push -c tcp://localhost:$P 2>/dev/null"
wait 2>/dev/null
PULL_OUT=$(cat $TMPDIR/pull_out.txt)
check "pull receives message" "task-1" "$PULL_OUT"

# ── PUB/SUB ─────────────────────────────────────────────────────────

echo "PUB/SUB:"
P=$(next_port)
run_bg $OMQCAT sub -b tcp://:$P -s "weather." -n 1 > $TMPDIR/sub_out.txt 2>/dev/null
sleep 0.5
timeout 5 sh -c "echo 'weather.nyc 72F' | $OMQCAT pub -c tcp://localhost:$P -d 0.3 2>/dev/null"
wait 2>/dev/null
SUB_OUT=$(cat $TMPDIR/sub_out.txt)
check "sub receives matching message" "weather.nyc 72F" "$SUB_OUT"

# ── Multipart (tabs) ────────────────────────────────────────────────

echo "Multipart:"
P=$(next_port)
run_bg $OMQCAT pull -b tcp://:$P -n 1 > $TMPDIR/multi_out.txt 2>/dev/null
sleep 0.5
timeout 5 sh -c "printf 'frame1\tframe2\tframe3' | $OMQCAT push -c tcp://localhost:$P 2>/dev/null"
wait 2>/dev/null
MULTI_OUT=$(cat $TMPDIR/multi_out.txt)
check "multipart via tabs" "frame1	frame2	frame3" "$MULTI_OUT"

# ── JSONL format ────────────────────────────────────────────────────

echo "JSONL:"
P=$(next_port)
run_bg $OMQCAT pull -b tcp://:$P -n 1 -J > $TMPDIR/jsonl_out.txt 2>/dev/null
sleep 0.5
timeout 5 sh -c "echo '[\"part1\",\"part2\"]' | $OMQCAT push -c tcp://localhost:$P -J 2>/dev/null"
wait 2>/dev/null
JSONL_OUT=$(cat $TMPDIR/jsonl_out.txt)
check "jsonl round-trip" '["part1","part2"]' "$JSONL_OUT"

# ── Empty line handling ─────────────────────────────────────────────

echo "Empty lines:"
P=$(next_port)
run_bg $OMQCAT pull -b tcp://:$P -n 1 > $TMPDIR/empty_out.txt 2>/dev/null
sleep 0.5
timeout 5 sh -c "printf '\nhello\n' | $OMQCAT push -c tcp://localhost:$P 2>/dev/null"
wait 2>/dev/null
EMPTY_OUT=$(cat $TMPDIR/empty_out.txt)
check "empty lines are skipped" "hello" "$EMPTY_OUT"

# ── URL normalization ───────────────────────────────────────────────

echo "URL normalization:"
P=$(next_port)
run_bg $OMQCAT pull -b tcp://:$P -n 1 > $TMPDIR/norm_out.txt 2>/dev/null
sleep 0.5
timeout 5 sh -c "echo 'normalized' | $OMQCAT push -c tcp://localhost:$P 2>/dev/null"
wait 2>/dev/null
NORM_OUT=$(cat $TMPDIR/norm_out.txt)
check "tcp://:port works" "normalized" "$NORM_OUT"

# ── IPC abstract namespace ──────────────────────────────────────────

echo "IPC abstract namespace:"
run_bg $OMQCAT pull -b "ipc://@omqcat_test_$$" -n 1 > $TMPDIR/abstract_out.txt 2>/dev/null
sleep 0.5
timeout 5 sh -c "echo 'abstract' | $OMQCAT push -c 'ipc://@omqcat_test_$$' 2>/dev/null"
wait 2>/dev/null
ABSTRACT_OUT=$(cat $TMPDIR/abstract_out.txt)
check "ipc abstract namespace works" "abstract" "$ABSTRACT_OUT"

# ── Ruby eval (-e) ──────────────────────────────────────────────────

echo "Ruby eval:"
P=$(next_port)
run_bg $OMQCAT rep -b tcp://:$P -e '$F.map(&:upcase)' -n 1 > /dev/null 2>&1
sleep 0.5
EVAL_OUT=$(timeout 5 sh -c "echo 'hello' | $OMQCAT req -c tcp://localhost:$P -d 0.3 -n 1 2>/dev/null")
wait 2>/dev/null
check "rep -e upcases reply" "HELLO" "$EVAL_OUT"

# ── Ruby eval nil (REP sends empty reply) ───────────────────────────

echo "Ruby eval nil:"
P=$(next_port)
run_bg $OMQCAT rep -b tcp://:$P -e 'nil' -n 1 > /dev/null 2>&1
sleep 0.5
EVAL_NIL_OUT=$(timeout 5 sh -c "echo 'anything' | $OMQCAT req -c tcp://localhost:$P -d 0.3 -n 1 2>/dev/null")
wait 2>/dev/null
check "rep -e nil sends empty reply" "" "$EVAL_NIL_OUT"

# ── Ruby eval on send side ──────────────────────────────────────────

echo "Ruby eval on send:"
P=$(next_port)
run_bg $OMQCAT pull -b tcp://:$P -n 1 > $TMPDIR/eval_send_out.txt 2>/dev/null
sleep 0.5
timeout 5 sh -c "echo 'hello' | $OMQCAT push -c tcp://localhost:$P -e '\$F.map(&:upcase)' 2>/dev/null"
wait 2>/dev/null
EVAL_SEND_OUT=$(cat $TMPDIR/eval_send_out.txt)
check "push -e transforms before send" "HELLO" "$EVAL_SEND_OUT"

# ── Ruby eval filter (nil skips) ────────────────────────────────────

echo "Ruby eval filter:"
P=$(next_port)
run_bg $OMQCAT pull -b tcp://:$P -n 1 > $TMPDIR/eval_filter_out.txt 2>/dev/null
sleep 0.5
timeout 5 sh -c "printf 'skip\nkeep\n' | $OMQCAT push -c tcp://localhost:$P -e '\$F.first == \"skip\" ? nil : \$F' 2>/dev/null"
wait 2>/dev/null
EVAL_FILTER_OUT=$(cat $TMPDIR/eval_filter_out.txt)
check "push -e nil skips message" "keep" "$EVAL_FILTER_OUT"

# ── Quoted format ───────────────────────────────────────────────────

echo "Quoted format:"
P=$(next_port)
run_bg $OMQCAT pull -b tcp://:$P -n 1 -Q > $TMPDIR/quoted_out.txt 2>/dev/null
sleep 0.5
# Send binary data via raw format, receive with quoted format
printf 'hello\001world' | timeout 5 $OMQCAT push -c tcp://localhost:$P --raw 2>/dev/null
wait 2>/dev/null
QUOTED_OUT=$(cat $TMPDIR/quoted_out.txt)
check "quoted format escapes non-printable" 'hello\x01world' "$QUOTED_OUT"

# ── File input (-F) ────────────────────────────────────────────────

echo "File input:"
P=$(next_port)
echo "from file" > $TMPDIR/omqcat_file_input.txt
run_bg $OMQCAT pull -b tcp://:$P -n 1 > $TMPDIR/file_out.txt 2>/dev/null
sleep 0.5
timeout 5 $OMQCAT push -c tcp://localhost:$P -F $TMPDIR/omqcat_file_input.txt 2>/dev/null
wait 2>/dev/null
FILE_OUT=$(cat $TMPDIR/file_out.txt)
check "-F reads from file" "from file" "$FILE_OUT"

# ── Compression (-z) ───────────────────────────────────────────────

if ruby -e 'require "zstd-ruby"' 2>/dev/null; then
  echo "Compression:"
  P=$(next_port)
  PAYLOAD=$(ruby -e "puts 'x' * 200")
  run_bg $OMQCAT pull -b tcp://:$P -n 1 -z > $TMPDIR/compress_out.txt 2>/dev/null
  sleep 0.5
  timeout 5 sh -c "echo '$PAYLOAD' | $OMQCAT push -c tcp://localhost:$P -z 2>/dev/null"
  wait 2>/dev/null
  COMPRESS_OUT=$(cat $TMPDIR/compress_out.txt)
  check "compression round-trip" "$PAYLOAD" "$COMPRESS_OUT"

  echo "Compression (small):"
  P=$(next_port)
  run_bg $OMQCAT pull -b tcp://:$P -n 1 -z > $TMPDIR/compress_small_out.txt 2>/dev/null
  sleep 0.5
  timeout 5 sh -c "echo 'tiny' | $OMQCAT push -c tcp://localhost:$P -z 2>/dev/null"
  wait 2>/dev/null
  COMPRESS_SMALL_OUT=$(cat $TMPDIR/compress_small_out.txt)
  check "compression round-trip (small)" "tiny" "$COMPRESS_SMALL_OUT"
else
  echo "Compression: skipped (zstd-ruby not installed)"
fi

# ── Interval sending (-i) ──────────────────────────────────────────

echo "Interval:"
P=$(next_port)
run_bg $OMQCAT pull -b tcp://:$P -n 3 > $TMPDIR/interval_out.txt 2>/dev/null
sleep 0.5
timeout 5 $OMQCAT push -c tcp://localhost:$P -D "tick" -i 0.1 -n 3 2>/dev/null
wait 2>/dev/null
INTERVAL_COUNT=$(wc -l < $TMPDIR/interval_out.txt | tr -d ' ')
check "interval sends N messages" "3" "$INTERVAL_COUNT"

# ── DEALER with --identity ──────────────────────────────────────────

echo "DEALER/ROUTER:"
P=$(next_port)
run_bg $OMQCAT router -b tcp://:$P -n 1 -t 3 > $TMPDIR/router_out.txt 2>/dev/null
sleep 0.5
timeout 5 $OMQCAT dealer -c tcp://localhost:$P --identity worker-1 -D "hi from dealer" -d 1 -n 1 2>/dev/null
sleep 0.5
wait 2>/dev/null
ROUTER_OUT=$(cat $TMPDIR/router_out.txt)
if echo "$ROUTER_OUT" | grep -q "worker-1" && echo "$ROUTER_OUT" | grep -q "hi from dealer"; then
  pass "router sees dealer identity + message"
else
  fail "router sees dealer identity + message" "worker-1<TAB>hi from dealer" "$ROUTER_OUT"
fi

# ── ROUTER sending with --target ─────────────────────────────────────

echo "ROUTER --target:"
P=$(next_port)
run_bg $OMQCAT dealer -c tcp://localhost:$P --identity "d1" -n 1 > $TMPDIR/dealer_recv.txt 2>/dev/null
sleep 0.3
run_bg $OMQCAT router -b tcp://:$P --target "d1" -D "routed reply" -n 1 -d 1 2>/dev/null
sleep 2
wait 2>/dev/null
DEALER_RECV=$(cat $TMPDIR/dealer_recv.txt)
# DEALER receives ["", "routed reply"] — empty delimiter + payload
check "router --target routes to dealer" "	routed reply" "$DEALER_RECV"

# ── CURVE encryption ────────────────────────────────────────────────

if ruby -Ilib -e 'require "omq/curve"' 2>/dev/null; then
  echo "CURVE encryption:"
  P=$(next_port)
  CURVE_KEYS=$(ruby -Ilib -e 'require "omq/curve"; k = RbNaCl::PrivateKey.generate; puts OMQ::Z85.encode(k.public_key.to_s); puts OMQ::Z85.encode(k.to_s)')
  CURVE_PUB=$(echo "$CURVE_KEYS" | head -1)
  CURVE_SEC=$(echo "$CURVE_KEYS" | tail -1)

  OMQ_SERVER_PUBLIC=$CURVE_PUB OMQ_SERVER_SECRET=$CURVE_SEC \
    run_bg $OMQCAT rep -b tcp://:$P -D "secret" -n 1 > $TMPDIR/curve_rep_out.txt 2>/dev/null
  sleep 0.5
  CURVE_REQ_OUT=$(OMQ_SERVER_KEY=$CURVE_PUB \
    timeout 5 $OMQCAT req -c tcp://localhost:$P -D "classified" -d 0.5 -n 1 2>/dev/null)
  wait 2>/dev/null
  CURVE_REP_OUT=$(cat $TMPDIR/curve_rep_out.txt)
  check "curve req receives encrypted reply" "secret" "$CURVE_REQ_OUT"
  check "curve rep receives encrypted request" "classified" "$CURVE_REP_OUT"
else
  echo "CURVE: skipped (omq-curve not installed)"
fi

# ── Summary ─────────────────────────────────────────────────────────

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
