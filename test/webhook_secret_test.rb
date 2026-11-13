# frozen_string_literal: true

require "test_helper"
require "rake"

class WebhookSecretTest < Minitest::Test
  def setup
    @configuration = RecordingStudioStripe.configuration
    @previous_secret = @configuration.webhook_secret
    @configuration.webhook_secret = nil
  end

  def teardown
    @configuration.webhook_secret = @previous_secret
  end

  def test_production_without_a_webhook_secret_raises
    in_env("production") do
      error = assert_raises(RecordingStudioStripe::MissingWebhookSecret) do
        RecordingStudioStripe::WebhookSecret.require_in_production!
      end

      assert_equal "Set STRIPE_WEBHOOK_SECRET in production", error.message
    end
  end

  def test_production_with_a_webhook_secret_boots
    @configuration.webhook_secret = "whsec_test_fixture"

    in_env("production") do
      RecordingStudioStripe::WebhookSecret.require_in_production!
    end
  end

  def test_development_and_test_boot_without_a_webhook_secret
    %w[development test].each do |name|
      in_env(name) do
        RecordingStudioStripe::WebhookSecret.require_in_production!
      end
    end
  end

  def test_asset_precompile_does_not_raise_in_production
    rake = Struct.new(:top_level_tasks).new(["assets:precompile"])

    in_env("production") do
      Rake.stub(:application, rake) do
        RecordingStudioStripe::WebhookSecret.require_in_production!
      end
    end
  end

  def test_secret_key_base_dummy_does_not_raise_in_production
    previous = ENV.fetch("SECRET_KEY_BASE_DUMMY", nil)
    ENV["SECRET_KEY_BASE_DUMMY"] = "1"

    in_env("production") do
      RecordingStudioStripe::WebhookSecret.require_in_production!
    end
  ensure
    if previous.nil?
      ENV.delete("SECRET_KEY_BASE_DUMMY")
    else
      ENV["SECRET_KEY_BASE_DUMMY"] = previous
    end
  end

  def test_boot_initializer_requires_the_webhook_secret
    source = File.read(File.expand_path("../lib/recording_studio_stripe/engine.rb", __dir__))

    assert_includes source, "WebhookSecret.require_in_production!"
  end

  private

  def in_env(name, &)
    Rails.stub(:env, ActiveSupport::StringInquirer.new(name), &)
  end
end
