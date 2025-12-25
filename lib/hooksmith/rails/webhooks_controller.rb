# frozen_string_literal: true

module Hooksmith
  module Rails
    # A concern for Rails controllers that handle webhooks.
    #
    # This concern provides standardized webhook handling with:
    # - Automatic request verification (if configured)
    # - Consistent response codes (200 for success, 400 for bad request, 500 for errors)
    # - Error logging and instrumentation
    # - Skip CSRF protection for webhook endpoints
    #
    # @example Basic usage
    #   class WebhooksController < ApplicationController
    #     include Hooksmith::Rails::WebhooksController
    #
    #     def stripe
    #       handle_webhook(provider: 'stripe', event: params[:type], payload: params.to_unsafe_h)
    #     end
    #   end
    #
    # @example With custom error handling
    #   class WebhooksController < ApplicationController
    #     include Hooksmith::Rails::WebhooksController
    #
    #     def stripe
    #       handle_webhook(provider: 'stripe', event: params[:type], payload: params.to_unsafe_h) do |result|
    #         # Custom success handling
    #         render json: { processed: true, result: result }
    #       end
    #     rescue Hooksmith::VerificationError => e
    #       render json: { error: 'Invalid signature' }, status: :unauthorized
    #     end
    #   end
    #
    # @example Async processing with ActiveJob
    #   class WebhooksController < ApplicationController
    #     include Hooksmith::Rails::WebhooksController
    #
    #     def stripe
    #       handle_webhook_async(provider: 'stripe', event: params[:type], payload: params.to_unsafe_h)
    #     end
    #   end
    #
    module WebhooksController
      extend ActiveSupport::Concern

      included do
        skip_before_action :verify_authenticity_token, raise: false
        before_action :verify_webhook_signature, if: :hooksmith_verification_enabled?
      end

      # Handles a webhook synchronously.
      #
      # @param provider [String, Symbol] the webhook provider
      # @param event [String, Symbol] the event type
      # @param payload [Hash] the webhook payload
      # @yield [result] optional block for custom success handling
      # @yieldparam result [Object] the result from the processor
      # @return [void]
      def handle_webhook(provider:, event:, payload:)
        result = Hooksmith::Dispatcher.new(provider:, event:, payload:).run!

        if block_given?
          yield(result)
        else
          head :ok
        end
      rescue Hooksmith::MultipleProcessorsError => e
        Hooksmith.logger.error("Webhook error: #{e.message}")
        head :internal_server_error
      rescue StandardError => e
        Hooksmith.logger.error("Webhook processing failed: #{e.message}")
        head :internal_server_error
      end

      # Handles a webhook asynchronously using ActiveJob.
      #
      # Requires Hooksmith::Jobs::DispatcherJob to be available.
      #
      # @param provider [String, Symbol] the webhook provider
      # @param event [String, Symbol] the event type
      # @param payload [Hash] the webhook payload
      # @param queue [Symbol, String] the queue to use (default: :default)
      # @return [void]
      def handle_webhook_async(provider:, event:, payload:, queue: :default)
        unless defined?(Hooksmith::Jobs::DispatcherJob)
          raise 'Hooksmith::Jobs::DispatcherJob is not available. Ensure ActiveJob is loaded.'
        end

        Hooksmith::Jobs::DispatcherJob.set(queue:).perform_later(
          provider: provider.to_s,
          event: event.to_s,
          payload: payload.as_json
        )

        head :ok
      end

      private

      # Verifies the webhook signature using the provider's configured verifier.
      #
      # Override this method to customize verification behavior.
      #
      # @return [void]
      # @raise [Hooksmith::VerificationError] if verification fails
      def verify_webhook_signature
        provider = hooksmith_provider_name
        return unless provider

        verifier = Hooksmith.configuration.verifier_for(provider)
        return unless verifier&.enabled?

        hooksmith_request = Hooksmith::Request.new(
          headers: request.headers.to_h,
          body: request.raw_post
        )

        verifier.verify!(hooksmith_request)
      rescue Hooksmith::VerificationError => e
        Hooksmith.logger.warn("Webhook verification failed for #{provider}: #{e.message}")
        head :unauthorized
      end

      # Returns the provider name for the current action.
      #
      # Override this method to customize provider detection.
      # By default, uses the action name.
      #
      # @return [String, nil] the provider name
      def hooksmith_provider_name
        action_name
      end

      # Checks if webhook verification is enabled for the current provider.
      #
      # Override this method to customize when verification runs.
      #
      # @return [Boolean] true if verification should run
      def hooksmith_verification_enabled?
        return false unless Hooksmith.configuration.respond_to?(:verifier_for)

        provider = hooksmith_provider_name
        return false unless provider

        verifier = Hooksmith.configuration.verifier_for(provider)
        verifier&.enabled? || false
      end
    end
  end
end
