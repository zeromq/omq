# frozen_string_literal: true

# REQ/REP synchronous roundtrip throughput.

require_relative "../bench_helper"

BenchHelper.run("REQ/REP", dir: __dir__, peer_counts: [1]) do |transport, ep, peers, payload, n|
  Async do |task|
    rep = OMQ::REP.new
    BenchHelper.apply_security(rep, transport, role: :server)
    rep.bind(ep)
    ep = BenchHelper.resolve_endpoint(transport, rep)

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
      BenchHelper.measure_roundtrip(req, responder, payload, n)
    ensure
      responder.stop
      req.close
      rep.close
    end
  end.wait
end
