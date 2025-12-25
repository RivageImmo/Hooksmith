# frozen_string_literal: true

module Hooksmith
  # Provides idempotency support for webhook processing.
  #
  # Idempotency ensures that processing the same webhook multiple times
  # (due to retries, network issues, etc.) produces the same result and
  # doesn't cause duplicate side effects.
  #
  # @example Configure idempotency key extraction
  #   Hooksmith.configure do |config|
  #     config.provider(:stripe) do |stripe|
  #       stripe.idempotency_key = ->(payload) { payload['id'] }
  #       stripe.register(:charge_succeeded, 'StripeChargeProcessor')
  #     end
  #   end
  #
  # @example Check if event was already processed
  #   key = Hooksmith::Idempotency.extract_key(provider: :stripe, payload: payload)
  #   if Hooksmith::Idempotency.already_processed?(provider: :stripe, key: key)
  #     return # Skip duplicate
  #   end
  #
  module Idempotency
    module_function

    # Extracts an idempotency key from a webhook payload.
    #
    # @param provider [Symbol, String] the provider name
    # @param payload [Hash] the webhook payload
    # @return [String, nil] the idempotency key or nil if not configured
    def extract_key(provider:, payload:)
      extractor = Hooksmith.configuration.idempotency_key_for(provider)
      return nil unless extractor

      key = extractor.call(payload)
      key&.to_s
    rescue StandardError => e
      Hooksmith.logger.error("Failed to extract idempotency key for #{provider}: #{e.message}")
      nil
    end

    # Checks if an event with the given idempotency key was already processed.
    #
    # This requires the event store to be enabled and the model to respond to
    # `exists_with_idempotency_key?` or have a `find_by_idempotency_key` method.
    #
    # @param provider [Symbol, String] the provider name
    # @param key [String] the idempotency key
    # @return [Boolean] true if already processed
    def already_processed?(provider:, key:)
      return false if key.nil?

      config = Hooksmith.configuration.event_store_config
      return false unless config.enabled

      model_class = config.model_class
      return false unless model_class

      check_duplicate(model_class, provider.to_s, key)
    rescue StandardError => e
      Hooksmith.logger.error("Failed to check idempotency for #{provider}: #{e.message}")
      false
    end

    # Generates a composite idempotency key from multiple fields.
    #
    # @param fields [Array<String, Symbol, nil>] the fields to combine
    # @param separator [String] the separator between fields
    # @return [String] the composite key
    def composite_key(*fields, separator: ':')
      fields.compact.map(&:to_s).join(separator)
    end

    # Common idempotency key extractors for popular webhook providers.
    module Extractors
      # Stripe uses the event ID as the idempotency key.
      STRIPE = ->(payload) { payload['id'] || payload[:id] }

      # GitHub uses the delivery ID header (must be passed in payload).
      GITHUB = ->(payload) { payload['delivery_id'] || payload[:delivery_id] }

      # Generic extractor that looks for common ID fields.
      GENERIC = lambda do |payload|
        payload['id'] || payload[:id] ||
          payload['event_id'] || payload[:event_id] ||
          payload['webhook_id'] || payload[:webhook_id]
      end
    end

    class << self
      private

      def check_duplicate(model_class, provider, key)
        if model_class.respond_to?(:exists_with_idempotency_key?)
          model_class.exists_with_idempotency_key?(provider:, idempotency_key: key)
        elsif model_class.respond_to?(:find_by_idempotency_key)
          !model_class.find_by_idempotency_key(provider:, idempotency_key: key).nil?
        elsif model_class.respond_to?(:exists?)
          model_class.exists?(provider:, idempotency_key: key)
        else
          false
        end
      end
    end
  end
end
