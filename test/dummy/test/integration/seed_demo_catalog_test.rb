# frozen_string_literal: true

require "test_helper"

class SeedDemoCatalogTest < ActiveSupport::TestCase
  setup do
    @previous_client = RecordingStudioStripe.configuration.client
    @previous_secret = RecordingStudioStripe.configuration.secret_key
  end

  teardown do
    reset_demo_catalog_to_local_ids
    RecordingStudioStripe.configuration.client = @previous_client
    RecordingStudioStripe.configuration.secret_key = @previous_secret
  end

  test "promotes local demo ids when a Stripe client is set" do
    RecordingStudioStripe.configuration.client = nil
    RecordingStudioStripe.configuration.secret_key = nil
    reset_demo_catalog_to_local_ids
    RecordingStudioStripe::SeedDemoCatalog.call

    pro = RecordingStudioStripe::Product.find_by!(name: "Pro")
    assert_equal "prod_local_pro", pro.stripe_id
    assert pro.monthly_price.stripe_id.start_with?("price_local_")

    RecordingStudioStripe.configuration.client = RecordingStudioStripe::Testing::Client.new
    RecordingStudioStripe::SeedDemoCatalog.call

    pro.reload
    starter = RecordingStudioStripe::Product.find_by!(name: "Starter")
    pack = RecordingStudioStripe::Product.find_by!(name: "AI token packs")
    promoted_id = pro.stripe_id

    assert promoted_id.start_with?("prod_")
    refute promoted_id.start_with?("prod_local_")
    assert starter.monthly_price.stripe_id.start_with?("price_")
    refute starter.monthly_price.stripe_id.start_with?("price_local_")
    assert pack.prices.one_time.first.stripe_id.start_with?("price_")
    assert_equal "starter", starter.metadata["recording_studio_demo"]

    RecordingStudioStripe::SeedDemoCatalog.call
    assert_equal promoted_id, RecordingStudioStripe::Product.find_by!(name: "Pro").stripe_id
  end
end
