# frozen_string_literal: true

# PAIR exclusive 1-to-1 throughput.

require_relative "../bench_helper"

BenchHelper.run("PAIR", dir: __dir__, peer_counts: [1]) do |transport, ep, _peers, payload, n|
  receiver = OMQ::PAIR.new
  BenchHelper.apply_security(receiver, transport, role: :server)
  receiver.bind(ep)
  ep = BenchHelper.resolve_endpoint(transport, receiver)

  sender = OMQ::PAIR.new
  BenchHelper.apply_security(sender, transport, role: :client)
  sender.connect(ep)
  BenchHelper.wait_connected(sender) unless transport == "inproc"

  begin
    BenchHelper.measure(receiver, [sender], payload, n)
  ensure
    sender.close
    receiver.close
  end
end
