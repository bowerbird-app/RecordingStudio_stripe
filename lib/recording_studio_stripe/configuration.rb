# frozen_string_literal: true

module RecordingStudioStripe
  module ConfigurationSecrets
    def webhook_configured?
      webhook_secret.present?
    end

    def configured?
      stripe_configured? && webhook_configured?
    end

    def missing_secrets
      names = []
      names << "STRIPE_WEBHOOK_SECRET" unless webhook_configured?
      names << "STRIPE_SECRET_KEY" unless stripe_configured?
      names
    end
  end

  class Configuration
    DOWNGRADE_TIMINGS = %w[at_period_end immediately].freeze
    private_constant :DOWNGRADE_TIMINGS

    include ConfigurationSecrets

    attr_accessor :secret_key,
                  :publishable_key,
                  :webhook_secret,
                  :require_secrets,
                  :api_version,
                  :client,
                  :meters,
                  :paywalls,
                  :limits,
                  :success_path,
                  :cancel_path,
                  :limit_reached_path,
                  :allow_promotion_codes,
                  :automatic_tax,
                  :mount_path,
                  :authenticate,
                  :current_actor,
                  :current_root_recording,
                  :site_admin_recording,
                  :domain_event_publish_lease,
                  :prices_pending_alert_after,
                  :prices_pending_max_hold,
                  :plans_background_image
    attr_reader :hooks, :usage_costs, :limit_usages, :layout, :subscription_types
    attr_writer :usage_path

    def initialize
      apply_environment_defaults
      @api_version = "2026-07-29.dahlia"
      @client = nil
      @meters = default_meters
      @usage_costs = {}.freeze
      @paywalls = {}
      @limits = {}
      @limit_usages = {}
      @subscription_types = {}
      @success_path = "/billing"
      @cancel_path = "/plans"
      @limit_reached_path = nil
      @usage_path = nil
      @allow_promotion_codes = true
      @automatic_tax = false
      @mount_path = "/billing"
      @authenticate = nil
      @current_actor = nil
      @current_root_recording = nil
      @site_admin_recording = nil
      @domain_event_publish_lease = 5.minutes
      @prices_pending_alert_after = 1.day
      @prices_pending_max_hold = 3.days
      @layout = nil
      @plans_background_image = nil
      @hooks = RecordingStudio::Hooks.new
    end

    def layout=(value)
      @layout = RecordingStudio::Layout.accept(value)
    end

    def stripe_configured?
      secret_key.present? || client.present?
    end

    # Development or test, with no Stripe secret key and no client.
    # A missing key in any other environment is not local mode.
    def local_mode?
      !stripe_configured? && %w[development test].include?(Rails.env.to_s)
    end

    def to_h
      {
        secret_key: secret_key.present? ? "[set]" : nil,
        publishable_key: publishable_key.present? ? "[set]" : nil,
        webhook_secret: webhook_secret.present? ? "[set]" : nil,
        api_version: api_version,
        meters: meters,
        usage_costs: usage_costs,
        paywalls: paywalls,
        limits: limits,
        limit_usages: limit_usages.keys,
        subscription_types: subscription_types,
        success_path: success_path,
        cancel_path: cancel_path,
        limit_reached_path: limit_reached_path,
        usage_path: usage_path,
        allow_promotion_codes: allow_promotion_codes,
        automatic_tax: automatic_tax,
        local_mode: local_mode?,
        configured: configured?,
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

    def usage_path
      @usage_path.presence || "#{mount_path.to_s.chomp('/')}/usage"
    end

    def subscription_types=(value)
      validate_downgrade_timings!(value)
      @subscription_types = value
    end

    def usage_costs=(costs)
      @usage_costs = UsageTariff.normalize_costs(costs).freeze
    end

    def register_limit_usage(name, &block)
      key = limit_usage_name(name)
      raise ArgumentError, "register_limit_usage needs a block" unless block

      limit_usages[key] = block
    end

    def limit_usage_for(name)
      limit_usages[name.to_s]
    end

    private

    def limit_usage_name(name)
      key = name.to_s
      raise ArgumentError, "limit name must not be blank" if key.blank?

      key
    end

    def apply_environment_defaults
      @secret_key = ENV.fetch("STRIPE_SECRET_KEY", nil)
      @publishable_key = ENV.fetch("STRIPE_PUBLISHABLE_KEY", nil)
      @webhook_secret = ENV.fetch("STRIPE_WEBHOOK_SECRET", nil)
      @require_secrets = ENV["RECORDING_STUDIO_STRIPE_REQUIRE_SECRETS"] == "1"
    end

    def validate_downgrade_timings!(value)
      return if value.blank?

      value.to_h.each_value do |entry|
        timing = entry.to_h.stringify_keys["downgrade_timing"]
        next if timing.nil?
        next if DOWNGRADE_TIMINGS.include?(timing.to_s)

        raise ArgumentError, "downgrade_timing must be at_period_end or immediately, got #{timing.inspect}"
      end
    end

    def default_meters
      {
        "ai_tokens" => { "label" => "AI tokens" },
        "api_calls" => { "label" => "API calls" }
      }
    end
  end
end
