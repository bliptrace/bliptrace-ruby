# g8scope-ruby

The runtime **Ruby SDK** for [g8scope](https://scope.g8suite.com) — a central,
multi-tenant, runtime-agnostic error-capture and observability platform.

This SDK builds the language-neutral **error envelope** from a Ruby `Exception`,
scrubs PII, and ships it to the g8scope ingest API over HTTPS using only the
standard library (`Net::HTTP`). It never raises into your application.

## Installation

Install directly:

```sh
gem install g8scope
```

Or add it to your `Gemfile`:

```ruby
gem "g8scope"
```

then run `bundle install`.

The SDK has **no runtime dependencies** and supports **Ruby 2.6+**.

## Usage

```ruby
require "g8scope"

client = G8Scope::Client.new(
  G8Scope::Config.new(
    key: ENV["G8SCOPE_INGEST_KEY"],   # your project ingest key
    environment: "production",
    release: "my-app@2026.06.25",
    base_path: Dir.pwd,               # used to flag in-app stack frames
    scrub_keys: %w[password token authorization secret]
  )
)

begin
  do_something_risky!
rescue => e
  client.capture(e, user: { id: current_user_id }, request: { method: "POST", url: "/checkout" })
  raise # re-raise if you still want your own handling
end
```

You can also pass a plain Hash instead of a `Config`:

```ruby
client = G8Scope::Client.new(key: ENV["G8SCOPE_INGEST_KEY"], environment: "staging")
```

### Deferring the send

Adapters that want to ship after the HTTP response has flushed can split the two
steps:

```ruby
envelope = client.build_envelope(exception, context)
# ... later ...
client.send_envelope(envelope) if envelope
```

### Custom transport

Any object that responds to `send_envelope(endpoint, key, envelope, timeout)`
(or `call` with the same arguments) can be used as a transport — useful for
buffering, testing, or routing through your own queue:

```ruby
client = G8Scope::Client.new(config, MyTransport.new)
```

## Configuration

| Option              | Default                              | Description                                                   |
| ------------------- | ------------------------------------ | ------------------------------------------------------------- |
| `key`               | `nil`                                | Project ingest key. No key means nothing is sent.             |
| `endpoint`          | `https://ingest.scope.g8suite.com`   | Ingest base URL; the SDK POSTs to `{endpoint}/v1/ingest`.     |
| `environment`       | `"production"`                        | Deployment environment.                                       |
| `release`           | `nil`                                 | Release marker, e.g. `my-app@2026.06.25`.                     |
| `timeout`           | `3`                                   | HTTP timeout in seconds.                                      |
| `max_frames`        | `30`                                  | Maximum stack frames captured.                                |
| `max_message`       | `2000`                                | Exception message truncation length.                         |
| `ignore_exceptions` | `[]`                                  | Class names (strings) to skip.                                |
| `scrub_keys`        | `[]`                                  | Context keys to redact (case-insensitive, recursive).        |
| `base_path`         | `""`                                  | App root; frames under it (and not under `/gems/`) are in-app. |
| `enabled`           | `true`                                | Master switch.                                                |
| `sdk_name`          | `"g8scope-ruby"`                      | Reported SDK name.                                            |
| `sdk_version`       | `G8Scope::VERSION`                    | Reported SDK version.                                         |

## A note on tenancy

The SDK **never** puts `project` in the payload. Your project (and therefore
your tenant) is resolved **server-side from the ingest key** — this is what
prevents one client from spoofing another tenant.

## Testing

The test suite uses **minitest** from the standard library and needs no bundler
or network access:

```sh
ruby -Ilib -Itest test/client_test.rb
```

or, with Rake:

```sh
rake test
```

## Licence

MIT © Developers Hub Sdn Bhd. See [LICENSE](LICENSE).
