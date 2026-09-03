# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def setup
    @configuration = RecordingStudioStripe::Configuration.new
  end

  def test_merge_updates_known_attributes
    @configuration.merge!(secret_key: "sk_test", success_path: "/done")

    assert_equal "sk_test", @configuration.secret_key
    assert_equal "/done", @configuration.success_path
  end

  def test_merge_ignores_unknown_keys
    @configuration.merge!(unknown_key: "ignored", success_path: "/kept")

    refute_respond_to @configuration, :unknown_key
    assert_equal "/kept", @configuration.success_path
  end

  def test_merge_with_non_enumerable_is_noop
    original = @configuration.to_h

    @configuration.merge!(nil)

    assert_equal original[:success_path], @configuration.success_path
  end

  def test_initialize_uses_environment_secret_key
    previous_value = ENV.fetch("STRIPE_SECRET_KEY", nil)
    previous_alias = ENV.fetch("Stripe_secret_key", nil)
    ENV["STRIPE_SECRET_KEY"] = "env-token"
    ENV.delete("Stripe_secret_key")

    configuration = RecordingStudioStripe::Configuration.new

    assert_equal "env-token", configuration.secret_key
    refute_predicate configuration, :local_mode?
    assert configuration.stripe_configured?
  ensure
    ENV["STRIPE_SECRET_KEY"] = previous_value
    ENV["Stripe_secret_key"] = previous_alias
  end

  def test_initialize_uses_cursor_secret_key_name
    previous_canonical = ENV.fetch("STRIPE_SECRET_KEY", nil)
    previous_alias = ENV.fetch("Stripe_secret_key", nil)
    ENV.delete("STRIPE_SECRET_KEY")
    ENV["Stripe_secret_key"] = "sk_test_from_cursor"

    configuration = RecordingStudioStripe::Configuration.new

    assert_equal "sk_test_from_cursor", configuration.secret_key
    assert RecordingStudioStripe::Configuration.sandbox_test_key?("sk_test_from_cursor")
    refute_predicate configuration, :local_mode?
  ensure
    ENV["STRIPE_SECRET_KEY"] = previous_canonical
    ENV["Stripe_secret_key"] = previous_alias
  end

  def test_canonical_secret_key_wins_over_cursor_name
    previous_canonical = ENV.fetch("STRIPE_SECRET_KEY", nil)
    previous_alias = ENV.fetch("Stripe_secret_key", nil)
    ENV["STRIPE_SECRET_KEY"] = "sk_test_canonical"
    ENV["Stripe_secret_key"] = "sk_test_alias"

    configuration = RecordingStudioStripe::Configuration.new

    assert_equal "sk_test_canonical", configuration.secret_key
  ensure
    ENV["STRIPE_SECRET_KEY"] = previous_canonical
    ENV["Stripe_secret_key"] = previous_alias
  end

  def test_merge_accepts_string_keys
    @configuration.merge!("secret_key" => "string-key", "success_path" => "/string")

    assert_equal "string-key", @configuration.secret_key
    assert_equal "/string", @configuration.success_path
  end

  def test_to_h_reports_registered_hook_counts
    @configuration.hooks.before_initialize { nil }
    @configuration.hooks.before_initialize { nil }
    @configuration.hooks.after_service { nil }

    result = @configuration.to_h

    assert_equal 2, result.fetch(:hooks_registered).fetch(:before_initialize)
    assert_equal 1, result.fetch(:hooks_registered).fetch(:after_service)
    assert_equal "[set]", result[:secret_key] if @configuration.secret_key.present?
  end

  def test_configure_without_block_is_safe
    RecordingStudioStripe.configure

    assert_kind_of RecordingStudioStripe::Configuration, RecordingStudioStripe.configuration
  end

  def test_default_meters_are_ai_tokens_and_api_calls
    assert_equal %w[ai_tokens api_calls], @configuration.meters.keys
    assert_equal "AI tokens", @configuration.meters.fetch("ai_tokens").fetch("label")
  end

  def test_default_paywalls_are_empty
    assert_equal({}, @configuration.paywalls)
    assert_includes @configuration.to_h.keys, :paywalls
  end

  def test_local_mode_when_no_secret
    previous_canonical = ENV.fetch("STRIPE_SECRET_KEY", nil)
    previous_alias = ENV.fetch("Stripe_secret_key", nil)
    ENV.delete("STRIPE_SECRET_KEY")
    ENV.delete("Stripe_secret_key")
    configuration = RecordingStudioStripe::Configuration.new

    assert_predicate configuration, :local_mode?
    refute RecordingStudioStripe::Configuration.sandbox_test_key?
  ensure
    ENV["STRIPE_SECRET_KEY"] = previous_canonical
    ENV["Stripe_secret_key"] = previous_alias
  end

  def test_live_secret_key_is_not_a_sandbox_test_key
    refute RecordingStudioStripe::Configuration.sandbox_test_key?("sk_live_example")
    assert RecordingStudioStripe::Configuration.live_secret_key?("sk_live_example")
    assert RecordingStudioStripe::Configuration.sandbox_test_key?("rk_test_example")
  end
end
