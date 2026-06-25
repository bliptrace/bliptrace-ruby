$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'g8scope'

G8scope.init(
  key: ENV['G8SCOPE_KEY'],
  endpoint: ENV.fetch('G8SCOPE_ENDPOINT', 'http://localhost:8088'),
  environment: 'demo',
  release: 'demo-ruby@1.0'
)

def fire(level: 'error')
  yield
rescue StandardError, ScriptError => e
  G8scope.capture(e, level: level, context: { demo: true })
  puts "captured: #{e.class}"
end

fire(level: 'fatal') { 1 / 0 }              # ZeroDivisionError
fire { [].fetch(5) }                        # IndexError
fire { {}.fetch(:nope) }                    # KeyError
fire { Integer('not-a-number') }            # ArgumentError
fire { nil.upcase }                         # NoMethodError
puts 'done'
