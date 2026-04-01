#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== Latency ==="
ruby -Ilib bench/latency.rb
echo
echo "=== Throughput ==="
ruby -Ilib bench/throughput.rb
echo
echo "=== Pipeline MB/s ==="
ruby -Ilib bench/pipeline_mbps.rb
