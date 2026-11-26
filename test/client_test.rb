# frozen_string_literal: true

require "test_helper"

class ClientTest < Minitest::Test
  UUID_RE = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/.freeze

  def raised(klass = RuntimeError, message = "boom")
    raise klass, message
  rescue klass => e
    e
  end

  def test_builds_and_ships_a_valid_envelope
    t = FakeTransport.new
    client = Bliptrace::Client.new(
      Bliptrace::Config.new(key: "k", endpoint: "http://api", base_path: "/srv/app"),
      t
    )
    client.capture(raised(RuntimeError, "boom"))

    assert_equal 1, t.sent.length
    env = t.sent.first[:envelope]

    assert_equal "1.0", env["schema_version"]
    assert_match UUID_RE, env["event_id"]
    assert_equal "ruby", env["runtime"]["name"]
    assert_equal RUBY_VERSION, env["runtime"]["version"]
    assert_equal "bliptrace-ruby", env["sdk"]["name"]
    assert_equal "1.0.0", env["sdk"]["version"]
    assert_equal "error", env["level"]
    assert_equal "RuntimeError", env["exception"]["type"]
    assert_equal "boom", env["exception"]["message"]

    frame = env["exception"]["frames"].first
    refute_nil frame
    %w[file line function in_app].each do |k|
      assert frame.key?(k), "frame missing key #{k}"
    end

    assert_equal "http://api", t.sent.first[:endpoint]
    assert_equal "k", t.sent.first[:key]
  end

  def test_occurred_at_is_rfc3339_with_milliseconds
    t = FakeTransport.new
    Bliptrace::Client.new(Bliptrace::Config.new(key: "k"), t).capture(raised)
    assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/, t.sent.first[:envelope]["occurred_at"])
  end

  def test_ignores_configured_exception_types
    t = FakeTransport.new
    client = Bliptrace::Client.new(
      Bliptrace::Config.new(key: "k", ignore_exceptions: ["ArgumentError"]),
      t
    )
    client.capture(raised(ArgumentError, "noise"))
    assert_empty t.sent
  end

  def test_does_nothing_without_a_key
    t = FakeTransport.new
    Bliptrace::Client.new(Bliptrace::Config.new(key: nil), t).capture(raised)
    assert_empty t.sent
  end

  def test_does_nothing_when_disabled
    t = FakeTransport.new
    Bliptrace::Client.new(Bliptrace::Config.new(key: "k", enabled: false), t).capture(raised)
    assert_empty t.sent
  end

  def test_scrubs_sensitive_context_before_sending
    t = FakeTransport.new
    client = Bliptrace::Client.new(
      Bliptrace::Config.new(key: "k", scrub_keys: ["password"]),
      t
    )
    client.capture(raised, "user" => { "password" => "hunter2", "id" => "7" })

    ctx = t.sent.first[:envelope]["context"]
    assert_equal "[REDACTED]", ctx["user"]["password"]
    assert_equal "7", ctx["user"]["id"]
  end

  def test_scrub_is_case_insensitive_and_nested_in_arrays
    t = FakeTransport.new
    client = Bliptrace::Client.new(
      Bliptrace::Config.new(key: "k", scrub_keys: ["Token"]),
      t
    )
    client.capture(raised, "list" => [{ "token" => "abc" }], "TOKEN" => "x")

    ctx = t.sent.first[:envelope]["context"]
    assert_equal "[REDACTED]", ctx["TOKEN"]
    assert_equal "[REDACTED]", ctx["list"].first["token"]
  end

  def test_never_raises_on_weird_context
    t = FakeTransport.new
    client = Bliptrace::Client.new(Bliptrace::Config.new(key: "k"), t)
    weird = { "a" => proc { 1 }, "b" => Object.new }
    assert_nil client.capture(raised, weird)
  end

  def test_accepts_hash_config
    t = FakeTransport.new
    client = Bliptrace::Client.new({ "key" => "k", "environment" => "staging" }, t)
    client.capture(raised)
    assert_equal "staging", t.sent.first[:envelope]["environment"]
  end

  def test_build_and_send_can_be_split
    t = FakeTransport.new
    client = Bliptrace::Client.new(Bliptrace::Config.new(key: "k"), t)
    env = client.build_envelope(raised)
    refute_nil env
    assert_empty t.sent
    client.send_envelope(env)
    assert_equal 1, t.sent.length
  end

  def test_marks_fatal_for_fatal_class
    t = FakeTransport.new
    client = Bliptrace::Client.new(Bliptrace::Config.new(key: "k"), t)
    err =
      begin
        raise NoMemoryError, "oom"
      rescue NoMemoryError => e
        e
      end
    client.capture(err)
    assert_equal "fatal", t.sent.first[:envelope]["level"]
  end

  def test_never_puts_project_in_payload
    t = FakeTransport.new
    Bliptrace::Client.new(Bliptrace::Config.new(key: "k"), t).capture(raised)
    refute t.sent.first[:envelope].key?("project")
  end
end
