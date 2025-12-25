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
      Hooksmith::Instrumentation.instrument('dispatch', provider: @provider, event: @event) do
        dispatch_webhook
      end
    end

    private

    def dispatch_webhook
      record_event(:before)
      matching = find_matching_processors

      return handle_no_processor if matching.empty?

      handle_multiple_processors(matching) if matching.size > 1

      execute_processor(matching.first)
    rescue Hooksmith::Error
      raise
    rescue StandardError => e
      publish_error(e)
      Hooksmith.logger.error("Error processing #{@provider} event #{@event}: #{e.message}")
      raise e
    end

    def find_matching_processors
      entries = Hooksmith.configuration.processors_for(@provider, @event)
      entries.filter_map do |entry|
        processor = Object.const_get(entry[:processor]).new(@payload)
        processor if processor.can_handle?(@payload)
      end
    end

    def handle_no_processor
      Hooksmith::Instrumentation.publish('no_processor', provider: @provider, event: @event)
      Hooksmith.logger.warn("No processor registered for #{@provider} event #{@event} could handle the payload")
      nil
    end

    def handle_multiple_processors(matching)
      processor_names = matching.map { |p| p.class.name }
      Hooksmith::Instrumentation.publish(
        'multiple_processors',
        provider: @provider, event: @event, processor_count: matching.size
      )
      raise MultipleProcessorsError.new(@provider, @event, @payload, processor_names:)
    end

    def execute_processor(processor)
      result = Hooksmith::Instrumentation.instrument(
        'process',
        provider: @provider, event: @event, processor: processor.class.name
      ) { processor.process! }

      record_event(:after)
      result
    end

    def record_event(timing)
      Hooksmith::EventRecorder.record!(provider: @provider, event: @event, payload: @payload, timing:)
    end

    def publish_error(error)
      Hooksmith::Instrumentation.publish(
        'error',
        provider: @provider, event: @event, error: error.message, error_class: error.class.name
      )
    end
  end
end
