# frozen_string_literal: true

module G8Scope
  # Immutable-ish SDK configuration. Framework adapters build this from their
  # own config. Accepts either keyword arguments or a Hash (string or symbol
  # keys) via .new / .from_hash.
  class Config
    DEFAULT_ENDPOINT = "https://ingest.scope.g8suite.com"

    attr_reader :key, :endpoint, :environment, :release, :timeout,
                :max_frames, :max_message, :ignore_exceptions, :scrub_keys,
                :base_path, :enabled, :sdk_name, :sdk_version

    def initialize(
      key: nil,
      endpoint: DEFAULT_ENDPOINT,
      environment: "production",
      release: nil,
      timeout: 3,
      max_frames: 30,
      max_message: 2000,
      ignore_exceptions: [],
      scrub_keys: [],
      base_path: "",
      enabled: true,
      sdk_name: "g8scope-ruby",
      sdk_version: G8Scope::VERSION
    )
      @key = key
      @endpoint = endpoint || DEFAULT_ENDPOINT
      @environment = environment || "production"
      @release = release
      @timeout = (timeout || 3).to_i
      @max_frames = (max_frames || 30).to_i
      @max_message = (max_message || 2000).to_i
      @ignore_exceptions = Array(ignore_exceptions).map(&:to_s)
      @scrub_keys = Array(scrub_keys).map(&:to_s)
      @base_path = base_path.to_s
      @enabled = enabled.nil? ? true : enabled
      @sdk_name = sdk_name || "g8scope-ruby"
      @sdk_version = sdk_version || G8Scope::VERSION
    end

    # Build a Config from a Hash with string or symbol keys.
    def self.from_hash(hash)
      h = {}
      (hash || {}).each { |k, v| h[k.to_sym] = v }
      new(**h)
    end

    def enabled?
      @enabled == true
    end
  end
end
