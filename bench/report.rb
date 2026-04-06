# frozen_string_literal: true

# Benchmark regression report.
#
# Reads bench/results.jsonl and compares the last N runs,
# highlighting regressions and improvements.
#
# Usage:
#   ruby bench/report.rb                  # latest vs previous
#   ruby bench/report.rb --all            # show all measurements
#   ruby bench/report.rb --runs 5         # compare latest vs oldest-of-5
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
RED    = "\e[31m"
GREEN  = "\e[32m"
YELLOW = "\e[33m"
DIM    = "\e[2m"
BOLD   = "\e[1m"
RESET  = "\e[0m"

def format_si(value)
  case
  when value >= 1e9
    "%.1fG"  % (value / 1e9)
  when value >= 1e6
    "%.1fM"  % (value / 1e6)
  when value >= 1e3
    "%.1fk"  % (value / 1e3)
  else                    "%.0f"   % value
  end
end

def format_mbps(value)
  case
  when value >= 1_000_000
    "%.1f TB/s" % (value / 1_000_000)
  when value >= 1_000
    "%.1f GB/s" % (value / 1_000)
  else                         "%.1f MB/s" % value
  end
end

def format_size(bytes)
  case
  when bytes >= 1024
    "#{bytes / 1024}KB"
  else                    "#{bytes}B"
  end
end

threshold    = options[:threshold]
base_run     = run_ids.first   # oldest of the window
latest_run   = run_ids.last
regressions  = []
improvements = []
trends       = []
stable_count = 0

by_key.sort.each do |key, runs|
  base   = runs[base_run]
  latest = runs[latest_run]
  next unless base && latest

  pattern, transport, peers, msg_size = key
  peer_label = "#{peers} peer#{'s' if peers > 1}"

  [:msgs_s, :mbps].each do |metric|
    old_val = base[metric]
    new_val = latest[metric]
    next if old_val.nil? || old_val.zero?

    fmt     = metric == :msgs_s ? method(:format_si) : method(:format_mbps)
    delta   = ((new_val - old_val) / old_val * 100).round(1)
    row     = { pattern: pattern, transport: transport, peers: peer_label,
                size: format_size(msg_size), metric: metric,
                old: fmt.(old_val), new: fmt.(new_val), delta: delta }

    if delta <= -threshold
      regressions << row
    elsif delta >= threshold
      improvements << row
    else
      # Check for monotonic trend across all N runs (requires 3+ runs)
      values = run_ids.map { |id| runs[id]&.fetch(metric, nil) }.compact
      if values.size >= 3
        declining  = values.each_cons(2).all? { |a, b| b < a }
        increasing = values.each_cons(2).all? { |a, b| b > a }
        if declining || increasing
          direction = declining ? :down : :up
          trends << row.merge(direction: direction, runs: values.size)
        else
          stable_count += 1
        end
      else
        stable_count += 1
      end
    end
  end
end

total = regressions.size + improvements.size + trends.size + stable_count

span_label = run_ids.size == 2 ? "#{latest_run} vs #{base_run}" :
             "#{latest_run} vs #{base_run} (#{run_ids.size} runs)"
puts "#{BOLD}=== OMQ Benchmark Report (#{span_label}) ===#{RESET}"
puts

if regressions.any?
  puts "#{RED}#{BOLD}REGRESSIONS (>#{threshold}% vs oldest):#{RESET}"
  regressions.each do |r|
    printf "  %-15s %-8s %-9s %5s  %-6s  %10s → %-10s  #{RED}%+.1f%%#{RESET}\n",
           r[:pattern], r[:transport], r[:peers], r[:size], r[:metric], r[:old], r[:new], r[:delta]
  end
  puts
end

if improvements.any?
  puts "#{GREEN}#{BOLD}IMPROVEMENTS (>#{threshold}% vs oldest):#{RESET}"
  improvements.each do |r|
    printf "  %-15s %-8s %-9s %5s  %-6s  %10s → %-10s  #{GREEN}%+.1f%%#{RESET}\n",
           r[:pattern], r[:transport], r[:peers], r[:size], r[:metric], r[:old], r[:new], r[:delta]
  end
  puts
end

if trends.any?
  puts "#{YELLOW}#{BOLD}TRENDS (monotonic across #{run_ids.size} runs, within ±#{threshold}%):#{RESET}"
  trends.each do |r|
    arrow = r[:direction] == :down ? "↓" : "↑"
    printf "  %-15s %-8s %-9s %5s  %-6s  %10s → %-10s  #{YELLOW}%s %+.1f%%#{RESET}\n",
           r[:pattern], r[:transport], r[:peers], r[:size], r[:metric], r[:old], r[:new], arrow, r[:delta]
  end
  puts
end

if regressions.empty? && improvements.empty? && trends.empty?
  puts "#{DIM}All #{total} measurements stable (±#{threshold}%)#{RESET}"
else
  puts "#{DIM}#{total} measurements total: #{regressions.size} regressions, " \
       "#{improvements.size} improvements, #{trends.size} trends, #{stable_count} stable (±#{threshold}%)#{RESET}"
end

# --all: full table grouped by pattern
if options[:all]
  puts
  puts "#{BOLD}=== Full Results ===#{RESET}"

  by_key.sort.each do |key, runs|
    pattern, transport, peers, msg_size = key
    peer_label = "#{peers} peer#{'s' if peers > 1}"

    printf "\n  %-15s %-8s %-9s %5s", pattern, transport, peer_label, format_size(msg_size)

    [:msgs_s, :mbps].each do |metric|
      values = run_ids.map { |id| runs[id]&.fetch(metric, nil) }
      fmt    = metric == :msgs_s ? method(:format_si) : method(:format_mbps)

      printf "  %-6s", metric
      values.each { |v| printf "  %10s", v ? fmt.(v) : "--" }

      base_val   = values.first
      latest_val = values.last
      if base_val && latest_val && !base_val.zero?
        delta = ((latest_val - base_val) / base_val * 100).round(1)
        color = delta <= -threshold ? RED : delta >= threshold ? GREEN : DIM
        printf "  #{color}%+.1f%%#{RESET}", delta
      end
    end
  end
  puts
  puts
end
