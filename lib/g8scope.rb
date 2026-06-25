# frozen_string_literal: true

require "g8scope/version"
require "g8scope/config"
require "g8scope/scrubber"
require "g8scope/envelope"
require "g8scope/transport"
require "g8scope/client"

# g8scope runtime Ruby SDK.
#
# Builds the language-neutral g8scope error envelope from a Ruby Exception,
# scrubs PII, and ships it to the ingest API. The SDK must never raise into the
# host application.
module G8Scope
end
