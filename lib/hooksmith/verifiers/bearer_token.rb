# frozen_string_literal: true

require 'openssl'

module Hooksmith
  module Verifiers
    # Bearer token webhook verifier.
    #
    # This verifier validates webhook requests using a simple bearer token
    # in the Authorization header or a custom header.
    #
    # @example Basic bearer token verification
    #   verifier = Hooksmith::Verifiers::BearerToken.new(
    #     token: ENV['WEBHOOK_TOKEN']
    #   )
    #
    # @example Custom header
    #   verifier = Hooksmith::Verifiers::BearerToken.new(
    #     token: ENV['WEBHOOK_TOKEN'],
    #     header: 'X-Webhook-Token'
    #   )
    #
    class BearerToken < Base
      # Default header for bearer tokens
      DEFAULT_HEADER = 'Authorization'

      # Initializes the bearer token verifier.
      #
      # @param token [String] the expected token value
      # @param header [String] the header containing the token (default: Authorization)
      # @param strip_bearer_prefix [Boolean] whether to strip 'Bearer ' prefix (default: true)
      def initialize(token:, header: DEFAULT_HEADER, strip_bearer_prefix: true, **options)
        super(**options)
        @token = token
        @header = header
        @strip_bearer_prefix = strip_bearer_prefix
      end

      # Verifies the bearer token in the request.
      #
      # @param request [Hooksmith::Request] the incoming request
      # @raise [Hooksmith::VerificationError] if verification fails
      # @return [void]
      def verify!(request)
        provided_token = extract_token(request)

        if provided_token.nil? || provided_token.empty?
          raise VerificationError.new('Missing authentication token', reason: 'missing_token')
        end

        return if secure_compare(@token, provided_token)

        raise VerificationError.new('Invalid authentication token', reason: 'invalid_token')
      end

      # Returns whether the verifier is properly configured.
      #
      # @return [Boolean] true if token is present
      def enabled?
        !@token.nil? && !@token.empty?
      end

      private

      # Extracts the token from the request headers.
      #
      # @param request [Hooksmith::Request] the incoming request
      # @return [String, nil] the extracted token
      def extract_token(request)
        raw_token = request.header(@header)
        return nil if raw_token.nil?

        token = raw_token.to_s.strip
        token = token.sub(/\ABearer\s+/i, '') if @strip_bearer_prefix
        token.empty? ? nil : token
      end
    end
  end
end
