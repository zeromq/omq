# frozen_string_literal: true

# Run all pattern benchmarks sequentially, appending results to bench/results.jsonl.

ENV["OMQ_BENCH_RUN_ID"] = Time.now.strftime("%Y-%m-%dT%H:%M:%S")

%w[push_pull pub_sub req_rep router_dealer dealer_dealer pair].each do |pattern|
  system("ruby", "--yjit", File.join(__dir__, pattern, "omq.rb")) || abort("#{pattern} failed")
end
