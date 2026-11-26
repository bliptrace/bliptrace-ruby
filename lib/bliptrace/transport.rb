# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Bliptrace
  # Transport is a duck-typed interface: any object that responds to
  # #send_envelope(endpoint, key, envelope, timeout) (or #call with the same
  # arguments) can be used as a transport. Implementations MUST NEVER raise.
  module Transport
    # Default transport using stdlib Net::HTTP (no third-party HTTP gem).
    #
    # Wraps each send in a retry loop with exponential backoff + jitter (via
    # RetryPolicy). The same serialized body -- hence the same event_id -- is
    # replayed on every attempt, so the ingest API's idempotency dedupe makes
    # this safe: a retry never creates a duplicate occurrence (spec section 10).
    class NetHttp
      INGEST_PATH = "/v1/ingest"

      # @param policy [Bliptrace::RetryPolicy] retry strategy (pure, injectable)
      def initialize(policy = nil)
        @policy = policy || RetryPolicy.new
      end

      # Ship the envelope. Swallows all errors -- capturing must never break the
      # monitored app, and never blocks longer than the retry policy's cap.
      def send_envelope(endpoint, key, envelope, timeout = 3)
        url = endpoint.to_s.sub(%r{/+\z}, "") + INGEST_PATH
        body = JSON.generate(envelope)

        attempt = 0
        loop do
          status, retry_after = attempt_request(url, body, key, timeout)
          return nil unless @policy.should_retry?(status, attempt)

          sleep_ms(@policy.delay_ms(attempt, retry_after_seconds: retry_after))
          attempt += 1
        end
      rescue StandardError
        nil
      end

      # Duck-typed alias so any object responding to #call also works.
      def call(endpoint, key, envelope, timeout = 3)
        send_envelope(endpoint, key, envelope, timeout)
      end

      protected

      # Perform one HTTP attempt. Returns [status, retry_after_seconds]; status
      # is 0 (RetryPolicy::TRANSPORT_ERROR) on a transport error/timeout, and
      # retry_after is an Integer of seconds or nil. The SAME +body+ is replayed
      # every attempt, keeping event_id constant. Overridable so tests can
      # script status sequences without real network I/O.
      def attempt_request(url, body, key, timeout)
        uri = URI.parse(url)

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
        request.body = body

        response = http.request(request)
        [response.code.to_i, parse_retry_after(response["Retry-After"])]
      rescue StandardError
        # No HTTP response (timeout / connection error): signal a transport
        # error so the policy can decide whether to retry.
        [RetryPolicy::TRANSPORT_ERROR, nil]
      end

      # Sleep between attempts. Overridable so tests run without real delay.
      def sleep_ms(ms)
        sleep(ms / 1000.0) if ms && ms > 0
        nil
      end

      # Parse a numeric Retry-After header (seconds). Returns an Integer or nil;
      # the HTTP-date form is ignored (treated as absent).
      def parse_retry_after(value)
        return nil if value.nil?

        s = value.to_s.strip
        return nil unless s =~ /\A\d+\z/

        s.to_i
      end
    end
  end
end
