# frozen_string_literal: true

require 'test_helper'

# VerifiersTest
class VerifiersTest < Minitest::Test
  def setup
    Hooksmith.configuration.registry.clear
    Hooksmith.configuration.verifiers.clear
  end

  def test_hmac_verifier_validates_signature
    secret = 'test_secret'
    body = '{"event": "test"}'
    expected_signature = OpenSSL::HMAC.hexdigest('sha256', secret, body)

    verifier = Hooksmith::Verifiers::Hmac.new(
      secret:,
      header: 'X-Signature'
    )

    request = Hooksmith::Request.new(
      headers: { 'X-Signature' => expected_signature },
      body:
    )

    # Should not raise
    verifier.verify!(request)
  end

  def test_hmac_verifier_rejects_invalid_signature
    verifier = Hooksmith::Verifiers::Hmac.new(
      secret: 'test_secret',
      header: 'X-Signature'
    )

    request = Hooksmith::Request.new(
      headers: { 'X-Signature' => 'invalid_signature' },
      body: '{"event": "test"}'
    )

    error = assert_raises(Hooksmith::VerificationError) { verifier.verify!(request) }
    assert_equal 'signature_mismatch', error.reason
  end

  def test_hmac_verifier_rejects_missing_signature
    verifier = Hooksmith::Verifiers::Hmac.new(
      secret: 'test_secret',
      header: 'X-Signature'
    )

    request = Hooksmith::Request.new(
      headers: {},
      body: '{"event": "test"}'
    )

    error = assert_raises(Hooksmith::VerificationError) { verifier.verify!(request) }
    assert_equal 'missing_signature', error.reason
  end

  def test_hmac_verifier_with_base64_encoding
    secret = 'test_secret'
    body = '{"event": "test"}'
    digest = OpenSSL::HMAC.digest('sha256', secret, body)
    expected_signature = Base64.strict_encode64(digest)

    verifier = Hooksmith::Verifiers::Hmac.new(
      secret:,
      header: 'X-Signature',
      encoding: :base64
    )

    request = Hooksmith::Request.new(
      headers: { 'X-Signature' => expected_signature },
      body:
    )

    # Should not raise
    verifier.verify!(request)
  end

  def test_hmac_verifier_with_signature_prefix
    secret = 'test_secret'
    body = '{"event": "test"}'
    signature = OpenSSL::HMAC.hexdigest('sha256', secret, body)

    verifier = Hooksmith::Verifiers::Hmac.new(
      secret:,
      header: 'X-Hub-Signature-256',
      signature_prefix: 'sha256='
    )

    request = Hooksmith::Request.new(
      headers: { 'X-Hub-Signature-256' => "sha256=#{signature}" },
      body:
    )

    # Should not raise
    verifier.verify!(request)
  end

  def test_bearer_token_verifier_validates_token
    verifier = Hooksmith::Verifiers::BearerToken.new(
      token: 'secret_token'
    )

    request = Hooksmith::Request.new(
      headers: { 'Authorization' => 'Bearer secret_token' },
      body: ''
    )

    # Should not raise
    verifier.verify!(request)
  end

  def test_bearer_token_verifier_rejects_invalid_token
    verifier = Hooksmith::Verifiers::BearerToken.new(
      token: 'secret_token'
    )

    request = Hooksmith::Request.new(
      headers: { 'Authorization' => 'Bearer wrong_token' },
      body: ''
    )

    error = assert_raises(Hooksmith::VerificationError) { verifier.verify!(request) }
    assert_equal 'invalid_token', error.reason
  end

  def test_bearer_token_verifier_rejects_missing_token
    verifier = Hooksmith::Verifiers::BearerToken.new(
      token: 'secret_token'
    )

    request = Hooksmith::Request.new(
      headers: {},
      body: ''
    )

    error = assert_raises(Hooksmith::VerificationError) { verifier.verify!(request) }
    assert_equal 'missing_token', error.reason
  end

  def test_bearer_token_verifier_with_custom_header
    verifier = Hooksmith::Verifiers::BearerToken.new(
      token: 'secret_token',
      header: 'X-Webhook-Token',
      strip_bearer_prefix: false
    )

    request = Hooksmith::Request.new(
      headers: { 'X-Webhook-Token' => 'secret_token' },
      body: ''
    )

    # Should not raise
    verifier.verify!(request)
  end

  def test_verifier_enabled_check
    hmac_verifier = Hooksmith::Verifiers::Hmac.new(secret: 'secret', header: 'X-Sig')
    assert hmac_verifier.enabled?

    empty_hmac = Hooksmith::Verifiers::Hmac.new(secret: '', header: 'X-Sig')
    refute empty_hmac.enabled?

    bearer_verifier = Hooksmith::Verifiers::BearerToken.new(token: 'token')
    assert bearer_verifier.enabled?

    empty_bearer = Hooksmith::Verifiers::BearerToken.new(token: '')
    refute empty_bearer.enabled?
  end

  def test_provider_verifier_configuration
    Hooksmith.configure do |config|
      config.provider(:stripe) do |stripe|
        stripe.verifier = Hooksmith::Verifiers::Hmac.new(
          secret: 'stripe_secret',
          header: 'Stripe-Signature'
        )
        stripe.register(:charge_succeeded, 'DummyProcessor')
      end
    end

    verifier = Hooksmith.configuration.verifier_for(:stripe)
    assert_instance_of Hooksmith::Verifiers::Hmac, verifier
    assert verifier.enabled?
  end

  def test_hooksmith_verify_method
    Hooksmith.configure do |config|
      config.provider(:test_provider) do |provider|
        provider.verifier = Hooksmith::Verifiers::BearerToken.new(token: 'test_token')
      end
    end

    valid_request = Hooksmith::Request.new(
      headers: { 'Authorization' => 'Bearer test_token' },
      body: ''
    )

    # Should not raise
    Hooksmith.verify!(provider: :test_provider, request: valid_request)

    invalid_request = Hooksmith::Request.new(
      headers: { 'Authorization' => 'Bearer wrong_token' },
      body: ''
    )

    assert_raises(Hooksmith::VerificationError) do
      Hooksmith.verify!(provider: :test_provider, request: invalid_request)
    end
  end

  def test_hooksmith_verify_skips_when_no_verifier
    # No verifier configured for this provider
    request = Hooksmith::Request.new(headers: {}, body: '')

    # Should not raise even with empty headers
    Hooksmith.verify!(provider: :unconfigured_provider, request:)
  end

  def test_verifier_configured_check
    Hooksmith.configure do |config|
      config.provider(:configured) do |provider|
        provider.verifier = Hooksmith::Verifiers::BearerToken.new(token: 'token')
      end
    end

    assert Hooksmith.verifier_configured?(:configured)
    refute Hooksmith.verifier_configured?(:unconfigured)
  end
end

# DummyProcessor for verifier tests
class DummyProcessor < Hooksmith::Processor::Base
  def can_handle?(_payload)
    true
  end

  def process!
    'dummy processed'
  end
end
