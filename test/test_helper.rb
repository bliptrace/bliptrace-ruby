# frozen_string_literal: true

# minitest ships with Ruby but is not always on the default load path (e.g. the
# macOS system Ruby installs it under /Library/Ruby/Gems). Make the suite runnable
# standalone with `ruby -Ilib -Itest test/client_test.rb` by discovering it.
begin
  require "minitest/autorun"
rescue LoadError
  Gem.path.dup.push("/Library/Ruby/Gems/#{RUBY_VERSION[/\d+\.\d+/]}.0").each do |base|
    candidate = Dir["#{base}/gems/minitest-*/lib"].sort.last
    $LOAD_PATH.unshift(candidate) if candidate && Dir.exist?(candidate)
  end
  require "minitest/autorun"
end

require "bliptrace"

# A fake transport that records every envelope it is asked to ship instead of
# making any network call. Used across the test suite.
class FakeTransport
  attr_reader :sent

  def initialize
    @sent = []
  end

  def send_envelope(endpoint, key, envelope, timeout = 3)
    @sent << {
      endpoint: endpoint,
      key: key,
      envelope: envelope,
      timeout: timeout
    }
    nil
  end
end
