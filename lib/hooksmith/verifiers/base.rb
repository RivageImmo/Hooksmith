# frozen_string_literal: true

module Hooksmith
  module Verifiers
    # Base class for webhook request verifiers.
    #
    # Verifiers are responsible for authenticating incoming webhook requests
    # before they are processed. Each provider can have its own verifier
    # configured to handle provider-specific authentication schemes.
    #
    # @abstract Subclass and override {#verify!} to implement custom verification.
    #
    # @example Creating a custom verifier
    #   class MyCustomVerifier < Hooksmith::Verifiers::Base
    #     def verify!(request)
    #       token = request.headers['X-Custom-Token']
    #       raise Hooksmith::VerificationError, 'Invalid token' unless valid_token?(token)
    #     end
    #
    #     private
    #
    #     def valid_token?(token)
    #       token == @options[:expected_token]
    #     end
    #   end
    #
    class Base
      # @return [Hash] options passed to the verifier
      attr_reader :options

      # Initializes the verifier with options.
      #
      # @param options [Hash] verifier-specific options
      def initialize(**options)
        @options = options
      end

      # Verifies the incoming webhook request.
      #
      # @param request [Hooksmith::Request] the incoming request to verify
      # @raise [Hooksmith::VerificationError] if verification fails
      # @return [void]
      def verify!(request)
        raise NotImplementedError, 'Subclasses must implement #verify!'
      end

      # Returns whether the verifier is configured and should be used.
      #
      # @return [Boolean] true if the verifier should be applied
      def enabled?
        true
      end
    end
  end
end
