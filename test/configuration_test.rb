# frozen_string_literal: true

require 'test_helper'

# DummyProcessor pour les tests de configuration.
class DummyProcessor < Hooksmith::Processor::Base
  def can_handle?(_payload)
    true
  end

  def process!
    'dummy processed'
  end
end

# ConfigurationTest
class ConfigurationTest < Minitest::Test
  def setup
    # On réinitialise la registry avant chaque test pour éviter toute interférence.
    Hooksmith.configuration.registry.clear
  end

  def test_configuration_instance
    config = Hooksmith.configuration
    assert_instance_of Hooksmith::Configuration, config
  end

  def test_configure_dsl_registers_provider
    Hooksmith.configure do |config|
      config.provider(:test_provider) do |provider_config|
        provider_config.register(:test_event, 'DummyProcessor')
      end
    end
    # Registry uses string keys internally to prevent Symbol DoS
    entries = Hooksmith.configuration.registry['test_provider']
    assert_equal 1, entries.size
    assert_equal 'test_event', entries.first[:event]
    assert_equal DummyProcessor, Object.const_get(entries.first[:processor])
  end

  def test_direct_registration_and_processors_for
    Hooksmith.configuration.register_processor(:foo, :bar, 'DummyProcessor')
    matches = Hooksmith.configuration.processors_for(:foo, :bar)
    assert_equal 1, matches.size
    assert_equal DummyProcessor, Object.const_get(matches.first[:processor])
  end

  def test_provider_config_registration
    provider_config = Hooksmith::Config::Provider.new(:example)
    provider_config.register(:sample_event, 'DummyProcessor')
    assert_equal 1, provider_config.entries.size
    # Provider uses string keys internally to prevent Symbol DoS
    assert_equal 'sample_event', provider_config.entries.first[:event]
    assert_equal DummyProcessor, Object.const_get(provider_config.entries.first[:processor])
  end

  def test_symbol_dos_prevention
    # Verify that untrusted input doesn't create new symbols
    initial_symbol_count = Symbol.all_symbols.count

    # Simulate untrusted webhook input with random event names
    100.times do |i|
      Hooksmith.configuration.processors_for("untrusted_provider_#{i}", "untrusted_event_#{i}")
    end

    # Symbol count should not have increased significantly
    # (some symbols may be created by the test framework itself)
    final_symbol_count = Symbol.all_symbols.count
    symbol_increase = final_symbol_count - initial_symbol_count

    # Should not create 200 new symbols (one for each provider and event)
    assert symbol_increase < 50, "Symbol DoS: created #{symbol_increase} new symbols from untrusted input"
  end
end
