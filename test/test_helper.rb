# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require_relative "simplecov_helper"
require "minitest/autorun"
require "rails"
require "active_support/time"
require "i18n"
Time.zone ||= "UTC"
require "recording_studio_stripe"

locale_file = File.expand_path("../config/locales/en.yml", __dir__)
I18n.load_path << locale_file unless I18n.load_path.include?(locale_file)
I18n.backend.load_translations
I18n.available_locales = Array(I18n.available_locales) | %i[en]
I18n.default_locale = :en
unless I18n.exists?("date.formats.long")
  I18n.backend.store_translations(:en, {
                                    date: { formats: { long: "%B %d, %Y" } },
                                    time: { formats: { long: "%B %d, %Y %H:%M" } }
                                  })
end
