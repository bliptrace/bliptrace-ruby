# frozen_string_literal: true

require "bliptrace/version"
require "bliptrace/config"
require "bliptrace/retry_policy"
require "bliptrace/scrubber"
require "bliptrace/envelope"
require "bliptrace/transport"
require "bliptrace/client"

# Bliptrace runtime Ruby SDK.
#
# Builds the language-neutral Bliptrace error envelope from a Ruby Exception,
# scrubs PII, and ships it to the ingest API. The SDK must never raise into the
# host application.
module Bliptrace
end
