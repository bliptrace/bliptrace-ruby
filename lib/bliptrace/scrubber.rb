# frozen_string_literal: true

module Bliptrace
  # Client-side PII scrub: recursively redact configured keys (case-insensitive)
  # in a Hash before anything is sent.
  class Scrubber
    REDACTED = "[REDACTED]"

    def initialize(keys = [])
      @redact = Array(keys).map { |k| k.to_s.downcase }
    end

    # Returns a scrubbed copy of the given Hash. Non-Hash input is returned
    # untouched. Never raises.
    def scrub(data)
      return data unless data.is_a?(Hash)

      result = {}
      data.each do |key, value|
        if redact?(key)
          result[key] = REDACTED
        elsif value.is_a?(Hash)
          result[key] = scrub(value)
        elsif value.is_a?(Array)
          result[key] = value.map { |item| item.is_a?(Hash) ? scrub(item) : item }
        else
          result[key] = value
        end
      end
      result
    rescue StandardError
      data
    end

    private

    def redact?(key)
      @redact.include?(key.to_s.downcase)
    end
  end
end
