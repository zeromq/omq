# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "minitest"
gem "rake"
gem "benchmark-ips"

if ENV["OMQ_DEV"]
  gem "cztop",     require: false
  gem "zstd-ruby", require: false
  gem "omq-curve", require: false, path: '../omq-curve'
end
