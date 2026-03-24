# frozen_string_literal: true

module OMQ
  module ZMTP
    # Pure Ruby socket options, replacing ZsockOptions.
    #
    # All timeouts are in seconds (Numeric) or nil (no timeout).
    # HWM values are integers.
    #
    class Options
      DEFAULT_HWM = 1000

      # @param linger [Integer] linger period in seconds (default 0)
      #
      def initialize(linger: 0)
        @send_hwm              = DEFAULT_HWM
        @recv_hwm              = DEFAULT_HWM
        @linger                = linger
        @identity              = "".b
        @router_mandatory      = false
        @read_timeout          = nil   # seconds, nil = no timeout
        @write_timeout         = nil
        @reconnect_interval    = 0.1   # seconds, or Range for backoff (e.g. 0.1..5.0)
        @heartbeat_interval    = nil   # seconds, nil = disabled
        @heartbeat_ttl         = nil   # seconds, nil = use heartbeat_interval
        @heartbeat_timeout     = nil   # seconds, nil = use heartbeat_interval
        @tcp_keepalive         = nil   # nil = OS default, true/false = enable/disable
        @tcp_keepalive_idle    = nil   # seconds until first probe, nil = OS default
        @tcp_keepalive_count   = nil   # probes before dead, nil = OS default
        @tcp_keepalive_interval = nil  # seconds between probes, nil = OS default
        @max_message_size       = nil  # bytes, nil = unlimited
      end

      attr_accessor :send_hwm,  :recv_hwm,
                    :linger,    :identity,
                    :router_mandatory,
                    :read_timeout,          :write_timeout,
                    :reconnect_interval,
                    :heartbeat_interval,    :heartbeat_ttl,    :heartbeat_timeout,
                    :tcp_keepalive,         :tcp_keepalive_idle,
                    :tcp_keepalive_count,   :tcp_keepalive_interval,
                    :max_message_size

      alias_method :router_mandatory?, :router_mandatory
      alias_method :recv_timeout,      :read_timeout
      alias_method :recv_timeout=,     :read_timeout=
      alias_method :send_timeout,      :write_timeout
      alias_method :send_timeout=,     :write_timeout=
    end
  end
end
