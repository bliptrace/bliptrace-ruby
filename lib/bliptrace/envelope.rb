# frozen_string_literal: true

require "securerandom"
require "time"

module Bliptrace
  # Builds the language-neutral Bliptrace error envelope from a Ruby Exception.
  #
  # NOTE: `project` is intentionally never put in the payload — it is resolved
  # server-side from the ingest key.
  module Envelope
    module_function

    # @param exception [Exception]
    # @param config [Bliptrace::Config]
    # @param context [Hash] already-scrubbed context (request/user/custom)
    # @return [Hash]
    def build(exception, config, context = {})
      {
        "schema_version" => "1.0",
        "event_id" => SecureRandom.uuid,
        "occurred_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%LZ"),
        "runtime" => { "name" => "ruby", "version" => RUBY_VERSION },
        "sdk" => { "name" => config.sdk_name, "version" => config.sdk_version },
        "environment" => config.environment,
        "release" => config.release,
        "level" => level_for(exception),
        "exception" => {
          "type" => exception.class.name,
          "message" => limit(exception.message.to_s, config.max_message),
          "frames" => frames(exception, config)
        },
        "context" => normalise_context(context)
      }
    end

    # Map a Ruby exception to an envelope level. SignalException / NoMemoryError
    # and friends are treated as fatal; everything else is an error.
    def level_for(exception)
      fatal = [SignalException, NoMemoryError, SystemStackError, SecurityError]
      fatal.any? { |klass| exception.is_a?(klass) } ? "fatal" : "error"
    end

    # Build frames from backtrace_locations (preferred) or a parsed backtrace.
    def frames(exception, config)
      locations = exception.respond_to?(:backtrace_locations) ? exception.backtrace_locations : nil

      raw =
        if locations && !locations.empty?
          locations.map do |loc|
            { path: loc.absolute_path || loc.path, line: loc.lineno, function: loc.label }
          end
        else
          Array(exception.backtrace).map { |line| parse_backtrace_line(line) }
        end

      raw.first(config.max_frames).map do |frame|
        {
          "file" => frame[:path].to_s,
          "line" => frame[:line].to_i,
          "function" => frame[:function].to_s,
          "in_app" => in_app?(frame[:path].to_s, config.base_path)
        }
      end
    end

    # Parse "path:lineno:in `method'" (or "in 'method'") backtrace strings.
    def parse_backtrace_line(line)
      if line =~ /\A(.+):(\d+):in [`'](.*)'\z/
        { path: Regexp.last_match(1), line: Regexp.last_match(2).to_i, function: Regexp.last_match(3) }
      elsif line =~ /\A(.+):(\d+)\z/
        { path: Regexp.last_match(1), line: Regexp.last_match(2).to_i, function: "" }
      else
        { path: line.to_s, line: 0, function: "" }
      end
    end

    # in_app = path starts with base_path AND not under a /gems/ path; if
    # base_path is empty, in_app = !path.include?('/gems/').
    def in_app?(path, base_path)
      return false if path.nil? || path.empty?

      if base_path.nil? || base_path.empty?
        !path.include?("/gems/")
      else
        path.start_with?(base_path) && !path.include?("/gems/")
      end
    end

    def limit(value, max)
      value.length > max ? value[0, max] : value
    end

    # Ensure empty context map fields encode as JSON objects, not arrays.
    def normalise_context(context)
      ctx = (context || {}).dup
      ctx
    end
  end
end
