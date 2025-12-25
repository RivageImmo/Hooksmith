# frozen_string_literal: true

module Hooksmith
  # Base error class for all Hooksmith errors.
  #
  # All Hooksmith errors inherit from this class, allowing you to rescue
  # all Hooksmith-related errors with a single rescue clause.
  #
  # @example Rescuing all Hooksmith errors
  #   begin
  #     Hooksmith::Dispatcher.new(...).run!
  #   rescue Hooksmith::Error => e
  #     logger.error("Hooksmith error: #{e.message}")
  #   end
  #
  class Error < StandardError
    # @return [String, nil] the provider name
    attr_reader :provider
    # @return [String, nil] the event name
    attr_reader :event

    # Initializes a new Error.
    #
    # @param message [String] the error message
    # @param provider [String, Symbol, nil] the provider name
    # @param event [String, Symbol, nil] the event name
    def initialize(message = nil, provider: nil, event: nil)
      @provider = provider&.to_s
      @event = event&.to_s
      super(message)
    end
  end

  # Raised when webhook request verification fails.
  #
  # This error is raised by verifiers when the incoming request
  # does not pass authentication checks.
  #
  # @example Raising a verification error
  #   raise Hooksmith::VerificationError, 'Invalid signature'
  #
  # @example Raising with additional context
  #   raise Hooksmith::VerificationError.new('Signature mismatch', provider: 'stripe', reason: 'invalid_hmac')
  #
  class VerificationError < Error
    # @return [String, nil] the reason for verification failure
    attr_reader :reason

    # Initializes a new VerificationError.
    #
    # @param message [String] the error message
    # @param provider [String, nil] the provider name
    # @param event [String, nil] the event name
    # @param reason [String, nil] additional reason for failure
    def initialize(message = 'Webhook verification failed', provider: nil, event: nil, reason: nil)
      @reason = reason
      super(message, provider:, event:)
    end
  end

  # Raised when no processor is registered for an event.
  #
  # This error can be raised when strict mode is enabled and no processor
  # is found for a given provider/event combination.
  #
  # @example
  #   raise Hooksmith::NoProcessorError.new('stripe', 'unknown_event')
  #
  class NoProcessorError < Error
    # Initializes a new NoProcessorError.
    #
    # @param provider [String, Symbol] the provider name
    # @param event [String, Symbol] the event name
    def initialize(provider, event)
      super(
        "No processor registered for #{provider} event #{event}",
        provider:,
        event:
      )
    end
  end

  # Raised when multiple processors can handle the same event.
  #
  # This error is raised when more than one processor's `can_handle?`
  # method returns true for the same webhook event. Hooksmith enforces
  # exactly-one processor semantics.
  #
  # This error intentionally does not include the full payload in the message
  # to prevent PII exposure in logs and error tracking systems.
  #
  # @example
  #   raise Hooksmith::MultipleProcessorsError.new('stripe', 'charge.succeeded', payload)
  #
  class MultipleProcessorsError < Error
    # @return [Integer] the number of bytes in the payload (for debugging)
    attr_reader :payload_size
    # @return [Array<String>] the names of the matching processor classes
    attr_reader :processor_names

    # Initializes the error with details about the provider and event.
    #
    # @param provider [String, Symbol] the provider name
    # @param event [String, Symbol] the event name
    # @param payload [Hash] the webhook payload (not included in message to prevent PII exposure)
    # @param processor_names [Array<String>] the names of the matching processor classes
    def initialize(provider, event, payload, processor_names: [])
      @payload_size = payload.to_s.bytesize
      @processor_names = processor_names
      super(
        "Multiple processors found for #{provider} event #{event} (payload_size=#{@payload_size} bytes)",
        provider:,
        event:
      )
    end
  end

  # Raised when a processor encounters an error during processing.
  #
  # This error wraps the original exception and provides additional context
  # about which processor failed and for which event.
  #
  # @example
  #   raise Hooksmith::ProcessorError.new(
  #     'Payment processing failed',
  #     provider: 'stripe',
  #     event: 'charge.succeeded',
  #     processor_class: 'StripeChargeProcessor',
  #     original_error: original_exception
  #   )
  #
  class ProcessorError < Error
    # @return [String] the processor class name
    attr_reader :processor_class
    # @return [Exception, nil] the original exception
    attr_reader :original_error

    # Initializes a new ProcessorError.
    #
    # @param message [String] the error message
    # @param provider [String, Symbol] the provider name
    # @param event [String, Symbol] the event name
    # @param processor_class [String, Class] the processor class name
    # @param original_error [Exception, nil] the original exception
    def initialize(message, provider:, event:, processor_class:, original_error: nil)
      @processor_class = processor_class.to_s
      @original_error = original_error
      super(message, provider:, event:)
    end
  end

  # Raised when the event name is not recognized or invalid.
  #
  # This error can be raised when strict event validation is enabled
  # and an unknown event type is received.
  #
  # @example
  #   raise Hooksmith::UnknownEventError.new('stripe', 'invalid.event.type')
  #
  class UnknownEventError < Error
    # Initializes a new UnknownEventError.
    #
    # @param provider [String, Symbol] the provider name
    # @param event [String, Symbol] the event name
    def initialize(provider, event)
      super(
        "Unknown event '#{event}' for provider '#{provider}'",
        provider:,
        event:
      )
    end
  end

  # Raised when the payload is invalid or malformed.
  #
  # This error can be raised during payload validation when the
  # webhook data doesn't match expected schema or format.
  #
  # @example
  #   raise Hooksmith::InvalidPayloadError.new(
  #     'Missing required field: id',
  #     provider: 'stripe',
  #     event: 'charge.succeeded'
  #   )
  #
  class InvalidPayloadError < Error
    # @return [Array<String>] list of validation errors
    attr_reader :validation_errors

    # Initializes a new InvalidPayloadError.
    #
    # @param message [String] the error message
    # @param provider [String, Symbol, nil] the provider name
    # @param event [String, Symbol, nil] the event name
    # @param validation_errors [Array<String>] list of validation errors
    def initialize(message = 'Invalid webhook payload', provider: nil, event: nil, validation_errors: [])
      @validation_errors = validation_errors
      super(message, provider:, event:)
    end
  end

  # Raised when event persistence fails.
  #
  # This error is raised when the event store is configured but
  # fails to persist the webhook event.
  #
  # @example
  #   raise Hooksmith::PersistenceError.new(
  #     'Failed to save webhook event',
  #     provider: 'stripe',
  #     event: 'charge.succeeded',
  #     original_error: ActiveRecord::RecordInvalid.new(...)
  #   )
  #
  class PersistenceError < Error
    # @return [Exception, nil] the original exception
    attr_reader :original_error

    # Initializes a new PersistenceError.
    #
    # @param message [String] the error message
    # @param provider [String, Symbol, nil] the provider name
    # @param event [String, Symbol, nil] the event name
    # @param original_error [Exception, nil] the original exception
    def initialize(message = 'Failed to persist webhook event', provider: nil, event: nil, original_error: nil)
      @original_error = original_error
      super(message, provider:, event:)
    end
  end

  # Raised when configuration is invalid or incomplete.
  #
  # This error is raised during configuration validation when
  # required settings are missing or invalid.
  #
  # @example
  #   raise Hooksmith::ConfigurationError, 'Provider name cannot be blank'
  #
  class ConfigurationError < Error; end
end
