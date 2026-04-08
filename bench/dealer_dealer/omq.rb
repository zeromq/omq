# frozen_string_literal: true

# DEALER/DEALER async bidirectional throughput.
# One DEALER binds, N DEALERs connect and send. Binder receives.

require_relative "../bench_helper"

BenchHelper.run("DEALER/DEALER", dir: __dir__, peer_counts: [1]) do |transport, ep, peers, payload|
  receiver = OMQ::DEALER.new
  BenchHelper.apply_security(receiver, transport, role: :server)
  receiver.bind(ep)
  ep = BenchHelper.resolve_endpoint(transport, receiver)

  senders = peers.times.map do
    s = OMQ::DEALER.new
    BenchHelper.apply_security(s, transport, role: :client)
    s.connect(ep)
    s
  end
  BenchHelper.wait_connected(senders) unless transport == "inproc"

  begin
    BenchHelper.measure(receiver, senders, payload)
  ensure
    senders.each(&:close)
    receiver.close
  end
end
