# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "bliptrace/version"

Gem::Specification.new do |spec|
  spec.name          = "bliptrace"
  spec.version       = Bliptrace::VERSION
  spec.authors       = ["Developers Hub Sdn Bhd"]
  spec.email         = ["dev@developershub.my"]

  spec.summary       = "The runtime Ruby SDK for Bliptrace error capture and observability."
  spec.description   = "Builds the language-neutral Bliptrace error envelope from a Ruby " \
                       "Exception, scrubs PII, and ships it to the Bliptrace ingest API " \
                       "using only the standard library. Never raises into the host app."
  spec.homepage      = "https://github.com/bliptrace/bliptrace-ruby"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 2.6"

  spec.files = Dir["lib/**/*.rb"] + %w[README.md LICENSE]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", ">= 12.0"
end
