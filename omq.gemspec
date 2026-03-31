# frozen_string_literal: true

require_relative "lib/omq/version"

Gem::Specification.new do |s|
  s.name     = "omq"
  s.version  = OMQ::VERSION
  s.authors  = ["Patrik Wenger"]
  s.email    = ["paddor@gmail.com"]
  s.summary  = "Pure Ruby ZMQ library + CLI"
  s.description = "Pure Ruby implementation of the ZMTP 3.1 wire protocol " \
                  "(ZeroMQ) with all socket types (REQ/REP, PUB/SUB, PUSH/PULL, " \
                  "DEALER/ROUTER, and draft types) and TCP/IPC/inproc transports. " \
                  "Includes an `omq` CLI for composable message pipelines — " \
                  "pipe, filter, and transform across processes with Ruby eval, " \
                  "multiple formats (JSON, msgpack, marshal), Ractor parallelism, " \
                  "and compression. No native libraries required."
  s.homepage = "https://github.com/zeromq/omq"
  s.license  = "ISC"

  s.required_ruby_version = ">= 3.3"

  s.files      = Dir["lib/**/*.rb", "exe/*", "README.md", "LICENSE", "CHANGELOG.md"]
  s.bindir     = "exe"
  s.executables = ["omq"]

  s.add_dependency "protocol-zmtp"
  s.add_dependency "async", "~> 2.38"
  s.add_dependency "io-stream", "~> 0.11"
end
