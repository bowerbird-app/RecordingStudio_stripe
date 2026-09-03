# frozen_string_literal: true

require "test_helper"
require "devise/test/integration_helpers"

class WebhooksTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    RecordingStudioStripe::SeedDemoCatalog.call
    @user = User.find_or_create_by!(email: "admin@admin.com") do |user|
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    @workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
    @root = RecordingStudio.root_recording_for(@workspace)
  end

  test "checkout.session.completed grants an allowance pack" do
    price = RecordingStudioStripe::Price.one_time.find_by!("metadata ->> 'allowance' = '5000000'")

    post "/webhooks/stripe",
         params: stripe_event(
           "evt_allowance_1",
           "checkout.session.completed",
           {
             "id" => "cs_test_allowance",
             "mode" => "payment",
             "client_reference_id" => @root.id.to_s,
             "metadata" => {
               "root_recording_id" => @root.id.to_s,
               "price_id" => price.stripe_id
             }
           }
         ),
         as: :json

    assert_response :success
    meter = @workspace.billing.meter(:ai_tokens)
    assert_equal 5_000_000, meter.purchased
  end

  test "customer.subscription.created projects the Subscription" do
    price = RecordingStudioStripe::Product.find_by!(name: "Pro").monthly_price

    post "/webhooks/stripe",
         params: stripe_event(
           "evt_sub_1",
           "customer.subscription.created",
           {
             "id" => "sub_test_pro",
             "customer" => "cus_test_pro",
             "status" => "active",
             "cancel_at_period_end" => false,
             "metadata" => { "root_recording_id" => @root.id.to_s },
             "items" => {
               "data" => [
                 {
                   "id" => "si_test_pro",
                   "price" => { "id" => price.stripe_id },
                   "current_period_start" => 1.day.ago.to_i,
                   "current_period_end" => 29.days.from_now.to_i
                 }
               ]
             }
           }
         ),
         as: :json

    assert_response :success
    subscription = @workspace.billing.subscription
    assert_predicate subscription, :active?
    assert_equal price.id, subscription.price_id
    assert_equal "si_test_pro", subscription.metadata["stripe_item_id"]
  end

  test "duplicate Stripe event ids are ignored" do
    price = RecordingStudioStripe::Product.find_by!(name: "Starter").monthly_price
    payload = stripe_event(
      "evt_dup_1",
      "customer.subscription.created",
      {
        "id" => "sub_dup",
        "customer" => "cus_dup",
        "status" => "active",
        "cancel_at_period_end" => false,
        "metadata" => { "root_recording_id" => @root.id.to_s },
        "items" => { "data" => [{ "id" => "si_dup", "price" => { "id" => price.stripe_id } }] }
      }
    )

    post "/webhooks/stripe", params: payload, as: :json
    post "/webhooks/stripe", params: payload, as: :json

    assert_response :success
    assert_equal 1, RecordingStudioStripe::WebhookEvent.where(stripe_id: "evt_dup_1").count
  end

  private

  def stripe_event(id, type, object)
    { "id" => id, "object" => "event", "type" => type, "data" => { "object" => object } }
  end
end
