#!/bin/sh
#
# System tests for omq. Run from the repo root:
#   sh test/cli/system_test.sh
#

set -eu

TMPDIR=$(mktemp -d)
export OMQ_DEV=1
OMQ="ruby -Ilib exe/omq"
T="-t 1"  # default timeout for all commands
PASS=0
FAIL=0

STDERR_LOG="$TMPDIR/stderr.log"
> "$STDERR_LOG"
echo "stderr log: $TMPDIR/stderr.log"

cleanup() {
	if [ $? -eq 0 ]
	then
		rm -rf "$TMPDIR"
	else
		cat $TMPDIR/stderr.log >&2
	fi
}

trap cleanup EXIT

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() {
  echo "  FAIL: $1 — expected: '$2', got: '$3'"
  if [ -s "$STDERR_LOG" ]; then
    echo "        stderr: $(cat "$STDERR_LOG")"
  fi
  FAIL=$((FAIL + 1))
}

check() {
  name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$name"
  else
    fail "$name" "$expected" "$actual"
  fi
  > "$STDERR_LOG"  # reset for next test
}

# Unique IPC name per test (abstract namespace, no file cleanup)
S=0
ipc() {
	S=$((S + 1))
	echo "ipc://@omq_test_${$}_${S}"
}

echo "=== omq system tests ==="
echo

# ── REQ/REP ─────────────────────────────────────────────────────────

echo "REQ/REP:"
U=$(ipc)
$OMQ rep -b $U -D "PONG" -n 1 $T > $TMPDIR/rep_out.txt 2>>"$STDERR_LOG" &
REQ_OUT=$(echo hello | $OMQ req -c $U -n 1 $T 2>>"$STDERR_LOG")
wait
check "req receives reply" "PONG" "$REQ_OUT"
check "rep receives request" "hello" "$(cat $TMPDIR/rep_out.txt)"

# ── REP echo mode ───────────────────────────────────────────────────

echo "REP echo:"
U=$(ipc)
$OMQ rep -b $U --echo -n 1 $T > /dev/null 2>&1 &
REQ_OUT=$(echo 'echo me' | $OMQ req -c $U -n 1 $T 2>>"$STDERR_LOG")
wait
check "rep --echo echoes back" "echo me" "$REQ_OUT"

# ── PUSH/PULL ───────────────────────────────────────────────────────

echo "PUSH/PULL:"
U=$(ipc)
$OMQ pull -b $U -n 1 $T > $TMPDIR/pull_out.txt 2>>"$STDERR_LOG" &
echo task-1 | $OMQ push -c $U $T 2>>"$STDERR_LOG"
wait
check "pull receives message" "task-1" "$(cat $TMPDIR/pull_out.txt)"

# ── PUB/SUB ─────────────────────────────────────────────────────────

echo "PUB/SUB:"
U=$(ipc)
$OMQ sub -b $U -s "weather." -n 1 $T > $TMPDIR/sub_out.txt 2>>"$STDERR_LOG" &
$OMQ pub -c $U -E '"weather.nyc 72F"' $T 2>>"$STDERR_LOG"
wait
check "sub receives matching message" "weather.nyc 72F" "$(cat $TMPDIR/sub_out.txt)"

# ── Multipart (tabs) ────────────────────────────────────────────────

echo "Multipart:"
U=$(ipc)
$OMQ pull -b $U -n 1 $T > $TMPDIR/multi_out.txt 2>>"$STDERR_LOG" &
printf 'frame1\tframe2\tframe3' | $OMQ push -c $U $T 2>>"$STDERR_LOG"
wait
check "multipart via tabs" "frame1	frame2	frame3" "$(cat $TMPDIR/multi_out.txt)"

# ── JSONL format ────────────────────────────────────────────────────

echo "JSONL:"
U=$(ipc)
$OMQ pull -b $U -n 1 -J $T > $TMPDIR/jsonl_out.txt 2>>"$STDERR_LOG" &
echo '["part1","part2"]' | $OMQ push -c $U -J $T 2>>"$STDERR_LOG"
wait
check "jsonl round-trip" '["part1","part2"]' "$(cat $TMPDIR/jsonl_out.txt)"

# ── PUB/SUB eval to JSONL ──────────────────────────────────────────

echo "PUB/SUB eval JSONL:"
U=$(ipc)
$OMQ sub -b $U -J -n 1 $T > $TMPDIR/pubsub_jsonl_out.txt 2>>"$STDERR_LOG" &
$OMQ pub -c $U -E '%w(foo bar)' $T 2>>"$STDERR_LOG"
wait
check "pub -E array received as jsonl" '["foo","bar"]' "$(cat $TMPDIR/pubsub_jsonl_out.txt)"

echo "PUB/SUB eval pipe:"
U=$(ipc)
$OMQ sub -b $U -e '$F.first' -J -n 1 $T > $TMPDIR/pubsub_evalpipe_out.txt 2>>"$STDERR_LOG" &
$OMQ pub -c $U -E '%w(foo bar)' $T 2>>"$STDERR_LOG"
wait
check "pub -E to sub -e extracts first part" '["foo"]' "$(cat $TMPDIR/pubsub_evalpipe_out.txt)"

# ── Empty line handling ─────────────────────────────────────────────

echo "Empty lines:"
U=$(ipc)
$OMQ pull -b $U -n 1 $T > $TMPDIR/empty_out.txt 2>>"$STDERR_LOG" &
printf '\nhello\n' | $OMQ push -c $U $T 2>>"$STDERR_LOG"
wait
check "empty lines are skipped" "hello" "$(cat $TMPDIR/empty_out.txt)"

# ── IPC abstract namespace ──────────────────────────────────────────

echo "IPC abstract namespace:"
U=$(ipc)
$OMQ pull -b $U -n 1 $T > $TMPDIR/abstract_out.txt 2>>"$STDERR_LOG" &
echo 'abstract' | $OMQ push -c $U $T 2>>"$STDERR_LOG"
wait
check "ipc abstract namespace works" "abstract" "$(cat $TMPDIR/abstract_out.txt)"

# ── Ruby eval (-e) ──────────────────────────────────────────────────

echo "Ruby eval:"
U=$(ipc)
$OMQ rep -b $U -e '$F.map(&:upcase)' -n 1 $T > /dev/null 2>&1 &
EVAL_OUT=$(echo 'hello' | $OMQ req -c $U -n 1 $T 2>>"$STDERR_LOG")
wait
check "rep -e upcases reply" "HELLO" "$EVAL_OUT"

# ── Ruby eval nil (REP sends empty reply) ───────────────────────────

echo "Ruby eval nil:"
U=$(ipc)
$OMQ rep -b $U -e 'nil' -n 1 $T > /dev/null 2>&1 &
EVAL_NIL_OUT=$(echo 'anything' | $OMQ req -c $U -n 1 $T 2>>"$STDERR_LOG")
wait
check "rep -e nil sends empty reply" "" "$EVAL_NIL_OUT"

# ── Ruby eval on send side ──────────────────────────────────────────

echo "Ruby eval on send:"
U=$(ipc)
$OMQ pull -b $U -n 1 $T > $TMPDIR/eval_send_out.txt 2>>"$STDERR_LOG" &
echo 'hello' | $OMQ push -c $U -E '$F.map(&:upcase)' $T 2>>"$STDERR_LOG"
wait
check "push -E transforms before send" "HELLO" "$(cat $TMPDIR/eval_send_out.txt)"

# ── Ruby eval filter (nil skips) ────────────────────────────────────

echo "Ruby eval filter:"
U=$(ipc)
$OMQ pull -b $U -n 1 $T > $TMPDIR/eval_filter_out.txt 2>>"$STDERR_LOG" &
printf 'skip\nkeep\n' | $OMQ push -c $U -E '$F.first == "skip" ? nil : $F' $T 2>>"$STDERR_LOG"
wait
check "push -E nil skips message" "keep" "$(cat $TMPDIR/eval_filter_out.txt)"

# ── Quoted format ───────────────────────────────────────────────────

echo "Quoted format:"
U=$(ipc)
$OMQ pull -b $U -n 1 -Q $T > $TMPDIR/quoted_out.txt 2>>"$STDERR_LOG" &
printf 'hello\001world' | $OMQ push -c $U --raw $T 2>>"$STDERR_LOG"
wait
check "quoted format escapes non-printable" 'hello\x01world' "$(cat $TMPDIR/quoted_out.txt)"

# ── File input (-F) ────────────────────────────────────────────────

echo "File input:"
U=$(ipc)
echo "from file" > $TMPDIR/omq_file_input.txt
$OMQ pull -b $U -n 1 $T > $TMPDIR/file_out.txt 2>>"$STDERR_LOG" &
$OMQ push -c $U -F $TMPDIR/omq_file_input.txt $T 2>>"$STDERR_LOG"
wait
check "-F reads from file" "from file" "$(cat $TMPDIR/file_out.txt)"

# ── Compression (-z) ───────────────────────────────────────────────

if ruby -e 'require "zstd-ruby"' 2>>"$STDERR_LOG"; then
  echo "Compression:"
  U=$(ipc)
  PAYLOAD=$(ruby -e "puts 'x' * 200")
  $OMQ pull -b $U -n 1 -z $T > $TMPDIR/compress_out.txt 2>>"$STDERR_LOG" &
  echo "$PAYLOAD" | $OMQ push -c $U -z $T 2>>"$STDERR_LOG"
  wait
  check "compression round-trip" "$PAYLOAD" "$(cat $TMPDIR/compress_out.txt)"

  echo "Compression (small):"
  U=$(ipc)
  $OMQ pull -b $U -n 1 -z $T > $TMPDIR/compress_small_out.txt 2>>"$STDERR_LOG" &
  echo 'tiny' | $OMQ push -c $U -z $T 2>>"$STDERR_LOG"
  wait
  check "compression round-trip (small)" "tiny" "$(cat $TMPDIR/compress_small_out.txt)"
else
  echo "Compression: skipped (zstd-ruby not installed)"
fi

# ── Interval sending (-i) ──────────────────────────────────────────

echo "Interval:"
U=$(ipc)
$OMQ pull -b $U -n 3 $T > $TMPDIR/interval_out.txt 2>>"$STDERR_LOG" &
$OMQ push -c $U -D "tick" -i 0.1 -n 3 $T 2>>"$STDERR_LOG"
wait
check "interval sends N messages" "3" "$(wc -l < $TMPDIR/interval_out.txt | tr -d ' ')"

# ── Interval with -e (no data/file) ────────────────────────────────

echo "Interval with eval:"
U=$(ipc)
$OMQ pull -b $U -n 3 $T > $TMPDIR/interval_eval_out.txt 2>>"$STDERR_LOG" &
$OMQ push -c $U -E '"tick"' -i 0.1 -n 3 $T 2>>"$STDERR_LOG"
wait
check "interval -E generates messages without input" "3" "$(wc -l < $TMPDIR/interval_eval_out.txt | tr -d ' ')"

# ── Eval sets $_ ───────────────────────────────────────────────────

echo "Eval \$_:"
U=$(ipc)
$OMQ pull -b $U -n 1 $T > $TMPDIR/eval_line_out.txt 2>>"$STDERR_LOG" &
echo "hello" | $OMQ push -c $U -E '$_.upcase' $T 2>>"$STDERR_LOG"
wait
check "-E sets \$_ to first frame" "HELLO" "$(cat $TMPDIR/eval_line_out.txt)"

# ── Eval nil skips output ──────────────────────────────────────────

echo "Eval nil output:"
U=$(ipc)
$OMQ pull -b $U -n 1 $T > $TMPDIR/eval_nil_out.txt 2>>"$STDERR_LOG" &
printf 'skip\nkeep\n' | $OMQ push -c $U -E '$F.first == "skip" ? nil : $F' $T 2>>"$STDERR_LOG"
wait
check "-E nil produces no output" "1" "$(wc -l < $TMPDIR/eval_nil_out.txt | tr -d ' ')"

# ── Interval quantized timing ─────────────────────────────────────

echo "Interval timing:"
U=$(ipc)
$OMQ pull -b $U -n 3 $T > /dev/null 2>&1 &
START=$(date +%s%N)
$OMQ push -c $U -D "tick" -i 0.2 -n 3 $T 2>>"$STDERR_LOG"
END=$(date +%s%N)
wait
ELAPSED_MS=$(( (END - START) / 1000000 ))
# 3 messages at 0.2s interval: ~0.6s total, allow 300–1500ms
if [ "$ELAPSED_MS" -ge 300 ] && [ "$ELAPSED_MS" -le 1500 ]; then
  TIMING_OK="yes"
else
  TIMING_OK="no (${ELAPSED_MS}ms)"
fi
check "quantized interval keeps cadence" "yes" "$TIMING_OK"

# ── DEALER with --identity ──────────────────────────────────────────

echo "DEALER/ROUTER:"
U=$(ipc)
$OMQ router -b $U -n 1 $T > $TMPDIR/router_out.txt 2>>"$STDERR_LOG" &
$OMQ dealer -c $U --identity worker-1 -D "hi from dealer" -d 0.3 $T 2>>"$STDERR_LOG"
wait
ROUTER_OUT=$(cat $TMPDIR/router_out.txt)
if echo "$ROUTER_OUT" | grep -q "worker-1" && echo "$ROUTER_OUT" | grep -q "hi from dealer"; then
  pass "router sees dealer identity + message"
else
  fail "router sees dealer identity + message" "worker-1<TAB>hi from dealer" "$ROUTER_OUT"
fi

# ── ROUTER sending with --target ─────────────────────────────────────

echo "ROUTER --target:"
U=$(ipc)
$OMQ dealer -c $U --identity "d1" -n 1 $T > $TMPDIR/dealer_recv.txt 2>>"$STDERR_LOG" &
$OMQ router -b $U --target "d1" -D "routed reply" -d 0.3 $T 2>>"$STDERR_LOG" || true
wait
# DEALER receives ["", "routed reply"] — empty delimiter + payload
check "router --target routes to dealer" "	routed reply" "$(cat $TMPDIR/dealer_recv.txt)"

# ── TCP transport ───────────────────────────────────────────────────

echo "TCP transport:"
$OMQ pull -b tcp://127.0.0.1:17199 -n 1 $T > $TMPDIR/tcp_out.txt 2>>"$STDERR_LOG" &
echo "tcp works" | $OMQ push -c tcp://127.0.0.1:17199 $T 2>>"$STDERR_LOG"
wait
check "tcp transport" "tcp works" "$(cat $TMPDIR/tcp_out.txt)"

# ── IPC filesystem transport ───────────────────────────────────────

echo "IPC filesystem:"
IPC_PATH="$TMPDIR/omq_test.sock"
$OMQ pull -b "ipc://$IPC_PATH" -n 1 $T > $TMPDIR/ipc_fs_out.txt 2>>"$STDERR_LOG" &
echo "ipc works" | $OMQ push -c "ipc://$IPC_PATH" $T 2>>"$STDERR_LOG"
wait
check "ipc filesystem transport" "ipc works" "$(cat $TMPDIR/ipc_fs_out.txt)"

# ── CURVE encryption ────────────────────────────────────────────────

if ruby -Ilib -e 'require "omq/curve"' 2>>"$STDERR_LOG"; then
  echo "CURVE encryption:"
  U=$(ipc)
  CURVE_KEYS=$(ruby -Ilib -e 'require "omq/curve"; k = RbNaCl::PrivateKey.generate; puts OMQ::Z85.encode(k.public_key.to_s); puts OMQ::Z85.encode(k.to_s)')
  CURVE_PUB=$(echo "$CURVE_KEYS" | head -1)
  CURVE_SEC=$(echo "$CURVE_KEYS" | tail -1)

  # REP
  OMQ_SERVER_PUBLIC="$CURVE_PUB" OMQ_SERVER_SECRET="$CURVE_SEC" \
    $OMQ rep -b $U -D "secret" -n 1 -t 3 > $TMPDIR/curve_rep_out.txt 2>>"$STDERR_LOG" &

  # REQ
  OMQ_SERVER_KEY="$CURVE_PUB" \
    $OMQ req -c $U -D "classified" -n 1 -t 3 > $TMPDIR/curve_req_out.txt 2>>"$STDERR_LOG"
  wait

  check "curve req receives encrypted reply" "secret" "$(cat $TMPDIR/curve_req_out.txt)"
  check "curve rep receives encrypted request" "classified" "$(cat $TMPDIR/curve_rep_out.txt)"
else
  echo "CURVE: skipped (omq-curve not installed)"
fi

# ── Script-based OMQ.incoming ─────────────────────────────────────

echo "Script OMQ.incoming:"
cat > $TMPDIR/recv_script.rb <<'RUBY'
OMQ.incoming { |msg| msg.map(&:upcase) }
RUBY
U=$(ipc)
$OMQ pull -b $U -r $TMPDIR/recv_script.rb -n 1 $T > $TMPDIR/script_recv_out.txt 2>>"$STDERR_LOG" &
echo 'hello' | $OMQ push -c $U $T 2>>"$STDERR_LOG"
wait
check "script OMQ.incoming transforms incoming" "HELLO" "$(cat $TMPDIR/script_recv_out.txt)"

# ── Script-based OMQ.outgoing ─────────────────────────────────────

echo "Script OMQ.outgoing:"
cat > $TMPDIR/send_script.rb <<'RUBY'
OMQ.outgoing { $F.map(&:upcase) }
RUBY
U=$(ipc)
$OMQ pull -b $U -n 1 $T > $TMPDIR/script_send_out.txt 2>>"$STDERR_LOG" &
echo 'hello' | $OMQ push -c $U -r $TMPDIR/send_script.rb $T 2>>"$STDERR_LOG"
wait
check "script OMQ.outgoing transforms outgoing" "HELLO" "$(cat $TMPDIR/script_send_out.txt)"

# ── Script with both OMQ.outgoing and OMQ.incoming on REQ ───────────

echo "Script both directions on REQ:"
cat > $TMPDIR/both_script.rb <<'RUBY'
OMQ.outgoing { |msg| msg.map(&:upcase) }
OMQ.incoming { |first_part, *| first_part.reverse }
RUBY
U=$(ipc)
$OMQ rep -b $U --echo -n 1 $T > /dev/null 2>&1 &
REQ_BOTH_OUT=$(echo 'hello' | $OMQ req -c $U -r $TMPDIR/both_script.rb -n 1 $T 2>>"$STDERR_LOG")
wait
# outgoing upcases "hello" → "HELLO", rep echoes, incoming reverses → "OLLEH"
check "script send+recv on REQ" "OLLEH" "$REQ_BOTH_OUT"

# ── Script with at_exit ─────────────────────────────────────────────

echo "Script at_exit:"
cat > $TMPDIR/atexit_script.rb <<RUBY
marker = "$TMPDIR/atexit_marker.txt"
OMQ.incoming { |msg| msg.map(&:upcase) }
at_exit { File.write(marker, "cleanup_ran") }
RUBY
U=$(ipc)
$OMQ pull -b $U -r $TMPDIR/atexit_script.rb -n 1 $T > /dev/null 2>>"$STDERR_LOG" &
echo 'hello' | $OMQ push -c $U $T 2>>"$STDERR_LOG"
wait
check "script at_exit runs on exit" "cleanup_ran" "$(cat $TMPDIR/atexit_marker.txt 2>/dev/null)"

# ── Script with closure state ───────────────────────────────────────

echo "Script closure state:"
cat > $TMPDIR/closure_script.rb <<'RUBY'
count = 0

OMQ.incoming do
  count += 1
  "msg_#{count}"
end
RUBY
U=$(ipc)
$OMQ pull -b $U -r $TMPDIR/closure_script.rb -n 3 $T > $TMPDIR/closure_out.txt 2>>"$STDERR_LOG" &
printf 'a\nb\nc\n' | $OMQ push -c $U $T 2>>"$STDERR_LOG"
wait
check "script closure increments across messages" "msg_3" "$(tail -1 $TMPDIR/closure_out.txt)"

# ── Script OMQ.outgoing + CLI -E override ───────────────────────────

echo "Script + CLI override:"
cat > $TMPDIR/override_script.rb <<'RUBY'
OMQ.outgoing { raise "should not be called" }
OMQ.incoming { |msg| msg.map(&:downcase) }
RUBY
U=$(ipc)
$OMQ rep -b $U --echo -n 1 $T > /dev/null 2>&1 &
OVERRIDE_OUT=$(echo 'Hello' | $OMQ req -c $U -r $TMPDIR/override_script.rb -E '$F.map(&:upcase)' -n 1 $T 2>>"$STDERR_LOG")
wait
# CLI -E overrides script outgoing: upcases → "HELLO", rep echoes, script incoming downcases → "hello"
check "CLI -E overrides script OMQ.outgoing" "hello" "$OVERRIDE_OUT"

# ── Script at_exit with closure teardown ────────────────────────────

echo "Script at_exit teardown:"
TEARDOWN_LOG="$TMPDIR/teardown_log.txt"
cat > $TMPDIR/teardown_script.rb <<RUBY
log = []
OMQ.incoming { |parts| log << parts.first; parts }
at_exit { File.write("$TEARDOWN_LOG", log.join(",")) }
RUBY
U=$(ipc)
$OMQ pull -b $U -r $TMPDIR/teardown_script.rb -n 3 $T > /dev/null 2>>"$STDERR_LOG" &
printf 'a\nb\nc\n' | $OMQ push -c $U $T 2>>"$STDERR_LOG"
wait
check "at_exit sees accumulated closure state" "a,b,c" "$(cat $TMPDIR/teardown_log.txt 2>/dev/null)"

# ── Validation: -e on send-only socket errors ───────────────────────

echo "Validation:"
$OMQ push -c tcp://x:1 -e '$F' 2>$TMPDIR/val_err.txt && EXITCODE=0 || EXITCODE=$?
check "-e on send-only socket errors" "1" "$EXITCODE"

$OMQ pull -b tcp://:1 -E '$F' 2>$TMPDIR/val_err2.txt && EXITCODE=0 || EXITCODE=$?
check "-E on recv-only socket errors" "1" "$EXITCODE"

$OMQ router -c tcp://x:1 -E '$F' --target peer1 2>$TMPDIR/val_err3.txt && EXITCODE=0 || EXITCODE=$?
check "-E + --target errors" "1" "$EXITCODE"

# ── REQ: -E transforms outgoing, -e transforms reply ───────────────

echo "REQ -E and -e:"
U=$(ipc)
$OMQ rep -b $U --echo -n 1 $T > /dev/null 2>&1 &
REQ_SPLIT_OUT=$(echo 'hello' | $OMQ req -c $U -E '$F.map(&:upcase)' -e '$F.map(&:reverse)' -n 1 $T 2>>"$STDERR_LOG")
wait
# -E upcases "hello" → "HELLO", rep echoes "HELLO", -e reverses → "OLLEH"
check "req -E sends transformed, -e transforms reply" "OLLEH" "$REQ_SPLIT_OUT"

# ── Pipe with -e (recv-eval) ───────────────────────────────────────

echo "Pipe -e:"
$OMQ push -b ipc://@omq_pipe_in_$$ -D "piped" -d 0.5 -t 3 2>>"$STDERR_LOG" &
$OMQ pull -b ipc://@omq_pipe_out_$$ -n 1 -t 3 > $TMPDIR/pipe_e_out.txt 2>>"$STDERR_LOG" &
$OMQ pipe -c ipc://@omq_pipe_in_$$ -c ipc://@omq_pipe_out_$$ -e '$F.map(&:upcase)' -n 1 -t 3 2>>"$STDERR_LOG" &
wait
check "pipe -e transforms in pipeline" "PIPED" "$(cat $TMPDIR/pipe_e_out.txt)"

# ── Pipe fan-in (--in with multiple sources) ──────────────────────

echo "Pipe fan-in:"
$OMQ push -b ipc://@omq_fanin_a_$$ -D "from_a" -d 0.5 -t 3 2>>"$STDERR_LOG" &
$OMQ push -b ipc://@omq_fanin_b_$$ -D "from_b" -d 0.5 -t 3 2>>"$STDERR_LOG" &
$OMQ pull -b ipc://@omq_fanin_out_$$ -n 2 -t 3 > $TMPDIR/fanin_out.txt 2>>"$STDERR_LOG" &
$OMQ pipe --in -c ipc://@omq_fanin_a_$$ -c ipc://@omq_fanin_b_$$ \
         --out -c ipc://@omq_fanin_out_$$ -e '$F.map(&:upcase)' -n 2 -t 3 2>>"$STDERR_LOG" &
wait
FANIN_LINES=$(wc -l < $TMPDIR/fanin_out.txt | tr -d ' ')
FANIN_CONTENT=$(sort $TMPDIR/fanin_out.txt | tr '\n' ',')
check "pipe fan-in receives from both sources" "2" "$FANIN_LINES"
check "pipe fan-in content" "FROM_A,FROM_B," "$FANIN_CONTENT"

# ── Pipe fan-out (--out with multiple sinks) ─────────────────────

echo "Pipe fan-out:"
$OMQ pull -b ipc://@omq_fanout_a_$$ -n 1 -t 3 > $TMPDIR/fanout_a.txt 2>>"$STDERR_LOG" &
$OMQ pull -b ipc://@omq_fanout_b_$$ -n 1 -t 3 > $TMPDIR/fanout_b.txt 2>>"$STDERR_LOG" &
$OMQ pipe --in -b ipc://@omq_fanout_in_$$ \
         --out -c ipc://@omq_fanout_a_$$ -c ipc://@omq_fanout_b_$$ \
         -e '$F.map(&:upcase)' -n 2 -t 3 2>>"$STDERR_LOG" &
sleep 0.3
printf 'msg1\nmsg2\n' | $OMQ push -c ipc://@omq_fanout_in_$$ -t 3 2>>"$STDERR_LOG"
wait
FANOUT_A=$(cat $TMPDIR/fanout_a.txt 2>/dev/null)
FANOUT_B=$(cat $TMPDIR/fanout_b.txt 2>/dev/null)
# PUSH round-robins: each sink should get exactly 1 message
if [ -n "$FANOUT_A" ] && [ -n "$FANOUT_B" ]; then
  pass "pipe fan-out distributes to both sinks"
else
  fail "pipe fan-out distributes to both sinks" "both non-empty" "a='$FANOUT_A' b='$FANOUT_B'"
fi

# ── Pipe --in/--out validation ───────────────────────────────────

echo "Pipe validation:"
$OMQ pipe --in -c tcp://x:1 2>$TMPDIR/val_pipe1.txt && EXITCODE=0 || EXITCODE=$?
check "pipe --in without --out errors" "1" "$EXITCODE"

$OMQ pipe --out -c tcp://x:1 2>$TMPDIR/val_pipe2.txt && EXITCODE=0 || EXITCODE=$?
check "pipe --out without --in errors" "1" "$EXITCODE"

$OMQ req --in -c tcp://x:1 --out -c tcp://x:2 2>$TMPDIR/val_pipe3.txt && EXITCODE=0 || EXITCODE=$?
check "--in/--out on non-pipe errors" "1" "$EXITCODE"

# ── Summary ─────────────────────────────────────────────────────────

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
