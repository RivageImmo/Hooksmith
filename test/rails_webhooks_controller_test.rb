# frozen_string_literal: true

require 'test_helper'

# Stub Rails dependencies for testing
module ActiveSupport
  # Stub for ActiveSupport::Concern
  module Concern
    def self.extended(base)
      base.instance_variable_set(:@_dependencies, [])
    end

    def included(base = nil, &block)
      if base.nil?
        @_included_block = block
      else
        @_dependencies.each { |dep| base.include(dep) }
        super
        base.class_eval(&@_included_block) if @_included_block
      end
    end

    def class_methods(&block)
      @_class_methods_block = block
    end
  end
end

# Stub ActionController methods
module ActionController
  # Stub for skip_before_action
  module Callbacks
    def self.included(base)
      base.extend(ClassMethods)
    end

    # Class methods for callbacks
    module ClassMethods
      def skip_before_action(*args); end
      def before_action(*args); end
    end
  end
end

# Load the controller concern after stubs
require 'hooksmith/rails/webhooks_controller'

# RailsWebhooksControllerTest tests the Hooksmith::Rails::WebhooksController concern
class RailsWebhooksControllerTest < Minitest::Test
  def setup
    Hooksmith.configuration.registry.clear
    Hooksmith.configuration.verifiers.clear
  end

  # Test processor for webhook tests
  class ::WebhookTestProcessor < Hooksmith::Processor::Base
    def can_handle?(_payload)
      true
    end

    def process!
      'webhook processed'
    end
  end

  # Test processor that raises an error
  class ::WebhookErrorProcessor < Hooksmith::Processor::Base
    def can_handle?(_payload)
      true
    end

    def process!
      raise StandardError, 'processing failed'
    end
  end

  # Mock controller class for testing
  class MockController
    include ActionController::Callbacks

    # Track method calls
    attr_accessor :rendered_status, :rendered_json, :action_name

    def initialize
      @action_name = 'stripe'
      @rendered_status = nil
      @rendered_json = nil
      @request_headers = {}
      @request_body = ''
    end

    # Include the concern methods manually since we're not in Rails
    include Hooksmith::Rails::WebhooksController

    def head(status)
      @rendered_status = status
    end

    def render(options)
      @rendered_json = options[:json]
      @rendered_status = options[:status]
    end

    def request
      @request ||= MockRequest.new(@request_headers, @request_body)
    end

    def set_request(headers:, body:)
      @request_headers = headers
      @request_body = body
      @request = nil
    end
  end

  # Mock request object
  class MockRequest
    attr_reader :headers, :raw_post

    def initialize(headers, body)
      @headers = MockHeaders.new(headers)
      @raw_post = body
    end
  end

  # Mock headers object
  class MockHeaders
    def initialize(headers)
      @headers = headers
    end

    def to_h
      @headers
    end

    def [](key)
      @headers[key]
    end
  end

  def test_handle_webhook_dispatches_to_processor
    Hooksmith.configuration.register_processor('stripe', 'charge.succeeded', 'WebhookTestProcessor')

    controller = MockController.new
    controller.handle_webhook(provider: 'stripe', event: 'charge.succeeded', payload: { id: 'evt_123' })

    assert_equal :ok, controller.rendered_status
  end

  def test_handle_webhook_returns_internal_server_error_on_exception
    Hooksmith.configuration.register_processor('stripe', 'charge.failed', 'WebhookErrorProcessor')

    controller = MockController.new
    controller.handle_webhook(provider: 'stripe', event: 'charge.failed', payload: { id: 'evt_123' })

    assert_equal :internal_server_error, controller.rendered_status
  end

  def test_handle_webhook_yields_result_when_block_given
    Hooksmith.configuration.register_processor('stripe', 'charge.succeeded', 'WebhookTestProcessor')

    controller = MockController.new
    yielded_result = nil

    controller.handle_webhook(provider: 'stripe', event: 'charge.succeeded', payload: { id: 'evt_123' }) do |result|
      yielded_result = result
    end

    assert_equal 'webhook processed', yielded_result
  end

  def test_handle_webhook_returns_ok_when_no_processor_matches
    # No processor registered for this event
    controller = MockController.new
    controller.handle_webhook(provider: 'stripe', event: 'unknown.event', payload: { id: 'evt_123' })

    assert_equal :ok, controller.rendered_status
  end

  def test_hooksmith_provider_name_returns_action_name
    controller = MockController.new
    controller.action_name = 'github'

    assert_equal 'github', controller.send(:hooksmith_provider_name)
  end

  def test_hooksmith_verification_enabled_returns_false_when_no_verifier
    controller = MockController.new

    refute controller.send(:hooksmith_verification_enabled?)
  end

  def test_hooksmith_verification_enabled_returns_true_when_verifier_configured
    verifier = Hooksmith::Verifiers::BearerToken.new(token: 'secret123')
    Hooksmith.configuration.verifiers['stripe'] = verifier

    controller = MockController.new
    controller.action_name = 'stripe'

    assert controller.send(:hooksmith_verification_enabled?)
  end

  def test_verify_webhook_signature_passes_with_valid_token
    verifier = Hooksmith::Verifiers::BearerToken.new(token: 'secret123')
    Hooksmith.configuration.verifiers['stripe'] = verifier

    controller = MockController.new
    controller.action_name = 'stripe'
    controller.set_request(
      headers: { 'Authorization' => 'Bearer secret123' },
      body: '{"id":"evt_123"}'
    )

    # Should not raise or set unauthorized status
    controller.send(:verify_webhook_signature)
    refute_equal :unauthorized, controller.rendered_status
  end

  def test_verify_webhook_signature_returns_unauthorized_with_invalid_token
    verifier = Hooksmith::Verifiers::BearerToken.new(token: 'secret123')
    Hooksmith.configuration.verifiers['stripe'] = verifier

    controller = MockController.new
    controller.action_name = 'stripe'
    controller.set_request(
      headers: { 'Authorization' => 'Bearer wrong_token' },
      body: '{"id":"evt_123"}'
    )

    controller.send(:verify_webhook_signature)
    assert_equal :unauthorized, controller.rendered_status
  end
end
