$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'bliptrace'

Bliptrace.init(
  key: ENV['BLIPTRACE_KEY'],
  endpoint: ENV.fetch('BLIPTRACE_ENDPOINT', 'http://localhost:8088'),
  environment: 'demo',
  release: 'demo-ruby@1.0'
)

def fire(level: 'error')
  yield
rescue StandardError, ScriptError => e
  Bliptrace.capture(e, level: level, context: { demo: true })
  puts "captured: #{e.class}"
end

fire(level: 'fatal') { 1 / 0 }              # ZeroDivisionError
fire { [].fetch(5) }                        # IndexError
fire { {}.fetch(:nope) }                    # KeyError
fire { Integer('not-a-number') }            # ArgumentError
fire { nil.upcase }                         # NoMethodError
puts 'done'
