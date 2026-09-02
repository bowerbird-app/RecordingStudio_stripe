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
    ENV["STRIPE_SECRET_KEY"] = "env-token"

    configuration = RecordingStudioStripe::Configuration.new

    assert_equal "env-token", configuration.secret_key
    refute_predicate configuration, :local_mode?
    assert configuration.stripe_configured?
  ensure
    ENV["STRIPE_SECRET_KEY"] = previous_value
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

  def test_local_mode_when_no_secret
    ENV["STRIPE_SECRET_KEY"] = nil
    configuration = RecordingStudioStripe::Configuration.new

    assert_predicate configuration, :local_mode?
  ensure
    ENV.delete("STRIPE_SECRET_KEY")
  end
end
