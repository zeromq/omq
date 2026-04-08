# frozen_string_literal: true

# PUB/SUB fan-out throughput.
# PUB sends N messages, each SUB receives all N.
# msgs/s = publish rate.

require_relative "../bench_helper"

BenchHelper.run("PUB/SUB", dir: __dir__, peer_counts: [3]) do |transport, ep, peers, payload, n|
  pub = OMQ::PUB.new
  BenchHelper.apply_security(pub, transport, role: :server)
  pub.bind(ep)
  ep = BenchHelper.resolve_endpoint(transport, pub)

  subs = peers.times.map do
    sub = OMQ::SUB.new(subscribe: "")
    BenchHelper.apply_security(sub, transport, role: :client)
    sub.connect(ep)
    sub
  end
  BenchHelper.wait_connected(subs) unless transport == "inproc"
  BenchHelper.wait_subscribed(pub, subs)

  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  send_barrier = Async::Barrier.new
  send_barrier.async { n.times { pub << payload } }

  # Each sub must receive all N messages
  recv_barrier = Async::Barrier.new
  subs.each { |sub| recv_barrier.async { n.times { sub.receive } } }
  recv_barrier.wait
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  send_barrier.wait

  begin
    BenchHelper.report(payload.bytesize, n, elapsed)
  ensure
    subs.each(&:close)
    pub.close
  end
end
