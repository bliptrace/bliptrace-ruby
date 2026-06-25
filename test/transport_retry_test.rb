# frozen_string_literal: true

require "test_helper"

# A NetHttp transport whose per-attempt HTTP call is scripted and whose sleep is
# recorded instead of performed -- so the retry loop is exercised with NO real
# network and NO real sleeping.
class ScriptedTransport < G8Scope::Transport::NetHttp
  attr_reader :attempts, :sleeps, :bodies

  # @param results [Array<Array(Integer, Integer|nil)>] [status, retry_after]
  #   returned per attempt, in order.
  def initialize(results, policy)
    super(policy)
    @results = results
    @attempts = 0
    @sleeps = []
    @bodies = []
  end

  protected

  def attempt_request(_url, body, _key, _timeout)
    @bodies << body
    result = @results[@attempts] || [200, nil]
    @attempts += 1
    result
  end

  def sleep_ms(ms)
    @sleeps << ms
    nil
  end
end

class TransportRetryTest < Minitest::Test
  def policy(**opts)
    G8Scope::RetryPolicy.new({ max_retries: 2, base_ms: 100, cap_ms: 2000 }.merge(opts))
  end

  def envelope
    { "event_id" => "11111111-1111-4111-8111-111111111111", "level" => "error" }
  end

  def test_stops_on_first_success
    t = ScriptedTransport.new([[202, nil]], policy)
    t.send_envelope("http://api", "k", envelope, 3)

    assert_equal 1, t.attempts
    assert_empty t.sleeps
  end

  def test_retries_then_succeeds
    t = ScriptedTransport.new([[503, nil], [200, nil]], policy)
    t.send_envelope("http://api", "k", envelope, 3)

    assert_equal 2, t.attempts
    assert_equal 1, t.sleeps.length # one delay between the two attempts
  end

  def test_gives_up_after_max_retries
    # All attempts fail; max_retries=2 means 1 initial + 2 retries == 3 attempts.
    t = ScriptedTransport.new([[503, nil], [503, nil], [503, nil], [503, nil]], policy)
    t.send_envelope("http://api", "k", envelope, 3)

    assert_equal 3, t.attempts
    assert_equal 2, t.sleeps.length
  end

  def test_does_not_retry_4xx
    t = ScriptedTransport.new([[400, nil], [200, nil]], policy)
    t.send_envelope("http://api", "k", envelope, 3)

    assert_equal 1, t.attempts # bad request is terminal
    assert_empty t.sleeps
  end

  def test_retries_transport_error
    # Status 0 == transport error/timeout, then success.
    t = ScriptedTransport.new([[0, nil], [202, nil]], policy)
    t.send_envelope("http://api", "k", envelope, 3)

    assert_equal 2, t.attempts
    assert_equal 1, t.sleeps.length
  end

  def test_honours_retry_after_from_attempt
    # cap large so the 1s Retry-After is honoured verbatim (1000ms).
    t = ScriptedTransport.new([[429, 1], [200, nil]], policy(cap_ms: 5000))
    t.send_envelope("http://api", "k", envelope, 3)

    assert_equal 2, t.attempts
    assert_equal [1000], t.sleeps
  end

  def test_replays_identical_body_and_event_id_across_attempts
    t = ScriptedTransport.new([[503, nil], [503, nil], [200, nil]], policy)
    t.send_envelope("http://api", "k", envelope, 3)

    assert_equal 3, t.bodies.length
    assert_equal 1, t.bodies.uniq.length, "body must be byte-identical across attempts"

    t.bodies.each do |body|
      parsed = JSON.parse(body)
      assert_equal "11111111-1111-4111-8111-111111111111", parsed["event_id"]
    end
  end

  def test_never_raises_even_when_attempt_blows_up
    raising = Class.new(G8Scope::Transport::NetHttp) do
      def attempt_request(*)
        raise "boom inside attempt"
      end
    end.new(policy)

    # Must swallow the error and return nil, never propagating into the app.
    assert_nil raising.send_envelope("http://api", "k", envelope, 3)
  end

  def test_call_alias_runs_the_retry_loop
    t = ScriptedTransport.new([[503, nil], [200, nil]], policy)
    t.call("http://api", "k", envelope, 3)

    assert_equal 2, t.attempts
  end
end
