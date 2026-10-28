# frozen_string_literal: true

require "test_helper"

class RecordingStudioStripeTest < Minitest::Test
  def test_version_matches_release
    assert_equal "0.17.0", ::RecordingStudioStripe::VERSION
  end

  def test_engine_exists
    assert_kind_of Class, ::RecordingStudioStripe::Engine
  end

  def test_gemspec_pins_recording_studio_accessible_and_stripe
    gemspec = File.read(File.expand_path("../recording_studio_stripe.gemspec", __dir__))

    assert_includes gemspec, 'spec.add_dependency "flat_pack", ">= 0.1.327"'
    assert_includes gemspec, 'spec.add_dependency "recording_studio", ">= 6.2.0"'
    assert_includes gemspec, 'spec.add_dependency "recording_studio_accessible", "~> 0.22"'
    assert_includes gemspec, 'spec.add_dependency "view_component", ">= 4.14", "< 5"'
    assert_includes gemspec, 'spec.add_dependency "stripe"'
    refute_includes gemspec, "recording_studio_conversions"
    refute_includes gemspec, "attachable"
    refute_includes gemspec, "recording_studio_library"
  end

  def test_gemspec_excludes_cursor_config
    spec = Gem::Specification.load(File.expand_path("../recording_studio_stripe.gemspec", __dir__))
    cursor_files = spec.files.select { |path| path == ".cursor" || path.split("/").include?(".cursor") }

    assert_empty cursor_files, "gemspec must not package .cursor/ (got #{cursor_files.inspect})"
  end

  def test_cursor_environment_is_repo_managed_without_snapshot
    path = File.expand_path("../.cursor/environment.json", __dir__)
    json = JSON.parse(File.read(path))

    assert_equal "recording-studio-stripe", json["name"]
    assert_equal ".cursor/install.sh", json["install"]
    assert_equal ".cursor/start.sh", json["start"]
    refute json.key?("snapshot"), "snapshot pins a Personal build and skips install"
    refute json.key?("agentCanUpdateSnapshot")
  end

  def test_cursor_install_still_fetches_skills
    install_script = File.read(File.expand_path("../.cursor/install.sh", __dir__))

    assert_includes install_script, "fetch-skills.sh"
  end

  def test_dummy_gemfile_pins_recording_studio_6_2
    gemfile = File.read(File.expand_path("dummy/Gemfile", __dir__))

    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio", tag: "v6.2.0"'
    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.22.0"'
    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio_admin", tag: "v2.7.0"'
    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio_trashable", tag: "v0.12.0"'
    assert_includes gemfile, 'ref: "8dd47257db449120496ad64ed2ce68af600dd6cd"'
    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio_metrics", tag: "v0.6.1"'
    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio_cache", tag: "v0.5.1"'
    assert_includes gemfile, 'github: "bowerbird-app/flatpack", tag: "v0.1.327"'
    assert_includes gemfile, 'gem "view_component", "4.19.0"'
    assert_includes gemfile, "widen_recording_studio_requirement"
    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio_Internationalization", tag: "v0.1.7"'
  end

  def test_root_gemfile_pins_accessible_and_recording_studio_6_2
    gemfile = File.read(File.expand_path("../Gemfile", __dir__))

    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio", tag: "v6.2.0"'
    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.22.0"'
    assert_includes gemfile, 'github: "bowerbird-app/flatpack", tag: "v0.1.327"'
    assert_includes gemfile, 'gem "view_component", "4.19.0"'
    assert_includes gemfile, "widen_recording_studio_requirement"
  end

  def test_lockfiles_pin_flat_pack_0_1_327
    ["../Gemfile.lock", "dummy/Gemfile.lock"].each do |path|
      lock = File.read(File.expand_path(path, __dir__))

      assert_includes lock, "flat_pack (0.1.327)"
      assert_includes lock, "tag: v0.1.327"
    end
  end

  def test_billing_application_controller_protects_forgery_before_controller_auth
    path = File.expand_path(
      "../app/controllers/recording_studio_stripe/application_controller.rb",
      __dir__
    )
    source = File.read(path)
    forgery_at = source.index("protect_from_forgery with: :exception, prepend: true")
    auth_at = source.index("include RecordingStudioAccessible::ControllerAuth")

    assert forgery_at, "expected protect_from_forgery with prepend: true"
    assert auth_at, "expected ControllerAuth include"
    assert_operator forgery_at, :<, auth_at
    assert_includes source, "recording_studio_auth("
    assert_includes source, "authenticate: false"
    assert_includes source, "def authorize_role!(role)"
    assert_includes source, "configuration.authenticate"
  end

  def test_template_does_not_ship_copied_core_hooks_or_base_service
    refute File.exist?(File.expand_path("../lib/recording_studio_stripe/hooks.rb", __dir__))
    refute File.exist?(File.expand_path("../lib/recording_studio_stripe/services/base_service.rb", __dir__))
    refute File.exist?(File.expand_path("../lib/recording_studio_stripe/services/example_service.rb", __dir__))
  end

  def test_dummy_app_uses_recording_studio_default_layout
    application_controller_path = File.expand_path("dummy/app/controllers/application_controller.rb", __dir__)
    controller_source = File.read(application_controller_path)

    assert_includes controller_source, "recording_studio_layout { RecordingStudioStripe.configuration.layout }"
    refute_includes controller_source, "UsesDefaultLayout"
    refute_includes controller_source, 'layout "recording_studio/default_layout"'
    refute_includes controller_source, "flat_pack_sidebar"
  end

  def test_dummy_home_uses_sidebar_layout
    home_controller = File.read(File.expand_path("dummy/app/controllers/home_controller.rb", __dir__))
    layout = File.read(File.expand_path("dummy/app/views/layouts/sidebar.html.erb", __dir__))
    top_nav = File.read(File.expand_path("dummy/app/views/layouts/_sidebar_top_nav.html.erb", __dir__))

    assert_includes home_controller, 'layout "sidebar"'
    assert_includes layout, "FlatPack::SidebarLayout::Component"
    assert_includes layout, 'data-theme="rounded"'
    assert_includes layout, 'data-dummy-sidebar-layout="true"'
    refute_includes layout, "data-recording-studio-default-layout"
    refute_includes top_nav, "dummy_language_selector"
    refute_includes top_nav, "recording_studio_language_selector"
    assert_includes top_nav, "recording_studio_root_switch_dropdown"
    public_layout = File.read(File.expand_path("dummy/app/views/layouts/public.html.erb", __dir__))
    refute_includes public_layout, "dummy_language_selector"
    refute_includes public_layout, "recording_studio_language_selector"
  end

  def test_dummy_does_not_override_the_recording_studio_default_layout
    override = File.expand_path("dummy/app/views/layouts/recording_studio/default_layout.html.erb", __dir__)

    refute File.exist?(override), "dummy should render Recording Studio's default layout"
  end

  def test_customer_screens_set_close_to_home
    billing = File.read(File.expand_path("../app/views/recording_studio_stripe/billing/show.html.erb", __dir__))
    usage = File.read(File.expand_path("../app/views/recording_studio_stripe/usage/show.html.erb", __dir__))
    plans = File.read(File.expand_path("../app/views/recording_studio_stripe/plans/index.html.erb", __dir__))
    change = File.read(File.expand_path("../app/views/recording_studio_stripe/subscriptions/edit.html.erb", __dir__))

    assert_includes billing, "anchor_href: main_app.root_path"
    assert_includes billing, "content_for :title"
    refute_includes billing, "back_href:"
    refute_includes billing, "PageTitle::Component"
    assert_includes usage, "anchor_href: main_app.root_path"
    assert_includes usage, "title: nil"
    refute_includes usage, "back_href:"
    assert_includes plans, "anchor_href: main_app.root_path"
    assert_includes plans, "align: :center"
    assert_includes plans, "recording_studio.stripe.plans.title"
    assert_includes plans, "recording_studio.stripe.plans.subtitle"
    assert_includes plans, "recording_studio_background_image"
    assert_includes plans, "plans_background_image"
    refute_includes plans, "title: nil"
    refute_includes plans, "content_for :title"
    refute_includes plans, "back_href:"
    assert_includes change, "anchor_href: main_app.root_path"
    assert_includes change, "back_href: main_app.plans_path"
    assert_includes change, "@change.title"
    assert_includes change, "@change.subtitle"
  end

  def test_dummy_login_layout_keeps_flatpack_assets_without_tight_main_offset
    application_layout = File.read(File.expand_path("dummy/app/views/layouts/application.html.erb", __dir__))

    assert_includes application_layout, 'data-theme="rounded"'
    assert_includes application_layout, "dummy_locale_attributes"
    assert_includes application_layout, 'stylesheet_link_tag "flat_pack/variables"'
    assert_includes application_layout, 'stylesheet_link_tag "flat_pack/application"'
    assert_includes application_layout, "javascript_importmap_tags"
    assert_includes application_layout, "min-h-screen"
    refute_includes application_layout, "mt-28"
    refute_includes application_layout, "flat_pack_sidebar"
  end

  def test_dummy_importmap_pins_admin_screen_controllers
    importmap = File.read(File.expand_path("dummy/config/importmap.rb", __dir__))

    assert_includes importmap, "@hotwired/turbo-rails"
    assert_includes importmap, "controllers/recording_studio_admin"
  end

  def test_dummy_tailwind_scans_engine_components
    tailwind_source = File.read(File.expand_path("dummy/app/assets/tailwind/application.css", __dir__))

    assert_includes tailwind_source, '@source "./gem_sources/flat_pack/app/components"'
    assert_includes tailwind_source, '@source "./gem_sources/recording_studio_admin/app/views"'
    assert_includes tailwind_source, '@source "../../views"'
    assert_includes tailwind_source, '@source "../../../../../app/components"'
    refute_includes tailwind_source, "bundler/gems/flatpack-*"
    refute_includes tailwind_source, "@theme"
    linker = File.read(File.expand_path("dummy/lib/tailwind_gem_sources.rb", __dir__))
    gem_names = %w[
      flat_pack
      recording_studio
      recording_studio_admin
      recording_studio_accessible
      recording_studio_root_switchable
      recording_studio_logs
    ]
    gem_names.each do |gem_name|
      assert_includes linker, gem_name
    end
  end

  def test_recording_studio_keeps_strict_recordable_declarations_enabled
    initializer_path = File.expand_path("dummy/config/initializers/recording_studio.rb", __dir__)
    initializer_source = File.read(initializer_path)

    assert_includes initializer_source, "config.require_recordable_declarations = true"
    assert_includes initializer_source, "AdminRoot"
    assert_includes initializer_source, "PressKit"
    refute_includes initializer_source, "v3"
  end

  def test_product_readme_explains_stripe_billing
    readme = File.read(File.expand_path("../README.md", __dir__))

    assert_includes readme, "RecordingStudioStripe"
    assert_includes readme, "remaining"
    assert_includes readme, "config.paywalls"
    assert_includes readme, "config.limits"
    assert_includes readme, "aggregation"
    assert_includes readme, "register_limit_usage"
    assert_includes readme, "with_capacity!"
    assert_includes readme, "authorized_action?"
    assert_includes readme, "Customer Portal"
    assert_includes readme, ":stripe"
    assert_includes readme, "/billing/usage"
    assert_includes readme, "UsageComponent"
    assert_includes readme, "recording_studio.stripe"
    assert_includes readme, "config.layout"
    assert_includes readme, ">= 6.2.0"
    refute_includes readme, "ExampleService"
  end

  def test_dummy_stripe_initializer_registers_paywalls
    initializer = File.read(File.expand_path("dummy/config/initializers/recording_studio_stripe.rb", __dir__))

    assert_includes initializer, "config.paywalls"
    assert_includes initializer, "generate_image"
    assert_includes initializer, "export_csv"
    assert_includes initializer, "config.subscription_types"
    assert_includes initializer, "studio"
    assert_includes initializer, "config.limits"
    assert_includes initializer, "press_kits"
    assert_includes initializer, "PressKit"
    assert_includes initializer, "plan_line"
    assert_includes initializer, "rectangle-stack"
    assert_includes initializer, "plans_background_image"
    assert_includes initializer, "/plans-backdrop.svg"
  end

  def test_install_initializer_template_documents_paywalls
    template_path = "../lib/generators/recording_studio_stripe/install/templates/" \
                    "recording_studio_stripe_initializer.rb"
    template = File.read(File.expand_path(template_path, __dir__))

    assert_includes template, "config.paywalls"
    assert_includes template, "generate_image"
    assert_includes template, "config.subscription_types"
    assert_includes template, "config.limits"
    assert_includes template, "recordable_type"
    assert_includes template, "plan_line"
    assert_includes template, "limit_reached_path"
    assert_includes template, "usage_path"
    assert_includes template, "usage_costs"
    assert_includes template, "plans_background_image"
    refute_includes template, "media_monitoring"
  end

  def test_readme_explains_domain_events
    readme = File.read(File.expand_path("../README.md", __dir__))

    assert_includes readme, "trial_started.recording_studio_stripe"
    assert_includes readme, "invoice_paid.recording_studio_stripe"
    assert_includes readme, "ProcessWebhook.replay"
    assert_includes readme, "kind` is `trial_fee"
    assert_includes readme, "does not call Stripe"
    assert_includes readme, "first_payment"
  end

  def test_billing_docs_explain_paywalls
    docs = File.read(File.expand_path("../docs/billing.md", __dir__))

    assert_includes docs, "## Paywalls"
    assert_includes docs, "config.paywalls"
    assert_includes docs, "authorized_action?"
    assert_includes docs, "Do not put them on a Price"
    assert_includes docs, "## Plan groups"
    assert_includes docs, "config.subscription_types"
    assert_includes docs, "## Limits"
    assert_includes docs, "config.limits"
    assert_includes docs, "PlanLimitReached"
    assert_includes docs, "limit_press_kits"
    assert_includes docs, "aggregation"
    assert_includes docs, "register_limit_usage"
    assert_includes docs, "with_capacity!"
    assert_includes docs, "storage_bytes"
    assert_includes docs, "plan_card"
    assert_includes docs, "plan_line"
    assert_includes docs, "## Paid trials"
    assert_includes docs, "trial_period_days"
    assert_includes docs, "kind=trial_fee"
    assert_includes docs, "usage_costs"
    assert_includes docs, "spend_usage"
    assert_includes docs, "included_credits"
    assert_includes docs, "AmbiguousSubscriptionLine"
    assert_includes docs, "SubscriptionLineRequired"
  end

  def test_billing_docs_explain_customer_portal
    docs = File.read(File.expand_path("../docs/billing.md", __dir__))

    assert_includes docs, "Manage billing on Stripe"
    assert_includes docs, ":stripe"
    assert_includes docs, "register_style"
    assert_includes docs, "recording_studio_stripe/button"
    assert_includes docs, "Customer Portal"
    assert_includes docs, "Do not copy invoices"
    assert_includes docs, "spend"
    assert_includes docs, "503"
    assert_includes docs, "automatic_tax"
    assert_includes docs, "confirmation"
    assert_includes docs, "/billing/usage"
    assert_includes docs, "UsageComponent"
    assert_includes docs, "config.usage_path"
    assert_includes docs, "used/included"
    assert_includes docs, "See usage"
    assert_includes docs, "Breakdown"
  end

  def test_billing_view_offers_manage_billing
    view_source = File.read(File.expand_path("../app/views/recording_studio_stripe/billing/show.html.erb", __dir__))
    controller = File.read(
      File.expand_path("../app/controllers/recording_studio_stripe/billing_controller.rb", __dir__)
    )

    assert_includes view_source, "recording_studio.stripe.billing.manage"
    assert_includes view_source, 'icon: "credit-card"'
    assert_includes view_source, "style: :stripe"
    assert_includes view_source, 'stylesheet_link_tag "recording_studio_stripe/button"'
    assert_includes view_source, "portal_path"
    assert_includes view_source, "style: :secondary"
    assert_includes view_source, "@waiting_on_stripe"
    assert_includes view_source, "@confirming_allowance"
    assert_includes view_source, "can_manage: @show_manage_billing"
    assert_includes view_source, "recording_studio.stripe.billing.see_usage"
    assert_includes view_source, "@show_see_usage"
    assert_includes view_source, "usage_path"
    refute_includes view_source, "SectionTitle"
    refute_includes view_source, "Need a bit more"
    refute_includes view_source, "AllowanceCardComponent"
    refute_includes view_source, "@allowance_prices"
    refute_includes view_source, "LimitCardComponent"
    refute_includes view_source, "MeterCardComponent"
    refute_includes view_source, "usage_section_title"
    assert_match(/Grid::Component.new\(cols: 2.*CurrentPlanComponent/m, view_source)
    refute_includes view_source, "Add press kit"
    refute_includes view_source, "press_kits_path"
    refute_includes view_source, "dashboard.stripe.com"
    assert_includes controller, "@show_see_usage = show_see_usage?"
    assert_includes controller, "helpers.usage_in_use?(billing)"
  end

  def test_usage_view_renders_caps_and_meters
    view_source = File.read(File.expand_path("../app/views/recording_studio_stripe/usage/show.html.erb", __dir__))
    component = File.read(File.expand_path("../app/components/recording_studio_stripe/usage_component.rb", __dir__))
    rescue_source = File.read(File.expand_path("../lib/recording_studio_stripe/plan_limit_rescue.rb", __dir__))

    assert_includes view_source, "UsageComponent"
    assert_includes view_source, "anchor_href: main_app.root_path"
    assert_includes view_source, "content_for :title"
    refute_includes view_source, "CurrentPlanComponent"
    refute_includes view_source, "Manage billing on Stripe"
    assert_includes component, "LimitCardComponent"
    assert_includes component, "MeterCardComponent"
    refute_includes component, "usage_section_title"
    refute_includes component, "SectionTitle"
    assert_includes component, "cols: 1"
    assert_includes component, "w-full"
    assert_includes rescue_source, "recording_studio_stripe_usage_url"
    assert_includes rescue_source, "usage_path"
    refute_includes rescue_source, "recording_studio_stripe_billing_url"
  end

  def test_stripe_button_style_paints_official_brand_colours
    css = File.read(File.expand_path("../app/assets/stylesheets/recording_studio_stripe/button.css", __dir__))

    assert_includes css, 'data-fp-style="stripe"'
    assert_includes css, "#635bff"
    assert_includes css, "#0a2540"
    assert_includes css, "--fp-button-background"
    assert_includes css, "--fp-button-hover-background"
    assert_includes css, "--fp-button-text"
    assert_includes css, "--fp-button-border"
  end

  def test_current_plan_puts_status_badges_above_the_name
    source = File.read(File.expand_path("../app/components/recording_studio_stripe/current_plan_component.rb", __dir__))

    assert_includes source, "stripe_card_stack(heading, timing, actions)"
    assert_includes source, 'Copy.t("billing.current")'
    assert_includes source, "show_group_label?"
    refute_includes source, "show_type_badge?"
    assert_includes source, "SubscriptionTypes.keys.size > 1"
    assert_includes source, "text-[length:var(--text-xs)]"
    assert_includes source, "justify-between"
    assert_includes source, "justify-end"
    refute_includes source, "badge(\"Active\", :primary)"
    assert_includes source, 'Copy.t("billing.past_due_badge")'
    assert_includes source, 'badge(Copy.t("billing.trial_badge"), :primary)'
    assert_includes source, "variant: :h2"
    refute_includes source, "variant: :h3"
    refute_includes source, 'badge(Copy.t("billing.trial_badge"), :info)'
    refute_includes source, "subscription_type_label, :info"
    assert_includes source, 'Copy.t("billing.renews_in"'
    assert_includes source, 'Copy.t("billing.trial_ends_in"'
    assert_includes source, 'Copy.t("billing.update_card")'
    assert_includes source, "stay_on_named"
    assert_includes source, "subscription_cancel_confirm_path"
    refute_includes source, "subscription_cancel_path"
  end

  def test_meter_card_shows_percent_used
    source = File.read(File.expand_path("../app/components/recording_studio_stripe/meter_card_component.rb", __dir__))

    assert_includes source, "show_label: true"
    refute_includes source, "left"
    refute_includes source, "Included"
  end

  def test_meter_card_offers_breakdown_when_include_and_packs_combine
    source = File.read(File.expand_path("../app/components/recording_studio_stripe/meter_card_component.rb", __dir__))

    assert_includes source, "combined?"
    assert_includes source, 'Copy.t("usage.breakdown")'
    assert_includes source, "style: :default"
    assert_includes source, 'Copy.t("usage.on_this_plan")'
    assert_includes source, 'Copy.t("usage.extra_packs")'
    assert_includes source, 'Copy.t("usage.total_this_period")'
  end

  def test_limit_card_shows_used_of_included_when_over
    source = File.read(File.expand_path("../app/components/recording_studio_stripe/limit_card_component.rb", __dir__))

    assert_includes source, "amount_text"
    assert_includes source, "stripe_card_stack(title, amount, details, over_hint)"
    assert_includes source, 'Copy.t("usage.used_of_included"'
    assert_includes source, "over?"
    assert_includes source, 'Copy.t("usage.over_hint")'
    refute_includes source, " of "
  end

  def test_dummy_home_page_points_at_plans
    view_path = File.expand_path("dummy/app/views/home/index.html.erb", __dir__)
    view_source = File.read(view_path)
    sidebar = File.read(File.expand_path("dummy/app/views/layouts/_sidebar_nav.html.erb", __dir__))

    assert_includes view_source, "See pricing"
    refute_includes view_source, "dummy_page_nav"
    assert_includes view_source, "FlatPack::EmptyState::Component"
    assert_includes sidebar, "Public pricing"
    assert_includes sidebar, "press_kits_path"
    assert_includes sidebar, "plans_path"
    assert_includes sidebar, 'text: "Pricing"'
    assert_includes sidebar, "dummy_billing_path"
    assert_includes sidebar, "dummy_usage_path"
    refute_includes view_source, "Add press kit"
    refute_includes view_source, "What this plan opens"
    refute_includes view_source, "dummy_paywall_open?"
    refute_includes view_source, "CurrentPlanComponent"
    refute_includes view_source, "LimitCardComponent"
    refute_includes view_source, "MeterCardComponent"
  end

  def test_plan_card_lists_product_limits_before_meter_inclusions
    source = File.read(File.expand_path("../app/helpers/recording_studio_stripe/application_helper.rb", __dir__))
    card = File.read(File.expand_path("../app/components/recording_studio_stripe/plan_card_component.rb", __dir__))
    features = File.read(File.expand_path("../lib/recording_studio_stripe/plan_features.rb", __dir__))
    candidates = File.read(File.expand_path("../lib/recording_studio_stripe/plan_feature_candidates.rb", __dir__))

    assert_includes source, "PlanFeatures.for"
    assert_includes source, "stripe_plan_feature_lines"
    assert_includes source, "stripe_plan_intervals"
    assert_includes source, "usage_in_use?"
    assert_includes source, "line_has_recorded_usage?"
    assert_includes card, "stripe_plan_feature_lines"
    assert_includes card, "FlatPack::List::Component.new(spacing: :dense, divider: true)"
    assert_includes card, "FlatPack::List::Item"
    assert_includes card, "SUBGRID_ROWS"
    assert_includes card, "grid-rows-subgrid"
    assert_includes card, "row-span-4"
    assert_includes card, "[grid-template-rows:subgrid]!"
    assert_includes card, "safe_join([title, price_row, action_row, inclusions])"
    refute_includes card, "card.footer"
    assert_includes card, "CARDS_ACTION"
    assert_includes card, "subscription_change_path"
    assert_includes card, 'Copy.t("plans.downgrade")'
    refute_includes card, "Switch at renewal"
    assert_includes features, "PlanFeatureCandidates"
    assert_includes candidates, "paywall:"
    assert_includes candidates, "limit:"
    assert_includes candidates, "meter:"
  end

  def test_plan_change_confirms_price_without_the_old_plan
    source = File.read(File.expand_path("../app/components/recording_studio_stripe/plan_change_component.rb", __dir__))

    refute_includes source, "PageTitle::Component"
    refute_includes source, "Grid::Component"
    refute_includes source, "from_price"
  end

  def test_plans_component_aligns_left_or_center
    component = File.read(File.expand_path("../app/components/recording_studio_stripe/plans_component.rb", __dir__))
    plans_view = File.read(File.expand_path("../app/views/recording_studio_stripe/plans/index.html.erb", __dir__))
    pricing_view = File.read(File.expand_path("dummy/app/views/pricing/show.html.erb", __dir__))

    assert_includes component, "ALIGNS = %i[left center]"
    assert_includes component, "align: :center"
    assert_includes component, "title: Copy::UNSET"
    assert_includes component, 'Copy.t("plans.empty_title")'
    assert_includes component, "Grid::Component"
    assert_includes component, "align: :stretch"
    assert_includes component, "h-full"
    assert_includes component, "PlanCardComponent::SUBGRID_ROWS"
    assert_includes component, "row-gap: 1rem"
    assert_includes component, "text-center"
    assert_includes component, 'Copy.value(@subtitle, "plans.subtitle").presence'
    assert_includes component, "fp-on-backdrop"
    assert_includes component, "show_group_headings?"
    assert_includes component, "populated_groups"
    assert_includes component, "shared_interval_pills"
    assert_includes component, "PILL_TRACK_CLASS"
    display = File.read(File.expand_path("../lib/recording_studio_stripe/plan_card_display.rb", __dir__))
    assert_includes display, "track: true"
    assert_includes display, "style: :primary"
    assert_includes display, "PlansComponent::PILL_TRACK_CLASS"
    assert_includes component, "intervals:"
    assert_includes component, "Catalog.sorted_plans"
    assert_includes plans_view, "align: :center"
    assert_includes plans_view, "recording_studio.stripe.plans.title"
    refute_includes plans_view, "title: \"Plans\""
    assert_includes pricing_view, "align: :center"
  end

  def test_catalog_orders_plan_products_by_price
    source = File.read(File.expand_path("../lib/recording_studio_stripe/catalog.rb", __dir__))

    assert_includes source, "sorted_plans"
    assert_includes source, "unit_amount"
    refute_includes source, "order(:name)"
  end

  def test_admin_plan_edit_names_the_plan_and_hides_card_keys
    edit = File.read(File.expand_path("../app/views/recording_studio_stripe/admin/products/edit.html.erb", __dir__))
    new_view = File.read(File.expand_path("../app/views/recording_studio_stripe/admin/products/new.html.erb", __dir__))
    card = File.read(
      File.expand_path("../app/views/recording_studio_stripe/admin/products/_plan_card.html.erb", __dir__)
    )
    helper = File.read(File.expand_path("../app/helpers/recording_studio_stripe/application_helper.rb", __dir__))

    assert_includes edit, 't("recording_studio.stripe.admin.products.edit_title"'
    assert_includes edit, 't("recording_studio.stripe.admin.products.this_plan")'
    assert_includes edit, 't("recording_studio.stripe.admin.products.what_they_get")'
    assert_includes edit, 't("recording_studio.stripe.admin.common.save")'
    assert_includes new_view, 't("recording_studio.stripe.admin.products.new_title")'
    assert_includes new_view, 't("recording_studio.stripe.admin.products.kind_label")'
    assert_includes card, "Collapse::Component"
    assert_includes card, 't("recording_studio.stripe.admin.plan_card.title")'
    assert_includes card, 't("recording_studio.stripe.admin.plan_card.extra_line")'
    assert_includes card, 't("recording_studio.stripe.admin.plan_card.what_it_says")'
    refute_includes card, "Also show"
    refute_includes card, "label: \"Key\""
    assert_includes helper, "stripe_plan_card_open?"
    assert_includes helper, "stripe_plan_card_extra_rows"
  end
end
