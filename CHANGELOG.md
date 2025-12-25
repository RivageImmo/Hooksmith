## [Unreleased]

## [1.0.0] - 2025-12-25

### Added

- **Request Verification Interface** - Built-in verifiers for HMAC and Bearer token authentication
  - `Hooksmith::Verifiers::Hmac` for HMAC-based signature verification
  - `Hooksmith::Verifiers::BearerToken` for Bearer token authentication
  - `Hooksmith::Verifiers::Base` for creating custom verifiers
  - `Hooksmith::Request` wrapper for accessing headers and body

- **Error Taxonomy** - Explicit error classes for different failure modes
  - `Hooksmith::Error` base class for all Hooksmith errors
  - `Hooksmith::VerificationError` for signature verification failures

- **Idempotency Support** - Prevent duplicate webhook processing
  - Configurable idempotency key extraction per provider
  - Pre-built extractors for Stripe, GitHub, and generic webhooks
  - `Hooksmith::Idempotency.extract_key` and `already_processed?` methods

- **ActiveJob Integration** - Process webhooks asynchronously
  - `Hooksmith::Jobs::DispatcherJob` for background processing
  - Automatic idempotency checking (can be skipped)

- **Instrumentation** - ActiveSupport::Notifications hooks for observability
  - `dispatch.hooksmith` event wrapping the entire dispatch flow
  - `process.hooksmith` event wrapping processor execution
  - `no_processor.hooksmith` event when no processor matches
  - `multiple_processors.hooksmith` event when multiple processors match
  - `error.hooksmith` event when an error occurs

- **Rails Controller Concern** - Standardized webhook handling
  - `Hooksmith::Rails::WebhooksController` concern
  - `handle_webhook` for synchronous processing
  - `handle_webhook_async` for background processing
  - Automatic CSRF protection skip
  - Optional signature verification integration

### Changed

- Internal storage now uses strings instead of symbols to prevent Symbol DoS attacks
- `MultipleProcessorsError` no longer includes full payload in error message to prevent PII exposure

### Security

- Fixed Symbol DoS vulnerability in Dispatcher (provider/event were converted to symbols from untrusted input)
- Fixed PII exposure in `MultipleProcessorsError` (full payload was included in error message)

## [0.2.0] - 2025-03-15

- Added event store for persisting webhook events
- Added configurable mapper for event persistence

## [0.1.0] - 2025-03-12

- Initial release
