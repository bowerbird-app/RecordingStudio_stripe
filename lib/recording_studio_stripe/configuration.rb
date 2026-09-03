# frozen_string_literal: true

module RecordingStudioStripe
  class Configuration
    SECRET_KEY_ENV_NAMES = %w[STRIPE_SECRET_KEY Stripe_secret_key].freeze
    PUBLISHABLE_KEY_ENV_NAMES = %w[STRIPE_PUBLISHABLE_KEY Stripe_publishable_key].freeze
    WEBHOOK_SECRET_ENV_NAMES = %w[STRIPE_WEBHOOK_SECRET Stripe_webhook_secret].freeze
    TEST_SECRET_PREFIXES = %w[sk_test_ rk_test_].freeze
    LIVE_SECRET_PREFIXES = %w[sk_live_ rk_live_].freeze

    class << self
      def env_secret_key
        first_present_env(*SECRET_KEY_ENV_NAMES)
      end

      def env_publishable_key
        first_present_env(*PUBLISHABLE_KEY_ENV_NAMES)
      end

      def env_webhook_secret
        first_present_env(*WEBHOOK_SECRET_ENV_NAMES)
      end

      def sandbox_test_key?(value = env_secret_key)
        value.present? && TEST_SECRET_PREFIXES.any? { |prefix| value.start_with?(prefix) }
      end

      def live_secret_key?(value = env_secret_key)
        value.present? && LIVE_SECRET_PREFIXES.any? { |prefix| value.start_with?(prefix) }
      end

      def first_present_env(*names)
        names.each do |name|
          value = ENV.fetch(name, nil)
          return value if value.present?
        end
        nil
      end
    end

    attr_accessor :secret_key,
                  :publishable_key,
                  :webhook_secret,
                  :api_version,
                  :client,
                  :meters,
                  :paywalls,
                  :success_path,
                  :cancel_path,
                  :mount_path,
                  :authenticate,
                  :current_actor,
                  :current_root_recording
    attr_reader :hooks

    def initialize
      @secret_key = self.class.env_secret_key
      @publishable_key = self.class.env_publishable_key
      @webhook_secret = self.class.env_webhook_secret
      @api_version = "2026-07-29.dahlia"
      @client = nil
      @meters = default_meters
      @paywalls = {}
      @success_path = "/billing"
      @cancel_path = "/plans"
      @mount_path = "/billing"
      @authenticate = nil
      @current_actor = nil
      @current_root_recording = nil
      @hooks = RecordingStudio::Hooks.new
    end

    def stripe_configured?
      secret_key.present? || client.present?
    end

    def local_mode?
      !stripe_configured?
    end

    def to_h
      {
        secret_key: secret_key.present? ? "[set]" : nil,
        publishable_key: publishable_key.present? ? "[set]" : nil,
        webhook_secret: webhook_secret.present? ? "[set]" : nil,
        api_version: api_version,
        meters: meters,
        paywalls: paywalls,
        success_path: success_path,
        cancel_path: cancel_path,
        local_mode: local_mode?,
        mount_path: mount_path,
        hooks_registered: hooks.instance_variable_get(:@registry).transform_values(&:size)
      }
    end

    def merge!(hash)
      return unless hash.respond_to?(:each)

      hash.each do |key, value|
        setter = "#{key}="
        public_send(setter, value) if respond_to?(setter)
      end
    end

    private

    def default_meters
      {
        "ai_tokens" => { "label" => "AI tokens" },
        "api_calls" => { "label" => "API calls" }
      }
    end
  end
end
