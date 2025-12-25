# frozen_string_literal: true

require 'test_helper'

# Stub ActiveJob::Base if not already defined
unless defined?(ActiveJob::Base)
  module ActiveJob
    # Stub for ActiveJob::Base when ActiveJob is not available
    class Base
      def self.queue_as(_queue_name); end
    end
  end
end

# Load the job after stubbing ActiveJob
require 'hooksmith/jobs/dispatcher_job'

# DispatcherJobTest tests the Hooksmith::Jobs::DispatcherJob class
class DispatcherJobTest < Minitest::Test
  def setup
    Hooksmith.configuration.registry.clear
    Hooksmith.configuration.idempotency_keys.clear
    @provider = 'test_provider'
    @event = 'test_event'
    @payload = { 'id' => 'evt_123', 'data' => 'test' }
  end

  # Test processor for job tests
  class ::JobTestProcessor < Hooksmith::Processor::Base
    def can_handle?(_payload)
      true
    end

    def process!
      'job processed'
    end
  end

  def test_perform_delegates_to_dispatcher
    Hooksmith.configuration.register_processor(@provider, @event, 'JobTestProcessor')

    job = Hooksmith::Jobs::DispatcherJob.new
    result = job.perform(provider: @provider, event: @event, payload: @payload)

    assert_equal 'job processed', result
  end

  def test_perform_converts_provider_and_event_to_strings
    Hooksmith.configuration.register_processor(@provider, @event, 'JobTestProcessor')

    job = Hooksmith::Jobs::DispatcherJob.new
    result = job.perform(provider: :test_provider, event: :test_event, payload: @payload)

    assert_equal 'job processed', result
  end

  def test_perform_skips_duplicate_when_idempotency_configured
    # Configure idempotency key extractor
    Hooksmith.configuration.idempotency_keys[@provider] = ->(payload) { payload['id'] }

    # Configure event store with a mock model that tracks processed events
    processed_keys = ['evt_123']
    mock_model = Class.new do
      define_singleton_method(:exists?) do |conditions|
        processed_keys.include?(conditions[:idempotency_key])
      end
    end

    Hooksmith.configuration.event_store_config.enabled = true
    Hooksmith.configuration.event_store_config.model_class_name = 'MockModel'

    # Stub Object.const_get to return our mock model
    Object.const_set(:MockModel, mock_model) unless defined?(::MockModel)

    Hooksmith.configuration.register_processor(@provider, @event, 'JobTestProcessor')

    job = Hooksmith::Jobs::DispatcherJob.new
    result = job.perform(provider: @provider, event: @event, payload: @payload)

    # Should return nil because the event was already processed
    assert_nil result
  ensure
    Object.send(:remove_const, :MockModel) if defined?(::MockModel)
    Hooksmith.configuration.event_store_config.enabled = false
  end

  def test_perform_processes_when_skip_idempotency_check_option_set
    # Configure idempotency key extractor
    Hooksmith.configuration.idempotency_keys[@provider] = ->(payload) { payload['id'] }

    # Configure event store with a mock model that says event is already processed
    mock_model = Class.new do
      define_singleton_method(:exists?) { |_| true }
    end

    Hooksmith.configuration.event_store_config.enabled = true
    Hooksmith.configuration.event_store_config.model_class_name = 'MockModel2'

    Object.const_set(:MockModel2, mock_model) unless defined?(::MockModel2)

    Hooksmith.configuration.register_processor(@provider, @event, 'JobTestProcessor')

    job = Hooksmith::Jobs::DispatcherJob.new
    result = job.perform(provider: @provider, event: @event, payload: @payload, skip_idempotency_check: true)

    # Should process because skip_idempotency_check is true
    assert_equal 'job processed', result
  ensure
    Object.send(:remove_const, :MockModel2) if defined?(::MockModel2)
    Hooksmith.configuration.event_store_config.enabled = false
  end

  def test_job_inherits_from_activejob_base
    assert Hooksmith::Jobs::DispatcherJob < ActiveJob::Base
  end
end
