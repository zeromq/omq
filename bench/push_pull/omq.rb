# frozen_string_literal: true

# PUSH/PULL sustained pipeline throughput.

require_relative "../bench_helper"

BenchHelper.run("PUSH/PULL", dir: __dir__, peer_counts: [1, 3]) do |transport, ep, peers, payload|
  pull = OMQ::PULL.new
  BenchHelper.apply_security(pull, transport, role: :server)
  pull.bind(ep)
  ep = BenchHelper.resolve_endpoint(transport, pull)

  pushes = peers.times.map do
    push = OMQ::PUSH.new
    BenchHelper.apply_security(push, transport, role: :client)
    push.connect(ep)
    push
  end
  BenchHelper.wait_connected(pushes) unless transport == "inproc"

  begin
    BenchHelper.measure(pull, pushes, payload)
  ensure
    pushes.each(&:close)
    pull.close
  end
end
