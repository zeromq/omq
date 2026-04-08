# frozen_string_literal: true

# ROUTER/DEALER throughput: DEALER sends, ROUTER receives.

require_relative "../bench_helper"

BenchHelper.run("ROUTER/DEALER", dir: __dir__, peer_counts: [3]) do |transport, ep, peers, payload|
  router = OMQ::ROUTER.new
  BenchHelper.apply_security(router, transport, role: :server)
  router.bind(ep)
  ep = BenchHelper.resolve_endpoint(transport, router)

  dealers = peers.times.map do |i|
    d = OMQ::DEALER.new
    d.identity = "d#{i}"
    BenchHelper.apply_security(d, transport, role: :client)
    d.connect(ep)
    d
  end
  BenchHelper.wait_connected(dealers) unless transport == "inproc"

  burst = ->(k) {
    per = [k / dealers.size, 1].max
    barrier = Async::Barrier.new
    dealers.each { |d| barrier.async { per.times { d << payload } } }
    (per * dealers.size).times { router.receive }
    barrier.wait
  }

  begin
    BenchHelper.measure_best_of(payload, align: dealers.size, &burst)
  ensure
    dealers.each(&:close)
    router.close
  end
end
