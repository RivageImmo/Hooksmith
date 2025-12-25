# frozen_string_literal: true

module Hooksmith
  module Config
    # Provider is used internally by the DSL to collect processor registrations.
    #
    # Uses string keys internally to prevent Symbol DoS attacks when processing
    # untrusted webhook input.
    class Provider
      # @return [String] the provider name.
      attr_reader :provider
      # @return [Array<Hash>] list of entries registered.
      attr_reader :entries

      def initialize(provider)
        @provider = provider.to_s
        @entries = []
      end

      # Registers a processor for a specific event.
      #
      # @param event [Symbol, String] the event name.
      # @param processor_class_name [String] the processor class name.
      def register(event, processor_class_name)
        entries << { event: event.to_s, processor: processor_class_name }
      end
    end
  end
end
