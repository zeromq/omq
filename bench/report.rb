# frozen_string_literal: true

# Benchmark regression report.
#
# Reads bench/results.jsonl and compares the last N runs,
# highlighting regressions and improvements.
#
# Usage:
#   ruby bench/report.rb                  # latest vs previous
#   ruby bench/report.rb --all            # show all measurements
#   ruby bench/report.rb --runs 5         # compare last 5 runs
#   ruby bench/report.rb --threshold 10   # 10% noise band
#   ruby bench/report.rb --pattern push_pull

require 'json'
require 'optparse'

RESULTS_PATH = File.join(__dir__, "results.jsonl")

options = { runs: 2, threshold: 5, all: false, pattern: nil }

OptionParser.new do |o|
  o.banner = "Usage: ruby bench/report.rb [options]"
  o.on("--runs N", Integer, "Number of runs to compare (default 2)")     { |v| options[:runs] = v }
  o.on("--threshold PCT", Float, "Noise band percentage (default 5)")    { |v| options[:threshold] = v }
  o.on("--all", "Show all measurements, not just outliers")              { options[:all] = true }
  o.on("--pattern NAME", "Filter to a specific pattern (e.g. push_pull)") { |v| options[:pattern] = v }
end.parse!

unless File.exist?(RESULTS_PATH)
  abort "No results file at #{RESULTS_PATH}. Run benchmarks first."
end

rows = File.readlines(RESULTS_PATH).map { |line| JSON.parse(line, symbolize_names: true) }
rows.select! { |r| r[:pattern] == options[:pattern] } if options[:pattern]

run_ids = rows.map { |r| r[:run_id] }.uniq.sort.last(options[:runs])

if run_ids.size < 2
  abort "Need at least 2 runs to compare. Found #{run_ids.size}."
end

# Group by measurement key
by_key = Hash.new { |h, k| h[k] = {} }
rows.each do |r|
  next unless run_ids.include?(r[:run_id])
  key = [r[:pattern], r[:transport], r[:peers], r[:msg_size]]
  by_key[key][r[:run_id]] = r
end

# ANSI helpers
RED   = "\e[31m"
GREEN = "\e[32m"
DIM   = "\e[2m"
BOLD  = "\e[1m"
RESET = "\e[0m"

def format_si(value)
  case
  when value >= 1e9  then "%.1fG"  % (value / 1e9)
  when value >= 1e6  then "%.1fM"  % (value / 1e6)
  when value >= 1e3  then "%.1fk"  % (value / 1e3)
  else                    "%.0f"   % value
  end
end

def format_mbps(value)
  case
  when value >= 1_000_000 then "%.1f TB/s" % (value / 1_000_000)
  when value >= 1_000     then "%.1f GB/s" % (value / 1_000)
  else                         "%.1f MB/s" % value
  end
end

def format_size(bytes)
  case
  when bytes >= 1024 then "#{bytes / 1024}KB"
  else                    "#{bytes}B"
  end
end

threshold    = options[:threshold]
prev_run     = run_ids[-2]
latest_run   = run_ids[-1]
regressions  = []
improvements = []
stable_count = 0

by_key.sort.each do |key, runs|
  prev   = runs[prev_run]
  latest = runs[latest_run]
  next unless prev && latest

  pattern, transport, peers, msg_size = key
  peer_label = "#{peers} peer#{'s' if peers > 1}"

  [:msgs_s, :mbps].each do |metric|
    old_val = prev[metric]
    new_val = latest[metric]
    next if old_val.zero?

    delta_pct = ((new_val - old_val) / old_val * 100).round(1)

    if delta_pct <= -threshold
      fmt_old = metric == :msgs_s ? format_si(old_val) : format_mbps(old_val)
      fmt_new = metric == :msgs_s ? format_si(new_val) : format_mbps(new_val)
      regressions << { pattern: pattern, transport: transport, peers: peer_label,
                       size: format_size(msg_size), metric: metric,
                       old: fmt_old, new: fmt_new, delta: delta_pct }
    elsif delta_pct >= threshold
      fmt_old = metric == :msgs_s ? format_si(old_val) : format_mbps(old_val)
      fmt_new = metric == :msgs_s ? format_si(new_val) : format_mbps(new_val)
      improvements << { pattern: pattern, transport: transport, peers: peer_label,
                        size: format_size(msg_size), metric: metric,
                        old: fmt_old, new: fmt_new, delta: delta_pct }
    else
      stable_count += 1
    end
  end
end

total = regressions.size + improvements.size + stable_count

puts "#{BOLD}=== OMQ Benchmark Report (#{latest_run} vs #{prev_run}) ===#{RESET}"
puts

if regressions.any?
  puts "#{RED}#{BOLD}REGRESSIONS (>#{threshold}%):#{RESET}"
  regressions.each do |r|
    printf "  %-15s %-8s %-9s %5s  %-6s  %10s → %-10s  #{RED}%+.1f%%#{RESET}\n",
           r[:pattern], r[:transport], r[:peers], r[:size], r[:metric], r[:old], r[:new], r[:delta]
  end
  puts
end

if improvements.any?
  puts "#{GREEN}#{BOLD}IMPROVEMENTS (>#{threshold}%):#{RESET}"
  improvements.each do |r|
    printf "  %-15s %-8s %-9s %5s  %-6s  %10s → %-10s  #{GREEN}%+.1f%%#{RESET}\n",
           r[:pattern], r[:transport], r[:peers], r[:size], r[:metric], r[:old], r[:new], r[:delta]
  end
  puts
end

if regressions.empty? && improvements.empty?
  puts "#{DIM}All #{total} measurements stable (±#{threshold}%)#{RESET}"
else
  puts "#{DIM}#{total} measurements total: #{regressions.size} regressions, #{improvements.size} improvements, #{stable_count} stable (±#{threshold}%)#{RESET}"
end

# --all: full table grouped by pattern
if options[:all]
  puts
  puts "#{BOLD}=== Full Results ===#{RESET}"

  by_key.sort.each do |key, runs|
    pattern, transport, peers, msg_size = key
    peer_label = "#{peers} peer#{'s' if peers > 1}"

    header_values = run_ids.map { |id| id[0..9] }
    printf "\n  %-15s %-8s %-9s %5s", pattern, transport, peer_label, format_size(msg_size)

    [:msgs_s, :mbps].each do |metric|
      values = run_ids.map { |id| runs[id]&.fetch(metric, nil) }
      fmt    = metric == :msgs_s ? method(:format_si) : method(:format_mbps)

      printf "  %-6s", metric
      values.each { |v| printf "  %10s", v ? fmt.(v) : "--" }

      if values.compact.size >= 2
        old_val = values[-2]
        new_val = values[-1]
        if old_val && new_val && !old_val.zero?
          delta = ((new_val - old_val) / old_val * 100).round(1)
          color = delta <= -threshold ? RED : delta >= threshold ? GREEN : DIM
          printf "  #{color}%+.1f%%#{RESET}", delta
        end
      end
    end
    puts
  end
  puts
end
