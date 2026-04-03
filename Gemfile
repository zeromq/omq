# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "minitest"
gem "rake"
gem "localhost"

# CURVE tests use Nuckle (pure Ruby, no libsodium).
# Cross-backend interop tests also use rbnacl when available.
gem "nuckle",        path: ENV["OMQ_DEV"] ? "../nuckle" : nil
gem "protocol-zmtp", path: ENV["OMQ_DEV"] ? "../protocol-zmtp" : nil

if ENV["OMQ_DEV"]
  gem "benchmark-ips"
  gem "rbnacl", "~> 7.0"
  gem "omq-ffi",  require: false, path: "../omq-ffi"
end
