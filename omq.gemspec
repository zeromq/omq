# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name     = "omq"
  s.version  = "0.1.0"
  s.authors  = ["Patrik Wenger"]
  s.email    = ["paddor@gmail.com"]
  s.summary  = "OMQ — pure Ruby ZeroMQ (ZMTP 3.1)"
  s.description = "Pure Ruby implementation of the ZMTP 3.1 wire protocol " \
                  "(ZeroMQ) using the Async gem. No native libraries required."
  s.homepage = "https://github.com/paddor/omq"
  s.license  = "ISC"

  s.required_ruby_version = ">= 3.3"

  s.files = Dir["lib/**/*.rb", "README.md", "LICENSE"]

  s.add_dependency "async", "~> 2"
end
