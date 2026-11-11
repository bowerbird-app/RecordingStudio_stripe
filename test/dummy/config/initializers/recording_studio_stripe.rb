# frozen_string_literal: true

RecordingStudioStripe.configure do |config|
  config.layout = lambda { |controller:|
    "application" if controller.devise_controller?
  }
  config.plans_background_image = "/plans-backdrop.svg"
  config.site_admin_recording = lambda {
    admin_root = AdminRoot.find_by(name: "Studio Admin")
    next unless admin_root

    RecordingStudio.root_recording_for(admin_root)
  }
  config.secret_key = ENV["STRIPE_SECRET_KEY"]
  config.publishable_key = ENV["STRIPE_PUBLISHABLE_KEY"]
  config.webhook_secret = ENV["STRIPE_WEBHOOK_SECRET"]
  # Named usage counters. Defaults are ai_tokens and api_calls.
  # Add your own, then set included_<name> on each plan Price.
  # icon and plan_line are for the public plan card. %{quantity} is shortened (1m, 10k).
  config.meters = {
    "ai_tokens" => { "label" => "AI tokens", "icon" => "sparkles" },
    "api_calls" => { "label" => "API calls", "icon" => "bolt" }
  }
  # Named plan features. Tick them on a Product in Admin.
  # Check with RecordingStudioAccessible.authorized_action?(action: :generate_image, recording: root)
  config.paywalls = {
    "generate_image" => { "label" => "Generate an image", "icon" => "photo" },
    "export_csv" => { "label" => "Export CSV", "icon" => "table-cells" }
  }
  config.subscription_types = {
    "studio" => { "label" => "Studio" },
    "inbox" => { "label" => "Inbox" }
  }
  # Standing caps. aggregation defaults to count (live recordings of recordable_type).
  # The number lives on the Product. Missing or 0 means none on that plan. No billing-period reset.
  # per_item is a ceiling on one item. Omit it and nothing here changes.
  config.limits = {
    "press_kits" => {
      "label" => "Press kits",
      "recordable_type" => "PressKit",
      "subscription_type" => "studio",
      "icon" => "rectangle-stack",
      "plan_line" => "%{quantity} press kits"
    },
    "max_file_bytes" => {
      "label" => "Max file size",
      "aggregation" => "per_item",
      "unit" => "bytes",
      "subscription_type" => "studio",
      "icon" => "document",
      "plan_line" => "Up to %{quantity} per file",
      "no_plan_ceiling" => 10.megabytes
    }
  }
end
