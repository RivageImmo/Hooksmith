# frozen_string_literal: true

require 'test_helper'

# DispatcherTest
class DispatcherTest < Minitest::Test
  def setup
    Hooksmith.configuration.registry.clear
    @payload = { foo: 'bar', handle: true }
    @provider = :test_dispatcher
  end

  # Un processor simple qui traite toujours.
  class ::SingleProcessor < Hooksmith::Processor::Base
    def can_handle?(_payload)
      true
    end

    def process!
      'single processed'
    end
  end

  # Deux processors pour tester la situation multi-processors.
  class ::MultiProcessor1 < Hooksmith::Processor::Base
    def can_handle?(_payload)
      true
    end

    def process!
      'multi1 processed'
    end
  end

  # Second multi-processor for testing multiple processor scenario.
  class ::MultiProcessor2 < Hooksmith::Processor::Base
    def can_handle?(_payload)
      true
    end

    def process!
      'multi2 processed'
    end
  end

  # Un processor conditionnel qui ne traite que si payload[:handle] est true.
  class ::ConditionalProcessor < Hooksmith::Processor::Base
    def can_handle?(payload)
      payload[:handle] == true
    end

    def process!
      'conditional processed'
    end
  end

  # Un processor qui lève une erreur lors du traitement.
  class ::ErrorProcessor < Hooksmith::Processor::Base
    def can_handle?(_payload)
      true
    end

    def process!
      raise StandardError, 'processing failed'
    end
  end

  def test_no_processor_matches
    Hooksmith.configuration.register_processor(@provider, :non_matching, 'ConditionalProcessor')
    dispatcher = Hooksmith::Dispatcher.new(
      provider: @provider,
      event: :non_matching,
      payload: @payload.merge(handle: false)
    )
    result = dispatcher.run!
    # Aucune processor ne devrait valider la condition, d'où le retour nil.
    assert_nil result
  end

  def test_single_processor_matches
    Hooksmith.configuration.register_processor(@provider, :single_event, 'SingleProcessor')
    dispatcher = Hooksmith::Dispatcher.new(
      provider: @provider,
      event: :single_event,
      payload: @payload
    )
    result = dispatcher.run!
    assert_equal 'single processed', result
  end

  def test_multiple_processors_raise_error
    Hooksmith.configuration.register_processor(@provider, :multi_event, 'MultiProcessor1')
    Hooksmith.configuration.register_processor(@provider, :multi_event, 'MultiProcessor2')
    dispatcher = Hooksmith::Dispatcher.new(
      provider: @provider,
      event: :multi_event,
      payload: @payload
    )
    error = assert_raises(Hooksmith::MultipleProcessorsError) { dispatcher.run! }
    assert_match(/Multiple processors found/, error.message)
  end

  def test_processor_error_propagates
    Hooksmith.configuration.register_processor(@provider, :error_event, 'ErrorProcessor')
    dispatcher = Hooksmith::Dispatcher.new(
      provider: @provider,
      event: :error_event,
      payload: @payload
    )
    error = assert_raises(StandardError) { dispatcher.run! }
    assert_equal 'processing failed', error.message
  end
end
