# frozen_string_literal: true

# Provides a DSL for registering webhook processors by provider and event.
#
module Hooksmith
  # Configuration holds the registry of all processors.
  class Configuration
    # @return [Hash] a registry mapping provider symbols to arrays of processor entries.
    attr_reader :registry
    # @return [Hooksmith::Config::EventStore] configuration for event persistence
    attr_reader :event_store_config

    def initialize
      # Registry structure: { provider_symbol => [{ event: event_symbol, processor: ProcessorClass }, ...] }
      @registry = Hash.new { |hash, key| hash[key] = [] }
      @event_store_config = Hooksmith::Config::EventStore.new
    end

    # Groups registrations under a specific provider.
    #
    # @param provider_name [Symbol, String] the provider name (e.g., :stripe)
    # @yield [Hooksmith::Config::Provider] a block yielding a Provider object
    def provider(provider_name)
      provider_config = Hooksmith::Config::Provider.new(provider_name)
      yield(provider_config)
      registry[provider_name.to_sym].concat(provider_config.entries)
    end

    # Direct registration of a processor.
    #
    # @param provider [Symbol, String] the provider name
    # @param event [Symbol, String] the event name
    # @param processor_class_name [String] the processor class name
    def register_processor(provider, event, processor_class_name)
      registry[provider.to_sym] << { event: event.to_sym, processor: processor_class_name }
    end

    # Returns all processor entries for a given provider and event.
    #
    # @param provider [Symbol, String] the provider name
    # @param event [Symbol, String] the event name
    # @return [Array<Hash>] the array of matching entries.
    def processors_for(provider, event)
      registry[provider.to_sym].select { |entry| entry[:event] == event.to_sym }
    end

    # Configure event store persistence.
    #
    # @yield [Hooksmith::Config::EventStore] a block yielding an EventStore object
    # @example
    #   Hooksmith.configure do |config|
    #     config.event_store do |store|
    #       store.enabled = true
    #       store.model_class_name = 'MyApp::WebhookEvent'
    #       store.record_timing = :before # or :after, or :both
    #       store.mapper = ->(provider:, event:, payload:) {
    #         now = Time.respond_to?(:current) ? Time.current : Time.now
    #         { provider:, event: event.to_s, payload:, received_at: now }
    #       }
    #     end
    #   end
    def event_store
      yield(@event_store_config)
    end
  end
end
