# frozen_string_literal: true

module Bliptrace
  # The runtime Ruby client: decide whether to capture, build + scrub the
  # envelope, and ship it. Framework adapters either call #capture directly or
  # split #build_envelope / #send_envelope to defer the send (e.g. after the
  # HTTP response has flushed).
  #
  # The capture path NEVER raises into the host application.
  class Client
    attr_reader :config

    # @param config [Bliptrace::Config, Hash] config object or options hash
    # @param transport [#send_envelope, #call] defaults to Transport::NetHttp
    # @param scrubber [Bliptrace::Scrubber] defaults to one built from scrub_keys
    def initialize(config, transport = nil, scrubber = nil)
      @config = config.is_a?(Config) ? config : Config.from_hash(config)
      @transport = transport || Transport::NetHttp.new(RetryPolicy.from_config(@config))
      @scrubber = scrubber || Scrubber.new(@config.scrub_keys)
    end

    # Capture and ship immediately. Guard-wrapped — never throws into your app.
    def capture(exception, context = {})
      envelope = build_envelope(exception, context)
      send_envelope(envelope) if envelope
      nil
    rescue StandardError
      nil
    end

    # Build the envelope (scrubbing context), or nil when capture is disabled,
    # unconfigured, or the exception is ignored. Lets adapters defer the send.
    def build_envelope(exception, context = {})
      return nil unless @config.enabled?
      return nil if @config.key.nil? || @config.key.to_s.empty?
      return nil if ignore?(exception)

      Envelope.build(exception, @config, @scrubber.scrub(context || {}))
    rescue StandardError
      nil # never break the app
    end

    # Ship an already-built envelope via the configured transport.
    def send_envelope(envelope)
      return nil if envelope.nil?
      return nil if @config.key.nil? || @config.key.to_s.empty?

      if @transport.respond_to?(:send_envelope)
        @transport.send_envelope(@config.endpoint, @config.key, envelope, @config.timeout)
      elsif @transport.respond_to?(:call)
        @transport.call(@config.endpoint, @config.key, envelope, @config.timeout)
      end
      nil
    rescue StandardError
      nil
    end

    private

    def ignore?(exception)
      ancestry = exception.class.ancestors.map(&:to_s)
      @config.ignore_exceptions.any? do |name|
        ancestry.include?(name) || exception.class.name == name
      end
    end
  end
end
