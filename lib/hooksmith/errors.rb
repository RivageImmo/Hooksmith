# frozen_string_literal: true

module Hooksmith
  # Base error class for all Hooksmith errors.
  class Error < StandardError; end

  # Raised when webhook request verification fails.
  #
  # This error is raised by verifiers when the incoming request
  # does not pass authentication checks.
  #
  # @example Raising a verification error
  #   raise Hooksmith::VerificationError, 'Invalid signature'
  #
  # @example Raising with additional context
  #   raise Hooksmith::VerificationError.new('Signature mismatch', provider: 'stripe')
  #
  class VerificationError < Error
    # @return [String, nil] the provider name
    attr_reader :provider
    # @return [String, nil] the reason for verification failure
    attr_reader :reason

    # Initializes a new VerificationError.
    #
    # @param message [String] the error message
    # @param provider [String, nil] the provider name
    # @param reason [String, nil] additional reason for failure
    def initialize(message = 'Webhook verification failed', provider: nil, reason: nil)
      @provider = provider
      @reason = reason
      super(message)
    end
  end

  # Raised when no processor is registered for an event.
  class NoProcessorError < Error
    # @return [String] the provider name
    attr_reader :provider
    # @return [String] the event name
    attr_reader :event

    # Initializes a new NoProcessorError.
    #
    # @param provider [String] the provider name
    # @param event [String] the event name
    def initialize(provider, event)
      @provider = provider.to_s
      @event = event.to_s
      super("No processor registered for #{@provider} event #{@event}")
    end
  end

  # Raised when a processor encounters an error during processing.
  class ProcessorError < Error
    # @return [String] the provider name
    attr_reader :provider
    # @return [String] the event name
    attr_reader :event
    # @return [String] the processor class name
    attr_reader :processor_class
    # @return [Exception] the original exception
    attr_reader :original_error

    # Initializes a new ProcessorError.
    #
    # @param message [String] the error message
    # @param provider [String] the provider name
    # @param event [String] the event name
    # @param processor_class [String] the processor class name
    # @param original_error [Exception] the original exception
    def initialize(message, provider:, event:, processor_class:, original_error: nil)
      @provider = provider.to_s
      @event = event.to_s
      @processor_class = processor_class.to_s
      @original_error = original_error
      super(message)
    end
  end

  # Raised when the event name is not recognized or invalid.
  class UnknownEventError < Error
    # @return [String] the provider name
    attr_reader :provider
    # @return [String] the event name
    attr_reader :event

    # Initializes a new UnknownEventError.
    #
    # @param provider [String] the provider name
    # @param event [String] the event name
    def initialize(provider, event)
      @provider = provider.to_s
      @event = event.to_s
      super("Unknown event '#{@event}' for provider '#{@provider}'")
    end
  end
end
