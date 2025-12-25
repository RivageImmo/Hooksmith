# frozen_string_literal: true

module Hooksmith
  # Wrapper for incoming webhook request data.
  #
  # This class provides a consistent interface for accessing request data
  # regardless of the underlying web framework (Rails, Rack, etc.).
  #
  # @example Creating a request from Rails controller
  #   request = Hooksmith::Request.new(
  #     headers: request.headers.to_h,
  #     body: request.raw_post,
  #     method: request.request_method,
  #     path: request.path
  #   )
  #
  # @example Creating a request from Rack env
  #   request = Hooksmith::Request.from_rack_env(env)
  #
  class Request
    # @return [Hash] the request headers
    attr_reader :headers
    # @return [String] the raw request body
    attr_reader :body
    # @return [String] the HTTP method (GET, POST, etc.)
    attr_reader :method
    # @return [String] the request path
    attr_reader :path
    # @return [Hash] the parsed payload (optional, for convenience)
    attr_reader :payload

    # Initializes a new Request.
    #
    # @param headers [Hash] the request headers
    # @param body [String] the raw request body
    # @param method [String] the HTTP method
    # @param path [String] the request path
    # @param payload [Hash] the parsed payload (optional)
    def initialize(headers:, body:, method: 'POST', path: '/', payload: nil)
      @headers = normalize_headers(headers)
      @body = body.to_s
      @method = method.to_s.upcase
      @path = path.to_s
      @payload = payload
    end

    # Creates a Request from a Rack environment hash.
    #
    # @param env [Hash] the Rack environment
    # @return [Request] a new Request instance
    def self.from_rack_env(env)
      headers = extract_headers_from_rack(env)
      body = env['rack.input']&.read || ''
      env['rack.input']&.rewind

      new(
        headers:,
        body:,
        method: env['REQUEST_METHOD'],
        path: env['PATH_INFO']
      )
    end

    # Gets a header value by name (case-insensitive).
    #
    # @param name [String] the header name
    # @return [String, nil] the header value or nil if not found
    def header(name)
      normalized_name = normalize_header_name(name)
      @headers[normalized_name]
    end

    # Alias for {#header}.
    #
    # @param name [String] the header name
    # @return [String, nil] the header value or nil if not found
    def [](name)
      header(name)
    end

    # Extracts headers from a Rack environment hash.
    #
    # @param env [Hash] the Rack environment
    # @return [Hash] the extracted headers
    def self.extract_headers_from_rack(env)
      env.select { |k, _| k.start_with?('HTTP_') || %w[CONTENT_TYPE CONTENT_LENGTH].include?(k) }
    end
    private_class_method :extract_headers_from_rack

    private

    # Normalizes headers to use consistent key format.
    #
    # @param headers [Hash] the raw headers
    # @return [Hash] normalized headers
    def normalize_headers(headers)
      return {} unless headers.is_a?(Hash)

      headers.transform_keys { |k| normalize_header_name(k) }
    end

    # Normalizes a header name to a consistent format.
    #
    # @param name [String] the header name
    # @return [String] the normalized header name
    def normalize_header_name(name)
      name.to_s.upcase.tr('-', '_').sub(/^HTTP_/, '')
    end
  end
end
