# frozen_string_literal: true

# REQ/REP synchronous roundtrip throughput.

require_relative "../bench_helper"

BenchHelper.run("REQ/REP", dir: __dir__, peer_counts: [1]) do |transport, ep, peers, payload|
  Async do |task|
    rep = OMQ::REP.new
    BenchHelper.apply_security(rep, transport, role: :server)
    uri = rep.bind(ep)
    ep = BenchHelper.resolve_endpoint(transport, ep, uri)

    req = OMQ::REQ.new
    BenchHelper.apply_security(req, transport, role: :client)
    req.connect(ep)

    responder = task.async do
      loop do
        msg = rep.receive
        rep << msg
      end
    end

    begin
      BenchHelper.measure_roundtrip(req, responder, payload)
    ensure
      responder.stop
      req.close
      rep.close
    end
  end.wait
end
