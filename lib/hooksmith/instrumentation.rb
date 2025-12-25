# frozen_string_literal: true

module Hooksmith
  # Provides ActiveSupport::Notifications instrumentation for webhook processing.
  #
  # This module emits events at key points in the webhook lifecycle, enabling
  # metrics collection, tracing, and debugging without modifying core code.
  #
  # @example Subscribe to all Hooksmith events
  #   ActiveSupport::Notifications.subscribe(/hooksmith/) do |name, start, finish, id, payload|
  #     duration = finish - start
  #     Rails.logger.info "#{name} took #{duration}s"
  #   end
  #
  # @example Subscribe to specific events
  #   ActiveSupport::Notifications.subscribe('dispatch.hooksmith') do |*args|
  #     event = ActiveSupport::Notifications::Event.new(*args)
  #     StatsD.timing('hooksmith.dispatch', event.duration, tags: ["provider:#{event.payload[:provider]}"])
  #   end
  #
  # == Available Events
  #
  # * `dispatch.hooksmith` - Emitted when a webhook is dispatched
  #   - payload: { provider:, event:, payload:, processor:, result: }
  #
  # * `process.hooksmith` - Emitted when a processor executes
  #   - payload: { provider:, event:, processor:, result: }
  #
  # * `no_processor.hooksmith` - Emitted when no processor matches
  #   - payload: { provider:, event: }
  #
  # * `multiple_processors.hooksmith` - Emitted when multiple processors match
  #   - payload: { provider:, event:, processor_count: }
  #
  # * `error.hooksmith` - Emitted when an error occurs
  #   - payload: { provider:, event:, error:, error_class: }
  #
  module Instrumentation
    NAMESPACE = 'hooksmith'

    module_function

    # Instruments a block with the given event name.
    #
    # @param event_name [String] the event name (without namespace)
    # @param payload [Hash] the event payload
    # @yield the block to instrument
    # @return [Object] the result of the block
    def instrument(event_name, payload = {}, &block)
      return yield unless notifications_available?

      full_name = "#{event_name}.#{NAMESPACE}"
      ActiveSupport::Notifications.instrument(full_name, payload, &block)
    end

    # Publishes an event without a block.
    #
    # @param event_name [String] the event name (without namespace)
    # @param payload [Hash] the event payload
    def publish(event_name, payload = {})
      return unless notifications_available?

      full_name = "#{event_name}.#{NAMESPACE}"
      ActiveSupport::Notifications.publish(full_name, payload)
    end

    # Checks if ActiveSupport::Notifications is available.
    #
    # @return [Boolean] true if available
    def notifications_available?
      defined?(ActiveSupport::Notifications)
    end

    # Subscribes to a Hooksmith event.
    #
    # @param event_name [String, Regexp, nil] the event name, pattern, or nil for all events
    # @yield [name, start, finish, id, payload] the event callback
    # @return [Object] the subscription object
    def subscribe(event_name = nil, &block)
      return unless notifications_available?

      pattern = build_subscription_pattern(event_name)
      ActiveSupport::Notifications.subscribe(pattern, &block)
    end

    # Unsubscribes from a Hooksmith event.
    #
    # @param subscriber [Object] the subscription object from subscribe
    def unsubscribe(subscriber)
      return unless notifications_available?

      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    private

    # Builds the subscription pattern based on the event name type.
    #
    # @param event_name [String, Regexp, nil] the event name or pattern
    # @return [String, Regexp] the subscription pattern
    def build_subscription_pattern(event_name)
      case event_name
      when nil
        /\.#{NAMESPACE}$/
      when Regexp
        event_name
      else
        "#{event_name}.#{NAMESPACE}"
      end
    end
  end
end
