# frozen_string_literal: true

# ROUTER/DEALER throughput: DEALER sends, ROUTER receives.

require_relative "../bench_helper"

BenchHelper.run("ROUTER/DEALER", dir: __dir__, peer_counts: [3]) do |transport, ep, peers, payload, n|
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

  per_dealer = n / dealers.size

  # Warm up
  100.times do
    dealers.first << payload
    router.receive
  end

  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  barrier = Async::Barrier.new
  dealers.each do |d|
    barrier.async { per_dealer.times { d << payload } }
  end

  (per_dealer * dealers.size).times { router.receive }
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  barrier.wait

  begin
    BenchHelper.report(payload.bytesize, n, elapsed)
  ensure
    dealers.each(&:close)
    router.close
  end
end
