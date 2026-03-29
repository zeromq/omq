# frozen_string_literal: true

module OMQ
  module CLI
    Endpoint = Data.define(:url, :bind?) do
      def connect? = !bind?
    end


    Config = Data.define(
      :type_name,
      :endpoints,
      :connects,
      :binds,
      :data,
      :file,
      :format,
      :subscribes,
      :joins,
      :group,
      :identity,
      :target,
      :interval,
      :count,
      :delay,
      :timeout,
      :linger,
      :conflate,
      :compress,
      :expr,
      :transient,
      :verbose,
      :quiet,
      :echo,
      :curve_server,
      :curve_server_key,
      :has_msgpack,
      :has_zstd,
      :stdin_is_tty,
    ) do
      SEND_ONLY = %w[pub push scatter radio].freeze
      RECV_ONLY = %w[sub pull gather dish].freeze

      def send_only? = SEND_ONLY.include?(type_name)
      def recv_only? = RECV_ONLY.include?(type_name)
    end
  end
end
