# frozen_string_literal: true

require 'unicode_plot'

module OMQ
  module Bench
    module Plot
      GROUPS = {
        "inproc"                  => %w[inproc],
        "ipc + tcp + tls + curve" => %w[ipc tcp tls curve],
      }.freeze

      LABEL_BULLETS = %w[▪ ▫ ▴ ▾ ◆].freeze

      module_function

      # results: { "inproc" => { 1 => [{size:, mbps:, msgs_s:}, ...], 3 => [...] }, ... }
      def render_all(results, sizes:)
        text = +""

        [1, 3].each do |peers|
          label = peers == 1 ? "1 peer" : "#{peers} peers"

          GROUPS.each do |group_name, transports|
            text << render_plot(results, peers, sizes, transports: transports,
                                metric:   :msgs_s,
                                title:    "msgs/s  #{group_name}  (#{label})",
                                ylabel:   "log msgs/s",
                                y_format: method(:format_si))
            text << render_plot(results, peers, sizes, transports: transports,
                                metric:   :mbps,
                                title:    "throughput  #{group_name}  (#{label})",
                                ylabel:   "log",
                                y_format: method(:format_mbps))
          end
        end

        text
      end

      def render_plot(results, peers, sizes, transports:, metric:, title:, ylabel:, y_format:)
        x = sizes.map { |s| Math.log2(s) }

        # Compute Y range from all transports before creating the plot.
        all_ys = transports.flat_map { |t| results.dig(t, peers)&.map { |r| r[metric] } || [] }
        return +"" if all_ys.empty?

        y_min   = all_ys.min
        y_max   = all_ys.max
        log_min = Math.log10(y_min).floor
        log_max = Math.log10(y_max).ceil

        plot   = nil
        series = [] # [{name:, last_log_y:, marker:}, ...]

        transports.each_with_index do |transport, i|
          points = results.dig(transport, peers)
          next unless points&.any?

          raw_ys = points.map { |r| r[metric] }
          log_ys = raw_ys.map { |v| Math.log10(v) }

          if plot.nil?
            plot = UnicodePlot.lineplot(x, log_ys,
                                        title:  title,
                                        xlabel: size_axis(sizes),
                                        ylabel: ylabel,
                                        ylim:   [log_min, log_max],
                                        width:  60,
                                        height: 15)
          else
            UnicodePlot.lineplot!(plot, x, log_ys)
          end

          series << { name: transport, min: raw_ys.min, max: raw_ys.max,
                      max_log_y: log_ys.max, last_log_y: log_ys.last,
                      bullet: LABEL_BULLETS[i] || "▪" }
        end

        return +"" unless plot
        n_rows  = plot.n_rows

        # Label each decade on the Y axis
        (log_min..log_max).each do |decade|
          fraction = (decade - log_min).to_f / (log_max - log_min)
          row      = n_rows - 1 - (fraction * (n_rows - 1)).round
          plot.annotate_row!(:l, row, y_format.(10**decade))
        end

        # Label each series at its peak row with min/max values.
        # Nudge labels apart when lines peak at the same row.
        used_rows = {}
        series.each do |s|
          fraction = (s[:max_log_y] - log_min) / (log_max - log_min)
          row      = n_rows - 1 - (fraction * (n_rows - 1)).round
          row      = row.clamp(0, n_rows - 1)
          row -= 1 while row >= 0 && used_rows[row]
          row = row.clamp(0, n_rows - 1)
          used_rows[row] = true
          plot.annotate_row!(:r, row, "#{s[:bullet]} #{s[:name]} min=#{y_format.(s[:min])} max=#{y_format.(s[:max])}")
        end

        # X axis: message size range
        plot.annotate!(:bl, format_size(sizes.first))
        plot.annotate!(:br, format_size(sizes.last))

        puts
        plot.render($stdout)
        puts

        # Return plain text (no ANSI colors) for file output
        sio = StringIO.new
        sio.puts
        plot.render(sio, color: false)
        sio.puts
        sio.string
      end

      def size_axis(sizes)
        sizes.map { |s| format_size(s) }.join("   ")
      end

      def format_size(bytes)
        case
        when bytes >= 1_073_741_824 then "#{bytes / 1_073_741_824}GB"
        when bytes >= 1_048_576     then "#{bytes / 1_048_576}MB"
        when bytes >= 1024          then "#{bytes / 1024}KB"
        else                             "#{bytes}B"
        end
      end

      def format_si(value)
        case
        when value >= 1e12 then "%.0fT"  % (value / 1e12)
        when value >= 1e9  then "%.0fG"  % (value / 1e9)
        when value >= 1e6  then "%.1fM"  % (value / 1e6)
        when value >= 1e3  then "%.0fk"  % (value / 1e3)
        else                    "%.0f"   % value
        end
      end

      def format_mbps(value)
        case
        when value >= 1_000_000 then "%.0f TB/s" % (value / 1_000_000)
        when value >= 1_000     then "%.0f GB/s" % (value / 1_000)
        else                         "%.0f MB/s" % value
        end
      end
    end
  end
end
