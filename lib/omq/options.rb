# frozen_string_literal: true

module OMQ
  # Pure Ruby socket options.
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
      @max_message_size      = nil  # bytes, nil = unlimited
      @conflate              = false
      @mechanism             = Protocol::ZMTP::Mechanism::Null.new
    end

    attr_accessor :send_hwm,  :recv_hwm,
                  :linger,    :identity,
                  :router_mandatory,  :conflate,
                  :read_timeout,          :write_timeout,
                  :reconnect_interval,
                  :heartbeat_interval,    :heartbeat_ttl,    :heartbeat_timeout,
                  :max_message_size,
                  :mechanism

    alias_method :router_mandatory?, :router_mandatory
    alias_method :recv_timeout,      :read_timeout
    alias_method :recv_timeout=,     :read_timeout=
    alias_method :send_timeout,      :write_timeout
    alias_method :send_timeout=,     :write_timeout=
  end
end
