# Hooksmith

**Hooksmith** is a modular, Rails-friendly gem for processing webhooks. It allows you to register multiple processors for different providers and events, ensuring that only one processor handles a given payload. If multiple processors qualify, an error is raised to avoid ambiguous behavior.

## Features

- **DSL for Registration:** Group processors by provider and event.
- **Flexible Dispatcher:** Dynamically selects the appropriate processor based on payload conditions.
- **Request Verification:** Built-in support for HMAC and Bearer token authentication.
- **Idempotency Support:** Prevent duplicate webhook processing with configurable key extraction.
- **ActiveJob Integration:** Process webhooks asynchronously with automatic idempotency checks.
- **Instrumentation:** ActiveSupport::Notifications hooks for observability.
- **Rails Controller Concern:** Standardized webhook handling with consistent response codes.
- **Rails Integration:** Automatically configures with Rails using a Railtie.
- **Lightweight Logging:** Built-in logging that can be switched to `Rails.logger` when in a Rails environment.
- **Tested with Minitest:** Comprehensive test coverage for robust behavior.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'hooksmith', '~> 1.0'
```

Then execute:
```bash
bundle install
```

Or install it yourself as:

```bash
gem install hooksmith
```

## Quick Start

### 1. Configure Providers and Processors

Configure your webhook processors in an initializer (e.g., `config/initializers/hooksmith.rb`):

```ruby
Hooksmith.configure do |config|
  config.provider(:stripe) do |stripe|
    stripe.register(:charge_succeeded, 'Stripe::ChargeSucceededProcessor')
    stripe.register(:payment_failed, 'Stripe::PaymentFailedProcessor')
  end

  config.provider(:github) do |github|
    github.register(:push, 'Github::PushProcessor')
    github.register(:pull_request, 'Github::PullRequestProcessor')
  end
end
```

### 2. Create a Processor

Create a processor by inheriting from `Hooksmith::Processor::Base`:

```ruby
class Stripe::ChargeSucceededProcessor < Hooksmith::Processor::Base
  def can_handle?(payload)
    payload.dig('data', 'object', 'status') == 'succeeded'
  end

  def process!
    charge_id = payload.dig('data', 'object', 'id')
    Payment.find_by(stripe_charge_id: charge_id)&.mark_as_paid!
  end
end
```

### 3. Handle Webhooks in Your Controller

```ruby
class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def stripe
    Hooksmith::Dispatcher.new(
      provider: :stripe,
      event: params[:type],
      payload: params.to_unsafe_h
    ).run!

    head :ok
  rescue StandardError => e
    head :internal_server_error
  end
end
```

## Request Verification

Hooksmith provides built-in verifiers for common authentication patterns.

### HMAC Verification

```ruby
Hooksmith.configure do |config|
  config.provider(:stripe) do |stripe|
    stripe.verifier = Hooksmith::Verifiers::Hmac.new(
      secret: ENV['STRIPE_WEBHOOK_SECRET'],
      header: 'Stripe-Signature',
      algorithm: :sha256
    )
  end
end
```

### Bearer Token Verification

```ruby
Hooksmith.configure do |config|
  config.provider(:internal) do |internal|
    internal.verifier = Hooksmith::Verifiers::BearerToken.new(
      token: ENV['WEBHOOK_SECRET_TOKEN'],
      header: 'Authorization'
    )
  end
end
```

### Custom Verifier

Create your own verifier by inheriting from `Hooksmith::Verifiers::Base`:

```ruby
class MyCustomVerifier < Hooksmith::Verifiers::Base
  def verify!(request)
    signature = request.headers['X-Custom-Signature']
    expected = compute_signature(request.body)

    raise Hooksmith::VerificationError, 'Invalid signature' unless secure_compare(signature, expected)
  end

  private

  def compute_signature(body)
    OpenSSL::HMAC.hexdigest('SHA256', @secret, body)
  end
end
```

## Idempotency Support

Prevent duplicate webhook processing by configuring idempotency key extraction:

```ruby
Hooksmith.configure do |config|
  config.provider(:stripe) do |stripe|
    stripe.idempotency_key = ->(payload) { payload.dig('id') }
  end

  config.provider(:github) do |github|
    github.idempotency_key = Hooksmith::Idempotency::GITHUB
  end
end
```

### Pre-built Extractors

Hooksmith includes pre-built extractors for common providers:

- `Hooksmith::Idempotency::STRIPE` - Extracts from `id` field
- `Hooksmith::Idempotency::GITHUB` - Extracts from `X-GitHub-Delivery` header
- `Hooksmith::Idempotency::GENERIC` - Extracts from `id`, `event_id`, or `request_id`

### Checking for Duplicates

```ruby
key = Hooksmith::Idempotency.extract_key(provider: 'stripe', payload: params)
if Hooksmith::Idempotency.already_processed?(provider: 'stripe', key: key)
  head :ok
  return
end
```

## ActiveJob Integration

Process webhooks asynchronously with automatic idempotency checking:

```ruby
class WebhooksController < ApplicationController
  def stripe
    Hooksmith::Jobs::DispatcherJob.perform_later(
      provider: 'stripe',
      event: params[:type],
      payload: params.to_unsafe_h
    )

    head :ok
  end
end
```

Skip idempotency checking if needed:

```ruby
Hooksmith::Jobs::DispatcherJob.perform_later(
  provider: 'stripe',
  event: params[:type],
  payload: params.to_unsafe_h,
  skip_idempotency_check: true
)
```

## Rails Controller Concern

Use the built-in controller concern for standardized webhook handling:

```ruby
class WebhooksController < ApplicationController
  include Hooksmith::Rails::WebhooksController

  def stripe
    handle_webhook(
      provider: 'stripe',
      event: params[:type],
      payload: params.to_unsafe_h
    )
  end

  def github
    handle_webhook_async(
      provider: 'github',
      event: request.headers['X-GitHub-Event'],
      payload: params.to_unsafe_h
    )
  end
end
```

The concern provides:
- Automatic CSRF protection skip
- Optional signature verification (if configured)
- Consistent response codes (200, 401, 500)
- `handle_webhook` for synchronous processing
- `handle_webhook_async` for background processing

## Instrumentation

Hooksmith emits ActiveSupport::Notifications events for observability:

```ruby
ActiveSupport::Notifications.subscribe(/hooksmith/) do |name, start, finish, id, payload|
  Rails.logger.info "#{name}: #{payload.inspect} (#{finish - start}s)"
end
```

### Available Events

| Event | Description |
|-------|-------------|
| `dispatch.hooksmith` | Wraps the entire dispatch flow |
| `process.hooksmith` | Wraps processor execution |
| `no_processor.hooksmith` | When no processor matches |
| `multiple_processors.hooksmith` | When multiple processors match |
| `error.hooksmith` | When an error occurs |

### Subscribing to Specific Events

```ruby
Hooksmith::Instrumentation.subscribe('process') do |name, start, finish, id, payload|
  StatsD.timing("webhooks.#{payload[:provider]}.#{payload[:event]}", finish - start)
end
```

## Persisting Webhook Events

Hooksmith can optionally persist incoming webhook events to your database:

### 1. Create a Model

```ruby
class WebhookEvent < ApplicationRecord
  self.table_name = 'webhook_events'
end
```

### 2. Create a Migration

```ruby
create_table :webhook_events do |t|
  t.string   :provider
  t.string   :event
  t.jsonb    :payload
  t.string   :idempotency_key
  t.datetime :received_at
  t.timestamps

  t.index [:provider, :idempotency_key], unique: true
  t.index :event
  t.index :received_at
end
```

### 3. Configure the Event Store

```ruby
Hooksmith.configure do |config|
  config.event_store do |store|
    store.enabled = true
    store.model_class_name = 'WebhookEvent'
    store.record_timing = :before
    store.mapper = ->(provider:, event:, payload:) {
      {
        provider: provider.to_s,
        event: event.to_s,
        payload: payload,
        received_at: Time.current
      }
    }
  end
end
```

## Error Handling

Hooksmith provides specific error classes for different failure modes:

| Error Class | Description |
|-------------|-------------|
| `Hooksmith::Error` | Base error class |
| `Hooksmith::VerificationError` | Request signature verification failed |
| `Hooksmith::MultipleProcessorsError` | Multiple processors matched the payload |

```ruby
begin
  Hooksmith::Dispatcher.new(provider:, event:, payload:).run!
rescue Hooksmith::VerificationError => e
  render json: { error: 'Invalid signature' }, status: :unauthorized
rescue Hooksmith::MultipleProcessorsError => e
  render json: { error: 'Ambiguous processor' }, status: :unprocessable_entity
rescue StandardError => e
  render json: { error: 'Processing failed' }, status: :internal_server_error
end
```

## Testing

The gem includes a full test suite using Minitest. Run the tests with:

```bash
bundle exec rake test
```

### Testing Your Processors

```ruby
class ChargeSucceededProcessorTest < ActiveSupport::TestCase
  test 'processes successful charges' do
    payload = { 'data' => { 'object' => { 'id' => 'ch_123', 'status' => 'succeeded' } } }
    processor = Stripe::ChargeSucceededProcessor.new(payload)

    assert processor.can_handle?(payload)
    processor.process!

    assert Payment.find_by(stripe_charge_id: 'ch_123').paid?
  end
end
```

## Configuration Reference

```ruby
Hooksmith.configure do |config|
  config.provider(:stripe) do |stripe|
    stripe.register(:charge_succeeded, 'Stripe::ChargeSucceededProcessor')

    stripe.verifier = Hooksmith::Verifiers::Hmac.new(
      secret: ENV['STRIPE_WEBHOOK_SECRET'],
      header: 'Stripe-Signature',
      algorithm: :sha256
    )

    stripe.idempotency_key = ->(payload) { payload['id'] }
  end

  config.event_store do |store|
    store.enabled = true
    store.model_class_name = 'WebhookEvent'
    store.record_timing = :before
    store.mapper = ->(provider:, event:, payload:) { ... }
  end
end
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/RivageImmo/Hooksmith.

## License

The gem is available as open source under the terms of the MIT License.
