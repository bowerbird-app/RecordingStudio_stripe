# frozen_string_literal: true

require "recording_studio"
require "stripe"

require "recording_studio_stripe/version"
require "recording_studio_stripe/errors"
require "recording_studio_stripe/engine"
require "recording_studio_stripe/configuration"
require "recording_studio_stripe/billable"
require "recording_studio_stripe/admin_support"
require "recording_studio_stripe/client"
require "recording_studio_stripe/billing"
require "recording_studio_stripe/meter_handle"
require "recording_studio_stripe/usage_period"
require "recording_studio_stripe/record_usage"
require "recording_studio_stripe/compare_prices"
require "recording_studio_stripe/ensure_customer"
require "recording_studio_stripe/start_checkout"
require "recording_studio_stripe/apply_subscription"
require "recording_studio_stripe/apply_allowance"
require "recording_studio_stripe/change_plan"
require "recording_studio_stripe/cancel_subscription"
require "recording_studio_stripe/resume_subscription"
require "recording_studio_stripe/process_webhook"
require "recording_studio_stripe/upsert_product"
require "recording_studio_stripe/upsert_price"
require "recording_studio_stripe/create_product"
require "recording_studio_stripe/update_product"
require "recording_studio_stripe/create_price"
require "recording_studio_stripe/paywall_policy"
require "recording_studio_stripe/register_paywall_actions"
require "recording_studio_stripe/catalog"
require "recording_studio_stripe/seed_demo_catalog"
require "recording_studio_stripe/testing/client"
require "recording_studio_stripe/admin/definitions"
require "recording_studio_stripe/admin/registration"

module RecordingStudioStripe
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end

    def register_capabilities!
      return if @capabilities_registered

      RecordingStudio.register_capability(
        :stripe,
        recording_methods: RecordingBilling,
        source: Billable
      )
      RecordingStudio.register_capability(
        :stripe_admin,
        source: AdminSupport
      )
      @capabilities_registered = true
    end
  end
end

RecordingStudioStripe.register_capabilities!
