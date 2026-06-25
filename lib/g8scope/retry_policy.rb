# frozen_string_literal: true

module G8Scope
  # Decides whether a failed ingest attempt should be retried, and how long to
  # wait. Mirrors the PHP SDK's RetryPolicy.
  #
  # The SDK owns "the backend might be briefly down or shedding (429)". Strategy:
  # exponential backoff (base * 2^attempt), +/-25% jitter to avoid a synchronised
  # thundering herd, and a hard cap on both attempts and delay so capturing can
  # never block the monitored app for long. Retries are only safe because the
  # envelope's event_id is reused across attempts and the ingest API dedupes on
  # it (spec section 10).
  #
  # Pure and immutable: no I/O, no sleeping -- that lives in the transport.
  class RetryPolicy
    # Status used to represent a transport error / timeout (no HTTP response).
    TRANSPORT_ERROR = 0

    attr_reader :max_retries, :base_ms, :cap_ms

    def initialize(max_retries: 2, base_ms: 100, cap_ms: 2000)
      @max_retries = (max_retries || 2).to_i
      @base_ms = (base_ms || 100).to_i
      @cap_ms = (cap_ms || 2000).to_i
    end

    # Build from the SDK config (framework adapters pass their own values).
    def self.from_config(config)
      new(
        max_retries: config.max_retries,
        base_ms: config.retry_base_ms,
        cap_ms: config.retry_cap_ms
      )
    end

    # Should we retry after seeing +status+, having already done +attempt+
    # retries? Retryable: transport errors / timeouts (status 0), 408, 429, and
    # any 5xx. Never retry a 2xx (success) or other 4xx (the request is bad).
    def should_retry?(status, attempt)
      return false if attempt.to_i >= @max_retries

      retryable?(status)
    end

    def retryable?(status)
      s = status.to_i
      s == TRANSPORT_ERROR || s == 408 || s == 429 || s >= 500
    end

    # Delay before the next attempt, in milliseconds.
    #
    # A server-sent Retry-After (seconds) wins, capped to cap_ms so a hostile or
    # misconfigured header can't stall the app. Otherwise: exponential backoff
    # with +/-25% jitter, capped at cap_ms. +jitter+ is an injectable callable
    # returning a float in [0,1); it defaults to a uniform random draw.
    def delay_ms(attempt, retry_after_seconds: nil, jitter: nil)
      if !retry_after_seconds.nil? && retry_after_seconds.to_i > 0
        return [@cap_ms, retry_after_seconds.to_i * 1000].min
      end

      a = attempt.to_i
      a = 0 if a < 0
      exp = [@cap_ms, @base_ms * (2**a)].min

      rand_value = jitter ? jitter.call.to_f : rand
      delta = (exp * 0.25 * ((2 * rand_value) - 1)).round # +/-25%

      [0, [@cap_ms, exp + delta].min].max
    end
  end
end
