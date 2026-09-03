# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

require_relative "../config/environment"
require "rails/test_help"

module StripeBillingTestHelpers
  def grant_owner_access!(recording:, actor:, role: :admin)
    return if RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: role)

    RecordingStudioAccessible::AccessCreationContext.allow do
      RecordingStudio.root_recording_or_self(recording).record(
        RecordingStudio::Access,
        parent_recording: recording
      ) do |access|
        access.actor = actor
        access.role = role
      end
    end
  end

  def reset_demo_catalog_to_local_ids
    RecordingStudioStripe::Product.find_each do |product|
      local_id = "prod_local_#{product.name.parameterize.underscore}"
      product.update_column(:stripe_id, local_id) unless product.stripe_id == local_id
      product.prices.find_each do |price|
        local_price_id = "price_local_#{product.name.parameterize.underscore}_#{price.interval || 'once'}_#{price.unit_amount}"
        price.update_column(:stripe_id, local_price_id) unless price.stripe_id == local_price_id
      end
    end
  end
end

ActiveSupport::TestCase.include StripeBillingTestHelpers

# Dummy tests stay in local mode. stripe_sandbox_test.rb restores test-mode keys
# in setup. Keep the process env so that file can read Stripe_secret_key.
RecordingStudioStripe.configuration.secret_key = nil
RecordingStudioStripe.configuration.publishable_key = nil
RecordingStudioStripe.configuration.webhook_secret = nil
RecordingStudioStripe.configuration.client = nil

class ActionDispatch::IntegrationTest
  include StripeBillingTestHelpers

  MODERN_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"

  def switch_to_root!(recording)
    patch "/recording_studio_root_switchable/v1/root_switch", params: {
      scope: "all_workspaces",
      root_switch: {
        root_recording_id: recording.id,
        return_to: "/"
      }
    }
    follow_redirect! if response.redirect?
    get "/up"
  end

  %i[get post patch put delete head].each do |http_method|
    define_method(http_method) do |path, **args|
      headers = args.fetch(:headers, {}).dup
      headers["User-Agent"] ||= MODERN_USER_AGENT
      super(path, **args.merge(headers: headers))
    end
  end
end
