# frozen_string_literal: true

module OMQ
  module ZMTP
    # Valid socket type peer combinations per ZMTP spec.
    #
    VALID_PEERS = {
      PAIR:   %i[PAIR],
      REQ:    %i[REP ROUTER],
      REP:    %i[REQ DEALER],
      DEALER: %i[REP DEALER ROUTER],
      ROUTER: %i[REQ DEALER ROUTER],
      PUB:    %i[SUB XSUB],
      SUB:    %i[PUB XPUB],
      XPUB:   %i[SUB XSUB],
      XSUB:   %i[PUB XPUB],
      PUSH:   %i[PULL],
      PULL:   %i[PUSH],
    }.freeze
  end
end
