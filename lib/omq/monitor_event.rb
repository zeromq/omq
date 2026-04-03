# frozen_string_literal: true

module OMQ
  # Lifecycle event emitted by {Socket#monitor}.
  #
  # @!attribute [r] type
  #   @return [Symbol] event type (:listening, :connected, :disconnected, etc.)
  # @!attribute [r] endpoint
  #   @return [String, nil] the endpoint involved
  # @!attribute [r] detail
  #   @return [Hash, nil] extra context (e.g. { error: }, { interval: }, etc.)
  #
  MonitorEvent = Data.define(:type, :endpoint, :detail) do
    def initialize(type:, endpoint: nil, detail: nil) = super
  end
end
