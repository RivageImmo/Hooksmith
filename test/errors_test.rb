# frozen_string_literal: true

require 'test_helper'

# ErrorsTest
class ErrorsTest < Minitest::Test
  def test_base_error_inherits_from_standard_error
    assert Hooksmith::Error < StandardError
  end

  def test_base_error_stores_provider_and_event
    error = Hooksmith::Error.new('test message', provider: :stripe, event: :charge_succeeded)
    assert_equal 'stripe', error.provider
    assert_equal 'charge_succeeded', error.event
    assert_equal 'test message', error.message
  end

  def test_verification_error_stores_reason
    error = Hooksmith::VerificationError.new('Invalid signature', provider: 'stripe', reason: 'invalid_hmac')
    assert_equal 'stripe', error.provider
    assert_equal 'invalid_hmac', error.reason
    assert_equal 'Invalid signature', error.message
  end

  def test_no_processor_error_message
    error = Hooksmith::NoProcessorError.new(:stripe, :unknown_event)
    assert_equal 'stripe', error.provider
    assert_equal 'unknown_event', error.event
    assert_match(/No processor registered/, error.message)
    assert_match(/stripe/, error.message)
    assert_match(/unknown_event/, error.message)
  end

  def test_multiple_processors_error_does_not_expose_payload
    sensitive_payload = {
      email: 'user@example.com',
      password: 'secret123',
      credit_card: '4111111111111111',
      ssn: '123-45-6789'
    }

    error = Hooksmith::MultipleProcessorsError.new(
      :stripe,
      :charge_succeeded,
      sensitive_payload,
      processor_names: %w[ProcessorA ProcessorB]
    )

    # Error message should NOT contain sensitive data
    refute_match(/user@example\.com/, error.message)
    refute_match(/secret123/, error.message)
    refute_match(/4111111111111111/, error.message)
    refute_match(/123-45-6789/, error.message)

    # Error should include provider, event, and payload size for debugging
    assert_match(/stripe/, error.message)
    assert_match(/charge_succeeded/, error.message)
    assert_match(/payload_size=\d+ bytes/, error.message)
  end

  def test_multiple_processors_error_stores_metadata
    payload = { foo: 'bar' }
    error = Hooksmith::MultipleProcessorsError.new(
      :stripe,
      :charge_succeeded,
      payload,
      processor_names: %w[ProcessorA ProcessorB]
    )

    assert_equal 'stripe', error.provider
    assert_equal 'charge_succeeded', error.event
    assert error.payload_size.positive?
    assert_equal %w[ProcessorA ProcessorB], error.processor_names
  end

  def test_processor_error_stores_original_error
    original = StandardError.new('original error')
    error = Hooksmith::ProcessorError.new(
      'Processing failed',
      provider: :stripe,
      event: :charge_succeeded,
      processor_class: 'MyProcessor',
      original_error: original
    )

    assert_equal 'stripe', error.provider
    assert_equal 'charge_succeeded', error.event
    assert_equal 'MyProcessor', error.processor_class
    assert_equal original, error.original_error
    assert_equal 'Processing failed', error.message
  end

  def test_unknown_event_error_message
    error = Hooksmith::UnknownEventError.new(:stripe, :invalid_event)
    assert_equal 'stripe', error.provider
    assert_equal 'invalid_event', error.event
    assert_match(/Unknown event/, error.message)
    assert_match(/invalid_event/, error.message)
    assert_match(/stripe/, error.message)
  end

  def test_invalid_payload_error_stores_validation_errors
    error = Hooksmith::InvalidPayloadError.new(
      'Validation failed',
      provider: :stripe,
      event: :charge_succeeded,
      validation_errors: ['Missing field: id', 'Invalid amount']
    )

    assert_equal 'stripe', error.provider
    assert_equal 'charge_succeeded', error.event
    assert_equal ['Missing field: id', 'Invalid amount'], error.validation_errors
    assert_equal 'Validation failed', error.message
  end

  def test_persistence_error_stores_original_error
    original = StandardError.new('database error')
    error = Hooksmith::PersistenceError.new(
      'Failed to save',
      provider: :stripe,
      event: :charge_succeeded,
      original_error: original
    )

    assert_equal 'stripe', error.provider
    assert_equal 'charge_succeeded', error.event
    assert_equal original, error.original_error
    assert_equal 'Failed to save', error.message
  end

  def test_configuration_error
    error = Hooksmith::ConfigurationError.new('Invalid configuration')
    assert_instance_of Hooksmith::ConfigurationError, error
    assert_equal 'Invalid configuration', error.message
  end

  def test_all_errors_inherit_from_hooksmith_error
    assert Hooksmith::VerificationError < Hooksmith::Error
    assert Hooksmith::NoProcessorError < Hooksmith::Error
    assert Hooksmith::MultipleProcessorsError < Hooksmith::Error
    assert Hooksmith::ProcessorError < Hooksmith::Error
    assert Hooksmith::UnknownEventError < Hooksmith::Error
    assert Hooksmith::InvalidPayloadError < Hooksmith::Error
    assert Hooksmith::PersistenceError < Hooksmith::Error
    assert Hooksmith::ConfigurationError < Hooksmith::Error
  end

  def test_can_rescue_all_hooksmith_errors
    errors = [
      Hooksmith::VerificationError.new,
      Hooksmith::NoProcessorError.new(:p, :e),
      Hooksmith::MultipleProcessorsError.new(:p, :e, {}),
      Hooksmith::ProcessorError.new('msg', provider: :p, event: :e, processor_class: 'C'),
      Hooksmith::UnknownEventError.new(:p, :e),
      Hooksmith::InvalidPayloadError.new,
      Hooksmith::PersistenceError.new,
      Hooksmith::ConfigurationError.new
    ]

    errors.each do |error|
      assert_kind_of Hooksmith::Error, error
    end
  end
end
