# frozen_string_literal: true

module Hooksmith
  module Jobs
    # ActiveJob for asynchronous webhook processing.
    #
    # This job wraps the Dispatcher to process webhooks in the background,
    # allowing your webhook endpoint to respond quickly while processing
    # happens asynchronously.
    #
    # @example Basic usage in a controller
    #   class WebhooksController < ApplicationController
    #     def stripe
    #       Hooksmith::Jobs::DispatcherJob.perform_later(
    #         provider: 'stripe',
    #         event: params[:type],
    #         payload: params.to_unsafe_h
    #       )
    #       head :ok
    #     end
    #   end
    #
    # @example With custom queue
    #   Hooksmith::Jobs::DispatcherJob.set(queue: :webhooks).perform_later(...)
    #
    # @example With retry configuration (in your application)
    #   # config/initializers/hooksmith.rb
    #   Hooksmith::Jobs::DispatcherJob.retry_on StandardError, wait: :polynomially_longer, attempts: 5
    #
    class DispatcherJob < ActiveJob::Base
      queue_as :default

      # Performs the webhook dispatch asynchronously.
      #
      # @param provider [String, Symbol] the webhook provider name
      # @param event [String, Symbol] the event type
      # @param payload [Hash] the webhook payload
      # @param options [Hash] additional options
      # @option options [Boolean] :skip_idempotency_check (false) skip duplicate checking
      # @return [Object] the result from the processor
      def perform(provider:, event:, payload:, **options)
        provider = provider.to_s
        event = event.to_s

        if check_idempotency?(options)
          key = Hooksmith::Idempotency.extract_key(provider:, payload:)
          if key && Hooksmith::Idempotency.already_processed?(provider:, key:)
            Hooksmith.logger.info("Skipping duplicate webhook: #{provider}/#{event} (key=#{key})")
            return nil
          end
        end

        Hooksmith::Dispatcher.new(provider:, event:, payload:).run!
      end

      private

      def check_idempotency?(options)
        !options[:skip_idempotency_check]
      end
    end
  end
end
