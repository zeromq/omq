#!/usr/bin/env bash
# Runs both halves of the MRI+OMQ vs JRuby+JeroMQ comparison sequentially.
#
# JRuby must be on PATH as `jruby`, or set JRUBY to a full path.

set -euo pipefail
cd "$(dirname "$0")/../../.."

JRUBY="${JRUBY:-jruby}"

echo
bundle exec ruby --yjit bench/scenarios/jeromq_vs_omq/omq.rb

echo
"$JRUBY" bench/scenarios/jeromq_vs_omq/jeromq.rb
