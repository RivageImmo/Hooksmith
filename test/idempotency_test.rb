# frozen_string_literal: true

require 'test_helper'

# IdempotencyTest
class IdempotencyTest < Minitest::Test
  def setup
    Hooksmith.configuration.registry.clear
    Hooksmith.configuration.idempotency_keys.clear
  end

  def test_extract_key_returns_nil_when_not_configured
    key = Hooksmith::Idempotency.extract_key(provider: :stripe, payload: { 'id' => 'evt_123' })
    assert_nil key
  end

  def test_extract_key_returns_key_when_configured
    Hooksmith.configure do |config|
      config.provider(:stripe) do |stripe|
        stripe.idempotency_key = ->(payload) { payload['id'] }
        stripe.register(:charge_succeeded, 'DummyProcessor')
      end
    end

    key = Hooksmith::Idempotency.extract_key(provider: :stripe, payload: { 'id' => 'evt_123' })
    assert_equal 'evt_123', key
  end

  def test_extract_key_converts_to_string
    Hooksmith.configure do |config|
      config.provider(:stripe) do |stripe|
        stripe.idempotency_key = ->(payload) { payload['id'] }
        stripe.register(:charge_succeeded, 'DummyProcessor')
      end
    end

    key = Hooksmith::Idempotency.extract_key(provider: :stripe, payload: { 'id' => 12_345 })
    assert_equal '12345', key
  end

  def test_extract_key_handles_extractor_errors
    Hooksmith.configure do |config|
      config.provider(:stripe) do |stripe|
        stripe.idempotency_key = ->(_payload) { raise 'Extraction failed' }
        stripe.register(:charge_succeeded, 'DummyProcessor')
      end
    end

    key = Hooksmith::Idempotency.extract_key(provider: :stripe, payload: { 'id' => 'evt_123' })
    assert_nil key
  end

  def test_composite_key_joins_fields
    key = Hooksmith::Idempotency.composite_key('stripe', 'charge_succeeded', 'evt_123')
    assert_equal 'stripe:charge_succeeded:evt_123', key
  end

  def test_composite_key_with_custom_separator
    key = Hooksmith::Idempotency.composite_key('stripe', 'charge_succeeded', separator: '-')
    assert_equal 'stripe-charge_succeeded', key
  end

  def test_composite_key_ignores_nil_values
    key = Hooksmith::Idempotency.composite_key('stripe', nil, 'evt_123')
    assert_equal 'stripe:evt_123', key
  end

  def test_stripe_extractor
    payload = { 'id' => 'evt_stripe_123' }
    key = Hooksmith::Idempotency::Extractors::STRIPE.call(payload)
    assert_equal 'evt_stripe_123', key
  end

  def test_stripe_extractor_with_symbol_key
    payload = { id: 'evt_stripe_123' }
    key = Hooksmith::Idempotency::Extractors::STRIPE.call(payload)
    assert_equal 'evt_stripe_123', key
  end

  def test_generic_extractor_tries_multiple_fields
    assert_equal 'id_123', Hooksmith::Idempotency::Extractors::GENERIC.call({ 'id' => 'id_123' })
    assert_equal 'evt_123', Hooksmith::Idempotency::Extractors::GENERIC.call({ 'event_id' => 'evt_123' })
    assert_equal 'wh_123', Hooksmith::Idempotency::Extractors::GENERIC.call({ 'webhook_id' => 'wh_123' })
  end

  def test_already_processed_returns_false_when_event_store_disabled
    result = Hooksmith::Idempotency.already_processed?(provider: :stripe, key: 'evt_123')
    assert_equal false, result
  end

  def test_already_processed_returns_false_when_key_is_nil
    result = Hooksmith::Idempotency.already_processed?(provider: :stripe, key: nil)
    assert_equal false, result
  end
end
