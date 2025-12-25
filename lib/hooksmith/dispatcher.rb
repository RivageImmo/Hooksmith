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
    # - If no processors qualify, logs a warning (or raises NoProcessorError in strict mode).
    # - If more than one qualifies, raises MultipleProcessorsError.
    # - Otherwise, processes the event with the single matching processor.
    #
    # @raise [Hooksmith::MultipleProcessorsError] if multiple processors qualify.
    # @raise [Hooksmith::NoProcessorError] if no processors qualify (strict mode only).
    # @raise [Hooksmith::ProcessorError] if the processor raises an error.
    # @return [Object, nil] the result of the processor, or nil if no processor matched.
    def run!
      Hooksmith::EventRecorder.record!(provider: @provider, event: @event, payload: @payload, timing: :before)

      entries = Hooksmith.configuration.processors_for(@provider, @event)
      matching = find_matching_processors(entries)

      if matching.empty?
        handle_no_processor
        return
      end

      if matching.size > 1
        processor_names = matching.map { |p| p.class.name }
        raise MultipleProcessorsError.new(@provider, @event, @payload, processor_names:)
      end

      execute_processor(matching.first)
    rescue Hooksmith::Error
      raise
    rescue StandardError => e
      Hooksmith.logger.error("Error processing #{@provider} event #{@event}: #{e.message}")
      raise e
    end

    private

    # Finds all processors that can handle the current payload.
    #
    # @param entries [Array<Hash>] the registered processor entries
    # @return [Array<Hooksmith::Processor::Base>] matching processors
    def find_matching_processors(entries)
      entries.filter_map do |entry|
        processor = Object.const_get(entry[:processor]).new(@payload)
        processor if processor.can_handle?(@payload)
      end
    end

    # Handles the case when no processor matches.
    #
    # @raise [Hooksmith::NoProcessorError] if strict mode is enabled
    def handle_no_processor
      Hooksmith.logger.warn("No processor registered for #{@provider} event #{@event} could handle the payload")
    end

    # Executes a single processor and records the event.
    #
    # @param processor [Hooksmith::Processor::Base] the processor to execute
    # @return [Object] the result of the processor
    def execute_processor(processor)
      result = processor.process!
      Hooksmith::EventRecorder.record!(provider: @provider, event: @event, payload: @payload, timing: :after)
      result
    end
  end
end
