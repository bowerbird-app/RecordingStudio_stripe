# frozen_string_literal: true

require "test_helper"
require "yaml"

class LocalesTest < Minitest::Test
  Copy = RecordingStudioStripe::Copy

  ADMIN_SAMPLE_KEYS = {
    "admin.products.new_title" => "New plan",
    "admin.products.edit_title" => "Edit %{name}",
    "admin.products.this_plan" => "This plan",
    "admin.products.what_they_get" => "What they get",
    "admin.common.save" => "Save",
    "admin.common.create" => "Create",
    "admin.prices.new_title" => "New Price",
    "admin.prices.edit_title" => "Edit Price",
    "admin.prices.edit_subtitle" => "Stripe keeps the amount. You can change included usage.",
    "admin.prices.included" => "Included %{label}",
    "admin.meters.new_title" => "New meter",
    "admin.paywalls.new_title" => "New paywall",
    "admin.trial.title" => "Paid trial",
    "admin.trial.help" => "They pay this now. The plan price starts when the trial ends.",
    "admin.limits.help" => "Blank means none. Monthly and yearly share this number.",
    "admin.plan_card.title" => "Pricing card",
    "admin.plan_card.extra_line" => "Extra line",
    "admin.plan_card.what_it_says" => "What it says"
  }.freeze

  def test_engine_ships_only_english_locale_files
    files = Dir[File.join(engine_locales_dir, "*")].map { |path| File.basename(path) }

    assert_equal ["en.yml"], files.sort
  end

  def test_rails_i18n_load_path_includes_the_gem_english_locale_file
    locale_path = File.join(engine_locales_dir, "en.yml")

    assert_includes I18n.load_path.map { |path| File.expand_path(path) }, File.expand_path(locale_path)
  end

  def test_dummy_french_covers_every_engine_english_key
    english = flatten_keys(locale_tree(File.join(engine_locales_dir, "en.yml"), "en"))
    french = flatten_keys(locale_tree(File.join(dummy_locales_dir, "fr.yml"), "fr"))
    missing = english - french

    assert_empty missing, "dummy fr.yml is missing keys present in engine en.yml: #{missing.join(', ')}"
  end

  def test_english_default_copy_is_unchanged
    I18n.with_locale(:en) do
      assert_equal "Pricing", Copy.t("plans.title")
      assert_equal "Monthly or yearly. You can switch later.", Copy.t("plans.subtitle")
      assert_equal "Current plan", Copy.t("plans.current_plan")
      assert_equal "You’re on the new plan.", Copy.t("notices.on_new_plan")
      assert_equal "Pick a plan from the list.", Copy.t("alerts.pick_plan")
      assert_equal "You keep it until October 12, 2026.",
                   Copy.t("cancel.subtitle_until", date: Copy.long_date(Date.new(2026, 10, 12)))
    end
  end

  def test_english_admin_keys_resolve_without_missing_translations
    I18n.with_locale(:en) do
      ADMIN_SAMPLE_KEYS.each do |key, english|
        full_key = "recording_studio.stripe.#{key}"
        translation = I18n.t(full_key, default: nil)

        assert_equal english, translation, "#{full_key} should resolve to #{english.inspect}"
        assert_equal english, I18n.t(full_key, raise: true)
      end

      assert_equal "Edit Pro", I18n.t("recording_studio.stripe.admin.products.edit_title", name: "Pro")
      assert_equal "For Pro.", I18n.t("recording_studio.stripe.admin.prices.new_subtitle_for", name: "Pro")
      assert_equal "Included ai tokens",
                   I18n.t("recording_studio.stripe.admin.prices.included", label: "ai tokens")
    end
  end

  def test_en_yml_nests_keys_under_recording_studio_stripe
    tree = YAML.safe_load_file(File.join(engine_locales_dir, "en.yml"), aliases: true)
               .fetch("en")
               .fetch("recording_studio")
               .fetch("stripe")

    assert tree.key?("admin")
    assert tree.fetch("admin").key?("products")
    refute tree.key?("recording_studio_stripe")
  end

  def test_no_legacy_top_level_recording_studio_stripe_locale_namespace
    tree = YAML.safe_load_file(File.join(engine_locales_dir, "en.yml"), aliases: true).fetch("en")

    refute tree.key?("recording_studio_stripe")
    assert_nil I18n.t("recording_studio_stripe.admin.products.new_title", default: nil)
  end

  def test_host_nested_override_wins_without_legacy_key
    I18n.backend.store_translations(:en, recording_studio: { stripe: { admin: { products: { new_title: "Acme plan" } } } })

    assert_equal "Acme plan", I18n.t("recording_studio.stripe.admin.products.new_title")
  ensure
    I18n.backend.store_translations(:en, recording_studio: { stripe: { admin: { products: { new_title: "New plan" } } } })
  end

  def test_component_text_overrides_win_including_nil
    assert_equal "Pricing", Copy.value(Copy::UNSET, "plans.title")
    assert_equal "Acme plans", Copy.value("Acme plans", "plans.title")
    assert_nil Copy.value(nil, "plans.title")
  end

  def test_host_translation_overrides_english
    I18n.backend.store_translations(:en, acme_title)
    assert_equal "Acme plans", Copy.t("plans.title")
  ensure
    I18n.backend.store_translations(:en, default_title)
  end

  private

  def engine_locales_dir
    File.expand_path("../config/locales", __dir__)
  end

  def dummy_locales_dir
    File.expand_path("dummy/config/locales", __dir__)
  end

  def locale_tree(path, locale)
    yaml = YAML.safe_load_file(path, aliases: true)
    yaml.fetch(locale).fetch("recording_studio").fetch("stripe")
  end

  def flatten_keys(hash, prefix = [])
    hash.flat_map do |key, value|
      path = prefix + [key.to_s]
      value.is_a?(Hash) ? flatten_keys(value, path) : [path.join(".")]
    end
  end

  def acme_title
    { recording_studio: { stripe: { plans: { title: "Acme plans" } } } }
  end

  def default_title
    { recording_studio: { stripe: { plans: { title: "Pricing" } } } }
  end
end
