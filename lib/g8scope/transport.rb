# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module G8Scope
  # Transport is a duck-typed interface: any object that responds to
  # #send_envelope(endpoint, key, envelope, timeout) (or #call with the same
  # arguments) can be used as a transport. Implementations MUST NEVER raise.
  module Transport
    # Default transport using stdlib Net::HTTP (no third-party HTTP gem).
    class NetHttp
      INGEST_PATH = "/v1/ingest"

      # Ship the envelope. Swallows all errors — capturing must never break the
      # monitored app.
      def send_envelope(endpoint, key, envelope, timeout = 3)
        uri = URI.parse(endpoint.to_s.sub(%r{/+\z}, "") + INGEST_PATH)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        t = timeout.to_i
        t = 1 if t < 1
        http.open_timeout = t
        http.read_timeout = t
        http.write_timeout = t if http.respond_to?(:write_timeout=)

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/json"
        request["X-Ingest-Key"] = key.to_s
        request.body = JSON.generate(envelope)

        http.request(request)
        nil
      rescue StandardError
        nil
      end

      # Duck-typed alias so any object responding to #call also works.
      def call(endpoint, key, envelope, timeout = 3)
        send_envelope(endpoint, key, envelope, timeout)
      end
    end
  end
end
