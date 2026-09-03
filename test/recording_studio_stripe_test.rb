# frozen_string_literal: true

require "test_helper"

class RecordingStudioStripeTest < Minitest::Test
  def test_version_matches_release
    assert_equal "0.3.1", ::RecordingStudioStripe::VERSION
  end

  def test_engine_exists
    assert_kind_of Class, ::RecordingStudioStripe::Engine
  end

  def test_gemspec_pins_recording_studio_and_stripe
    gemspec = File.read(File.expand_path("../recording_studio_stripe.gemspec", __dir__))

    assert_includes gemspec, 'spec.add_dependency "recording_studio", "~> 4.1"'
    assert_includes gemspec, 'spec.add_dependency "stripe"'
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

  def test_dummy_gemfile_pins_verified_4x_github_tags
    gemfile = File.read(File.expand_path("dummy/Gemfile", __dir__))

    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio", tag: "v4.2.0"'
    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.6.0"'
    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio_admin", tag: "v2.0.2"'
    assert_includes gemfile, 'github: "bowerbird-app/RecordingStudio_root_switchable", tag: "v0.5.0"'
    assert_includes gemfile, 'github: "bowerbird-app/flatpack", tag: "v0.1.133"'
  end

  def test_template_does_not_ship_copied_core_hooks_or_base_service
    refute File.exist?(File.expand_path("../lib/recording_studio_stripe/hooks.rb", __dir__))
    refute File.exist?(File.expand_path("../lib/recording_studio_stripe/services/base_service.rb", __dir__))
    refute File.exist?(File.expand_path("../lib/recording_studio_stripe/services/example_service.rb", __dir__))
  end

  def test_dummy_app_uses_recording_studio_default_layout
    application_controller_path = File.expand_path("dummy/app/controllers/application_controller.rb", __dir__)
    controller_source = File.read(application_controller_path)

    assert_includes controller_source, "include RecordingStudio::UsesDefaultLayout"
    assert_includes controller_source, '"recording_studio/default_layout"'
    assert_includes controller_source, "devise_controller? ? \"application\""
    refute_includes controller_source, "flat_pack_sidebar"
  end

  def test_dummy_default_layout_sets_rounded_theme_on_html
    layout = File.read(File.expand_path("dummy/app/views/layouts/recording_studio/default_layout.html.erb", __dir__))

    assert_includes layout, '<html data-theme="rounded">'
    assert_includes layout, 'data-recording-studio-default-layout="true"'
    refute_includes layout, "document.documentElement.setAttribute"
  end

  def test_dummy_login_layout_keeps_flatpack_assets_without_tight_main_offset
    application_layout = File.read(File.expand_path("dummy/app/views/layouts/application.html.erb", __dir__))

    assert_includes application_layout, '<html data-theme="rounded">'
    assert_includes application_layout, 'stylesheet_link_tag "flat_pack/variables"'
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

    assert_includes tailwind_source, "bundler/gems/flatpack-*/app/components"
    assert_includes tailwind_source, "usr/local/lib/ruby/gems"
    assert_includes tailwind_source, "app/components/**/*.{rb,erb}"
    refute_includes tailwind_source, "@theme"
  end

  def test_recording_studio_keeps_strict_recordable_declarations_enabled
    initializer_path = File.expand_path("dummy/config/initializers/recording_studio.rb", __dir__)
    initializer_source = File.read(initializer_path)

    assert_includes initializer_source, "config.require_recordable_declarations = true"
    assert_includes initializer_source, "AdminRoot"
    refute_includes initializer_source, "v3"
  end

  def test_product_readme_explains_stripe_billing
    readme = File.read(File.expand_path("../README.md", __dir__))

    assert_includes readme, "RecordingStudioStripe"
    assert_includes readme, "remaining"
    assert_includes readme, "config.paywalls"
    assert_includes readme, "authorized_action?"
    assert_includes readme, "Customer Portal"
    assert_includes readme, "Stripe_secret_key"
    refute_includes readme, "ExampleService"
  end

  def test_dummy_stripe_initializer_registers_paywalls
    initializer = File.read(File.expand_path("dummy/config/initializers/recording_studio_stripe.rb", __dir__))

    assert_includes initializer, "config.paywalls"
    assert_includes initializer, "generate_image"
    assert_includes initializer, "export_csv"
    assert_includes initializer, "Configuration.env_secret_key"
  end

  def test_install_initializer_template_documents_paywalls
    template_path = "../lib/generators/recording_studio_stripe/install/templates/" \
                    "recording_studio_stripe_initializer.rb"
    template = File.read(File.expand_path(template_path, __dir__))

    assert_includes template, "config.paywalls"
    assert_includes template, "generate_image"
    assert_includes template, "Configuration.env_secret_key"
  end

  def test_billing_docs_explain_paywalls
    docs = File.read(File.expand_path("../docs/billing.md", __dir__))

    assert_includes docs, "## Paywalls"
    assert_includes docs, "config.paywalls"
    assert_includes docs, "authorized_action?"
    assert_includes docs, "Do not put them on a Price"
  end

  def test_billing_docs_explain_customer_portal
    docs = File.read(File.expand_path("../docs/billing.md", __dir__))

    assert_includes docs, "Manage billing on Stripe"
    assert_includes docs, "Customer Portal"
    assert_includes docs, "Do not copy invoices"
    assert_includes docs, "Stripe_secret_key"
    assert_includes docs, "stripe_sandbox_test.rb"
  end

  def test_billing_view_offers_manage_billing
    view_source = File.read(File.expand_path("../app/views/recording_studio_stripe/billing/show.html.erb", __dir__))

    assert_includes view_source, "Manage billing on Stripe"
    assert_includes view_source, 'icon: "credit-card"'
    assert_includes view_source, "portal_path"
    assert_match(/Grid::Component.new\(cols: 2.*CurrentPlanComponent/m, view_source)
    refute_includes view_source, "dashboard.stripe.com"
  end

  def test_current_plan_puts_active_badge_above_the_name
    source = File.read(File.expand_path("../app/components/recording_studio_stripe/current_plan_component.rb", __dir__))

    assert_includes source, "stripe_card_stack(badges, title, actions)"
    assert_includes source, "text: \"Active\", style: :primary"
  end

  def test_meter_card_shows_percent_used
    source = File.read(File.expand_path("../app/components/recording_studio_stripe/meter_card_component.rb", __dir__))

    assert_includes source, "show_label: true"
    refute_includes source, "left"
    refute_includes source, "Included"
  end

  def test_dummy_home_page_points_at_plans
    view_path = File.expand_path("dummy/app/views/home/index.html.erb", __dir__)
    view_source = File.read(view_path)

    assert_includes view_source, "See plans"
    assert_includes view_source, "dummy_page_nav"
    assert_includes view_source, "FlatPack::EmptyState::Component"
    assert_includes view_source, "Public pricing"
    assert_includes view_source, "What this plan opens"
    assert_includes view_source, "dummy_paywall_open?"
  end

  def test_plans_component_aligns_left_or_center
    component = File.read(File.expand_path("../app/components/recording_studio_stripe/plans_component.rb", __dir__))
    plans_view = File.read(File.expand_path("../app/views/recording_studio_stripe/plans/index.html.erb", __dir__))
    pricing_view = File.read(File.expand_path("dummy/app/views/pricing/show.html.erb", __dir__))

    assert_includes component, "align: :left"
    assert_includes component, "justify-start"
    assert_includes component, "justify-center"
    assert_includes plans_view, "align: :left"
    assert_includes pricing_view, "align: :center"
  end
end
