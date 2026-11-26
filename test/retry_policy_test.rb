# frozen_string_literal: true

require "test_helper"

class RetryPolicyTest < Minitest::Test
  # 2 * 0.5 - 1 == 0, so this jitter contributes no delta.
  NO_JITTER = -> { 0.5 }

  def test_retryable_classification
    policy = Bliptrace::RetryPolicy.new(max_retries: 5)

    {
      0   => true,  # transport error / timeout
      408 => true,  # request timeout
      429 => true,  # too many requests
      500 => true,
      502 => true,
      503 => true,
      599 => true,
      200 => false, # success
      202 => false, # accepted
      400 => false,
      403 => false,
      404 => false,
      418 => false
    }.each do |status, expected|
      assert_equal expected, policy.retryable?(status), "status #{status}"
    end
  end

  def test_stops_once_attempt_cap_reached
    policy = Bliptrace::RetryPolicy.new(max_retries: 2)

    assert policy.should_retry?(503, 0)
    assert policy.should_retry?(503, 1)
    refute policy.should_retry?(503, 2) # exhausted
  end

  def test_does_not_retry_non_retryable_even_with_attempts_left
    policy = Bliptrace::RetryPolicy.new(max_retries: 5)

    refute policy.should_retry?(200, 0)
    refute policy.should_retry?(400, 0)
    refute policy.should_retry?(403, 1)
  end

  def test_backoff_grows_exponentially_and_caps
    policy = Bliptrace::RetryPolicy.new(base_ms: 100, cap_ms: 2000)

    assert_equal 100, policy.delay_ms(0, jitter: NO_JITTER)
    assert_equal 200, policy.delay_ms(1, jitter: NO_JITTER)
    assert_equal 400, policy.delay_ms(2, jitter: NO_JITTER)
    assert_equal 800, policy.delay_ms(3, jitter: NO_JITTER)
    assert_equal 2000, policy.delay_ms(8, jitter: NO_JITTER) # capped
  end

  def test_jitter_stays_within_plus_minus_25_percent
    # Large cap so jitter is never clamped by the cap during this test.
    policy = Bliptrace::RetryPolicy.new(base_ms: 100, cap_ms: 100_000)

    [-> { 0.0 }, -> { 0.999 }, -> { 0.5 }, -> { 0.25 }, -> { 0.75 }].each do |jitter|
      d = policy.delay_ms(3, jitter: jitter) # base exp == 800ms
      assert d >= 600, "delay #{d} below -25% bound for jitter #{jitter.call}"
      assert d <= 1000, "delay #{d} above +25% bound for jitter #{jitter.call}"
    end
  end

  def test_delay_clamped_to_zero_and_cap
    policy = Bliptrace::RetryPolicy.new(base_ms: 100, cap_ms: 2000)

    # Minimum jitter pushes toward 0 but never below it.
    assert_equal 75, policy.delay_ms(0, jitter: -> { 0.0 }) # 100 - 25
    refute policy.delay_ms(0, jitter: -> { 0.0 }).negative?

    # Maximum jitter never exceeds the cap.
    assert policy.delay_ms(8, jitter: -> { 0.999 }) <= 2000
  end

  def test_retry_after_seconds_honoured_and_capped
    policy = Bliptrace::RetryPolicy.new(cap_ms: 5000)

    assert_equal 2000, policy.delay_ms(0, retry_after_seconds: 2)   # 2s honoured
    assert_equal 5000, policy.delay_ms(0, retry_after_seconds: 999) # hostile value capped
  end

  def test_retry_after_zero_or_nil_falls_back_to_backoff
    policy = Bliptrace::RetryPolicy.new(base_ms: 100, cap_ms: 2000)

    assert_equal 100, policy.delay_ms(0, retry_after_seconds: 0, jitter: NO_JITTER)
    assert_equal 100, policy.delay_ms(0, retry_after_seconds: nil, jitter: NO_JITTER)
  end

  def test_from_config_threads_knobs
    config = Bliptrace::Config.new(key: "k", max_retries: 7, retry_base_ms: 50, retry_cap_ms: 9000)
    policy = Bliptrace::RetryPolicy.from_config(config)

    assert_equal 7, policy.max_retries
    assert_equal 50, policy.base_ms
    assert_equal 9000, policy.cap_ms
  end

  def test_config_defaults
    config = Bliptrace::Config.new(key: "k")

    assert_equal 2, config.max_retries
    assert_equal 100, config.retry_base_ms
    assert_equal 2000, config.retry_cap_ms
  end
end
