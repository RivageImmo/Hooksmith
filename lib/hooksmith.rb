# frozen_string_literal: true

require 'hooksmith/version'
require 'hooksmith/errors'
require 'hooksmith/configuration'
require 'hooksmith/config/provider'
require 'hooksmith/config/event_store'
require 'hooksmith/request'
require 'hooksmith/dispatcher'
require 'hooksmith/logger'
require 'hooksmith/event_recorder'
require 'hooksmith/idempotency'
require 'hooksmith/processor/base'
require 'hooksmith/jobs/dispatcher_job' if defined?(ActiveJob)
require 'hooksmith/verifiers/base'
require 'hooksmith/verifiers/hmac'
require 'hooksmith/verifiers/bearer_token'
require 'hooksmith/railtie' if defined?(Rails)

# Main entry point for the Hooksmith gem.
#
# @example Basic usage:
#   Hooksmith.configure do |config|
#     config.provider(:stripe) do |stripe|
#       stripe.register(:charge_succeeded, MyStripeProcessor)
#     end
#   end
#
#   Hooksmith::Dispatcher.new(provider: :stripe, event: :charge_succeeded, payload: payload).run!
#
# @example With request verification:
#   Hooksmith.configure do |config|
#     config.provider(:stripe) do |stripe|
#       stripe.verifier = Hooksmith::Verifiers::Hmac.new(
#         secret: ENV['STRIPE_WEBHOOK_SECRET'],
#         header: 'Stripe-Signature'
#       )
#       stripe.register(:charge_succeeded, MyStripeProcessor)
#     end
#   end
#
#   # In your controller:
#   request = Hooksmith::Request.new(headers: request.headers, body: request.raw_post)
#   Hooksmith.verify!(provider: :stripe, request: request)
#   Hooksmith::Dispatcher.new(provider: :stripe, event: event, payload: payload).run!
#
module Hooksmith
  # Returns the configuration instance.
  # @return [Configuration] the configuration instance.
  def self.configuration
    @configuration ||= Configuration.new
  end

  # Yields the configuration to a block.
  # @yieldparam config [Configuration]
  def self.configure
    yield(configuration)
  end

  # Returns the gem's logger instance.
  # @return [Logger] the logger instance.
  def self.logger
    Logger.instance
  end

  # Verifies an incoming webhook request for a provider.
  #
  # @param provider [Symbol, String] the provider name
  # @param request [Hooksmith::Request] the incoming request
  # @raise [Hooksmith::VerificationError] if verification fails
  # @return [void]
  def self.verify!(provider:, request:)
    verifier = configuration.verifier_for(provider)
    return unless verifier&.enabled?

    verifier.verify!(request)
  end

  # Checks if a provider has a verifier configured.
  #
  # @param provider [Symbol, String] the provider name
  # @return [Boolean] true if a verifier is configured
  def self.verifier_configured?(provider)
    verifier = configuration.verifier_for(provider)
    verifier&.enabled? || false
  end
end
