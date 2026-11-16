# frozen_string_literal: true

require "test_helper"
require "rake"

class WebhookSecretTest < Minitest::Test
  def setup
    @configuration = RecordingStudioStripe.configuration
    @previous = {
      secret_key: @configuration.secret_key,
      publishable_key: @configuration.publishable_key,
      webhook_secret: @configuration.webhook_secret,
      client: @configuration.client,
      require_secrets: @configuration.require_secrets
    }
    @configuration.secret_key = nil
    @configuration.publishable_key = nil
    @configuration.webhook_secret = nil
    @configuration.client = nil
    @configuration.require_secrets = false
    RecordingStudioStripe::WebhookSecret.instance_variable_set(:@reported, false)
  end

  def teardown
    @configuration.secret_key = @previous[:secret_key]
    @configuration.publishable_key = @previous[:publishable_key]
    @configuration.webhook_secret = @previous[:webhook_secret]
    @configuration.client = @previous[:client]
    @configuration.require_secrets = @previous[:require_secrets]
    RecordingStudioStripe::WebhookSecret.instance_variable_set(:@reported, false)
  end

  def test_production_without_secrets_boots_and_warns_once
    canary = "pk_live_do_not_print_this_value"
    @configuration.publishable_key = canary
    log = WarningLog.new

    in_env("production") do
      Rails.stub(:logger, log) do
        with_env("STRIPE_SECRET_KEY", canary) do
          with_env("STRIPE_WEBHOOK_SECRET", "whsec_do_not_print_this_value") do
            RecordingStudioStripe::WebhookSecret.report!
            RecordingStudioStripe::WebhookSecret.report!
          end
        end
      end
    end

    assert_equal 1, log.warnings.size
    message = log.warnings.first
    assert_includes message, "[recording_studio_stripe]"
    assert_includes message, "STRIPE_WEBHOOK_SECRET missing: /webhooks/stripe returns 503"
    assert_includes message, "STRIPE_SECRET_KEY missing: checkout/portal/admin sync disabled"
    refute_includes message, canary
    refute_includes message, "whsec_do_not_print_this_value"
  end

  def test_strict_mode_in_production_raises
    @configuration.require_secrets = true
    @configuration.secret_key = "sk_test_fixture"

    in_env("production") do
      error = assert_raises(RecordingStudioStripe::MissingWebhookSecret) do
        RecordingStudioStripe::WebhookSecret.report!
      end
      assert_includes error.message, "STRIPE_WEBHOOK_SECRET"
    end

    @configuration.webhook_secret = "whsec_test_fixture"
    @configuration.secret_key = nil

    in_env("production") do
      error = assert_raises(RecordingStudioStripe::MissingStripeKey) do
        RecordingStudioStripe::WebhookSecret.report!
      end
      assert_includes error.message, "STRIPE_SECRET_KEY"
      assert_kind_of RecordingStudioStripe::NotConfigured, error
    end
  end

  def test_strict_mode_skips_the_raise_for_a_build_task
    @configuration.require_secrets = true
    log = WarningLog.new
    tasks = %w[assets:precompile tailwindcss:build tailwindcss:watch app:tailwindcss:build]

    tasks.each do |task|
      rake = Struct.new(:top_level_tasks).new([task])
      in_env("production") do
        Rake.stub(:application, rake) do
          Rails.stub(:logger, log) do
            RecordingStudioStripe::WebhookSecret.report!
          end
        end
      end
    end

    assert_empty log.warnings
  end

  def test_production_with_both_secrets_does_not_warn
    @configuration.secret_key = "sk_test_fixture"
    @configuration.webhook_secret = "whsec_test_fixture"
    log = WarningLog.new

    in_env("production") do
      Rails.stub(:logger, log) do
        RecordingStudioStripe::WebhookSecret.report!
      end
    end

    assert_empty log.warnings
  end

  def test_local_mode_does_not_warn
    log = WarningLog.new

    %w[development test].each do |name|
      in_env(name) do
        Rails.stub(:logger, log) do
          RecordingStudioStripe::WebhookSecret.report!
        end
      end
    end

    assert_empty log.warnings
  end

  def test_secret_key_base_dummy_skips_strict_mode
    @configuration.require_secrets = true
    previous = ENV.fetch("SECRET_KEY_BASE_DUMMY", nil)
    ENV["SECRET_KEY_BASE_DUMMY"] = "1"

    in_env("production") do
      RecordingStudioStripe::WebhookSecret.report!
    end
  ensure
    if previous.nil?
      ENV.delete("SECRET_KEY_BASE_DUMMY")
    else
      ENV["SECRET_KEY_BASE_DUMMY"] = previous
    end
  end

  def test_boot_initializer_reports_missing_secrets
    source = File.read(File.expand_path("../lib/recording_studio_stripe/engine.rb", __dir__))

    assert_includes source, "config.after_initialize"
    assert_includes source, "WebhookSecret.report!"
    refute_includes source, "require_in_production!"
  end

  private

  def in_env(name, &)
    Rails.stub(:env, ActiveSupport::StringInquirer.new(name), &)
  end

  def with_env(name, value)
    previous = ENV.fetch(name, nil)
    ENV[name] = value
    yield
  ensure
    if previous.nil?
      ENV.delete(name)
    else
      ENV[name] = previous
    end
  end

  class WarningLog
    attr_reader :warnings

    def initialize
      @warnings = []
    end

    def warn(message)
      @warnings << message
    end
  end
end
