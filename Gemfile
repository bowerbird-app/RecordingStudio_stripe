# frozen_string_literal: true

source "https://rubygems.org"

require_relative "test/support/widen_recording_studio_requirement"

# Specify your gem's dependencies in recording_studio_stripe.gemspec
gemspec

# These gems resolve from GitHub.
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.329"
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v6.2.0"
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.22.0"
gem "recording_studio_metrics", github: "bowerbird-app/RecordingStudio_metrics", tag: "v0.6.1", require: false
# Required by accessible >= 0.22.0 (not on RubyGems)
gem "recording_studio_trashable", github: "bowerbird-app/RecordingStudio_trashable", tag: "v0.12.0", require: false
gem "view_component", "4.19.0"

gem "devise"
gem "puma"
gem "sprockets-rails"

group :development, :test do
  gem "debug"
  gem "simplecov", require: false
end

group :development do
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
end
