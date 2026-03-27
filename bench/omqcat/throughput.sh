#!/bin/sh
#
# omqcat throughput benchmark (PUSH/PULL)
#
# Usage: sh bench/omqcat/throughput.sh [count]
#
set -u

OMQCAT="ruby --yjit -Ilib exe/omqcat"
N=${1:-10000}
PORT=18100

echo "omqcat throughput benchmark — $N messages"
echo

for transport in tcp ipc; do
  if [ "$transport" = "tcp" ]; then
    ADDR="tcp://:$PORT"
    CONN="tcp://localhost:$PORT"
    PORT=$((PORT + 1))
  else
    ADDR="ipc://@omqcat_bench_tp_$$"
    CONN="$ADDR"
  fi

  # Start receiver
  $OMQCAT pull -b "$ADDR" -n $N -q 2>/dev/null &
  PULL_PID=$!
  sleep 0.5

  # Generate N messages and pipe through push
  START=$(ruby -e 'puts Process.clock_gettime(Process::CLOCK_MONOTONIC)')
  seq $N | $OMQCAT push -c "$CONN" 2>/dev/null
  wait $PULL_PID 2>/dev/null
  END=$(ruby -e 'puts Process.clock_gettime(Process::CLOCK_MONOTONIC)')

  ELAPSED=$(ruby -e "puts ($END - $START).round(3)")
  RATE=$(ruby -e "puts ($N.to_f / ($END - $START)).round(0)")

  echo "  $transport: ${RATE} msg/s (${N} messages in ${ELAPSED}s)"
done
