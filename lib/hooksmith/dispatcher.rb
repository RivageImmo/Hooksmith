# frozen_string_literal: true

module Hooksmith
  # Dispatcher routes incoming webhook payloads to the appropriate processor.
  #
  # Uses string keys internally to prevent Symbol DoS attacks when processing
  # untrusted webhook input from external sources.
  #
  # @example Dispatch a webhook event:
  #   Hooksmith::Dispatcher.new(provider: :stripe, event: :charge_succeeded, payload: payload).run!
  #
  class Dispatcher
    # @return [String] the provider name
    attr_reader :provider
    # @return [String] the event name
    attr_reader :event
    # @return [Hash] the webhook payload
    attr_reader :payload

    # Initializes a new Dispatcher.
    #
    # @param provider [Symbol, String] the provider (e.g., :stripe)
    # @param event [Symbol, String] the event (e.g., :charge_succeeded)
    # @param payload [Hash] the webhook payload data.
    def initialize(provider:, event:, payload:)
      @provider = provider.to_s
      @event    = event.to_s
      @payload  = payload
    end

    # Runs the dispatcher.
    #
    # Instantiates each processor registered for the given provider and event,
    # then selects the ones that can handle the payload using the can_handle? method.
    # - If no processors qualify, logs a warning.
    # - If more than one qualifies, raises MultipleProcessorsError.
    # - Otherwise, processes the event with the single matching processor.
    #
    # @raise [MultipleProcessorsError] if multiple processors qualify.
    def run!
      # Optionally record the incoming event before processing.
      Hooksmith::EventRecorder.record!(provider: @provider, event: @event, payload: @payload, timing: :before)

      # Fetch all processors registered for this provider and event.
      entries = Hooksmith.configuration.processors_for(@provider, @event)

      # Instantiate each processor and filter by condition.
      matching_processors = entries.map do |entry|
        processor = Object.const_get(entry[:processor]).new(@payload)
        processor if processor.can_handle?(@payload)
      end.compact

      if matching_processors.empty?
        Hooksmith.logger.warn("No processor registered for #{@provider} event #{@event} could handle the payload")
        return
      end

      # If more than one processor qualifies, raise an error.
      raise MultipleProcessorsError.new(@provider, @event, @payload) if matching_processors.size > 1

      # Exactly one matching processor.
      result = matching_processors.first.process!

      # Optionally record the event after successful processing.
      Hooksmith::EventRecorder.record!(provider: @provider, event: @event, payload: @payload, timing: :after)

      result
    rescue StandardError => e
      Hooksmith.logger.error("Error processing #{@provider} event #{@event}: #{e.message}")
      raise e
    end
  end

  # Raised when multiple processors can handle the same event.
  #
  # This error intentionally does not include the full payload in the message
  # to prevent PII exposure in logs and error tracking systems.
  class MultipleProcessorsError < StandardError
    # @return [String] the provider name
    attr_reader :provider
    # @return [String] the event name
    attr_reader :event
    # @return [Integer] the number of bytes in the payload (for debugging)
    attr_reader :payload_size

    # Initializes the error with details about the provider and event.
    #
    # @param provider [String] the provider name.
    # @param event [String] the event name.
    # @param payload [Hash] the webhook payload (not included in message to prevent PII exposure).
    def initialize(provider, event, payload)
      @provider = provider.to_s
      @event = event.to_s
      @payload_size = payload.to_s.bytesize
      super("Multiple processors found for #{@provider} event #{@event} (payload_size=#{@payload_size} bytes)")
    end
  end
end
