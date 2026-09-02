# frozen_string_literal: true

module RecordingStudioStripe
  class Configuration
    attr_accessor :secret_key,
                  :publishable_key,
                  :webhook_secret,
                  :api_version,
                  :client,
                  :meters,
                  :success_path,
                  :cancel_path,
                  :mount_path,
                  :authenticate,
                  :current_actor,
                  :current_root_recording
    attr_reader :hooks

    def initialize
      @secret_key = ENV.fetch("STRIPE_SECRET_KEY", nil)
      @publishable_key = ENV.fetch("STRIPE_PUBLISHABLE_KEY", nil)
      @webhook_secret = ENV.fetch("STRIPE_WEBHOOK_SECRET", nil)
      @api_version = "2026-07-29.dahlia"
      @client = nil
      @meters = default_meters
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
