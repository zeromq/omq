# frozen_string_literal: true

# PUB/SUB fan-out throughput.
# PUB sends N messages, each SUB receives all N.
# msgs/s = publish rate.

require_relative "../bench_helper"

BenchHelper.run("PUB/SUB", dir: __dir__, peer_counts: [3]) do |transport, ep, peers, payload|
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

  burst = ->(k) {
    send_barrier = Async::Barrier.new
    send_barrier.async { k.times { pub << payload } }
    recv_barrier = Async::Barrier.new
    subs.each { |sub| recv_barrier.async { k.times { sub.receive } } }
    recv_barrier.wait
    send_barrier.wait
  }

  begin
    BenchHelper.measure_best_of(payload, &burst)
  ensure
    subs.each(&:close)
    pub.close
  end
end
