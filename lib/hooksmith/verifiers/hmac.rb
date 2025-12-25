# frozen_string_literal: true

require 'openssl'
require 'base64'

module Hooksmith
  module Verifiers
    # HMAC-based webhook signature verifier.
    #
    # This verifier validates webhook requests using HMAC signatures,
    # which is a common authentication method used by providers like
    # Stripe, GitHub, Shopify, and many others.
    #
    # @example Basic HMAC verification
    #   verifier = Hooksmith::Verifiers::Hmac.new(
    #     secret: ENV['WEBHOOK_SECRET'],
    #     header: 'X-Signature'
    #   )
    #
    # @example HMAC with timestamp validation (like Stripe)
    #   verifier = Hooksmith::Verifiers::Hmac.new(
    #     secret: ENV['STRIPE_WEBHOOK_SECRET'],
    #     header: 'Stripe-Signature',
    #     timestamp_options: { header: 'Stripe-Signature', tolerance: 300 }
    #   )
    #
    # @example HMAC with custom signature format
    #   verifier = Hooksmith::Verifiers::Hmac.new(
    #     secret: ENV['WEBHOOK_SECRET'],
    #     header: 'X-Hub-Signature-256',
    #     algorithm: 'sha256',
    #     signature_prefix: 'sha256='
    #   )
    #
    class Hmac < Base
      # Supported HMAC algorithms
      ALGORITHMS = %w[sha1 sha256 sha384 sha512].freeze

      # Default signature encoding
      DEFAULT_ENCODING = :hex

      # Initializes the HMAC verifier.
      #
      # @param secret [String] the shared secret key
      # @param header [String] the header containing the signature
      # @param algorithm [String] the HMAC algorithm (sha1, sha256, sha384, sha512)
      # @param encoding [Symbol] the signature encoding (:hex or :base64)
      # @param signature_prefix [String, nil] prefix to strip from signature (e.g., 'sha256=')
      # @param timestamp_options [Hash] timestamp validation options
      # @option timestamp_options [String] :header header containing the timestamp
      # @option timestamp_options [Integer] :tolerance max age of request in seconds (default: 300)
      # @option timestamp_options [Symbol] :format timestamp format (:unix or :iso8601)
      def initialize(secret:, header:, **options)
        super(**options.except(:algorithm, :encoding, :signature_prefix, :timestamp_options))
        @secret = secret
        @header = header
        @algorithm = validate_algorithm(options.fetch(:algorithm, 'sha256'))
        @encoding = options.fetch(:encoding, DEFAULT_ENCODING)
        @signature_prefix = options[:signature_prefix]
        configure_timestamp_options(options[:timestamp_options])
      end

      # Verifies the HMAC signature of the request.
      #
      # @param request [Hooksmith::Request] the incoming request
      # @raise [Hooksmith::VerificationError] if verification fails
      # @return [void]
      def verify!(request)
        signature = extract_signature(request)
        raise VerificationError.new('Missing signature header', reason: 'missing_signature') if signature.nil?

        verify_timestamp!(request) if @timestamp_header

        expected = compute_signature(request.body)

        return if secure_compare(expected, signature)

        raise VerificationError.new('Invalid signature', reason: 'signature_mismatch')
      end

      # Returns whether the verifier is properly configured.
      #
      # @return [Boolean] true if secret and header are present
      def enabled?
        !@secret.nil? && !@secret.empty? && !@header.nil? && !@header.empty?
      end

      private

      # Configures timestamp validation options.
      #
      # @param timestamp_options [Hash, nil] timestamp options hash
      def configure_timestamp_options(timestamp_options)
        return unless timestamp_options

        @timestamp_header = timestamp_options[:header]
        @timestamp_tolerance = timestamp_options.fetch(:tolerance, 300)
        @timestamp_format = timestamp_options.fetch(:format, :unix)
      end

      # Validates the HMAC algorithm.
      #
      # @param algorithm [String] the algorithm name
      # @return [String] the validated algorithm
      # @raise [ArgumentError] if the algorithm is not supported
      def validate_algorithm(algorithm)
        algo = algorithm.to_s.downcase
        unless ALGORITHMS.include?(algo)
          raise ArgumentError, "Unsupported algorithm: #{algorithm}. Supported: #{ALGORITHMS.join(', ')}"
        end

        algo
      end

      # Extracts the signature from the request headers.
      #
      # @param request [Hooksmith::Request] the incoming request
      # @return [String, nil] the extracted signature
      def extract_signature(request)
        raw_signature = request.header(@header)
        return nil if raw_signature.nil? || raw_signature.empty?

        signature = raw_signature.to_s
        signature = signature.sub(/\A#{Regexp.escape(@signature_prefix)}/, '') if @signature_prefix
        signature.strip
      end

      # Computes the expected HMAC signature for the body.
      #
      # @param body [String] the request body
      # @return [String] the computed signature
      def compute_signature(body)
        digest = OpenSSL::HMAC.digest(@algorithm, @secret, body)

        case @encoding
        when :base64
          Base64.strict_encode64(digest)
        else
          digest.unpack1('H*')
        end
      end

      # Verifies the timestamp is within tolerance.
      #
      # @param request [Hooksmith::Request] the incoming request
      # @raise [Hooksmith::VerificationError] if timestamp is invalid or expired
      def verify_timestamp!(request)
        timestamp_value = request.header(@timestamp_header)
        raise VerificationError.new('Missing timestamp header', reason: 'missing_timestamp') if timestamp_value.nil?

        timestamp = parse_timestamp(timestamp_value)
        raise VerificationError.new('Invalid timestamp format', reason: 'invalid_timestamp') if timestamp.nil?

        age = (Time.now - timestamp).abs
        return unless age > @timestamp_tolerance

        raise VerificationError.new(
          "Request timestamp too old (#{age.to_i}s > #{@timestamp_tolerance}s)",
          reason: 'timestamp_expired'
        )
      end

      # Parses a timestamp value.
      #
      # @param value [String] the timestamp value
      # @return [Time, nil] the parsed time or nil if invalid
      def parse_timestamp(value)
        case @timestamp_format
        when :iso8601
          Time.iso8601(value)
        else
          Time.at(value.to_i)
        end
      rescue ArgumentError, TypeError
        nil
      end

      # Performs a constant-time string comparison to prevent timing attacks.
      #
      # @param expected [String] expected string
      # @param actual [String] actual string
      # @return [Boolean] true if strings are equal
      def secure_compare(expected, actual)
        return false if expected.nil? || actual.nil?
        return false if expected.bytesize != actual.bytesize

        # Use OpenSSL's secure comparison if available (Ruby 2.5+)
        if OpenSSL.respond_to?(:secure_compare)
          OpenSSL.secure_compare(expected, actual)
        else
          # Fallback to manual constant-time comparison
          left = expected.unpack('C*')
          right = actual.unpack('C*')
          result = 0
          left.zip(right) { |x, y| result |= x ^ y }
          result.zero?
        end
      end
    end
  end
end
