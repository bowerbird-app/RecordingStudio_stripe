# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in recording_studio_stripe.gemspec
gemspec

# These gems resolve from GitHub.
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.341"
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v6.5.0"
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.24.2"
gem "recording_studio_metrics", github: "bowerbird-app/RecordingStudio_metrics", tag: "v0.7.3", require: false
# Required by accessible (not on RubyGems)
gem "recording_studio_cache", github: "bowerbird-app/RecordingStudio_cache", tag: "v0.6.2", require: false
gem "recording_studio_logs", github: "bowerbird-app/RecordingStudio_logs", tag: "v0.7.4", require: false
gem "recording_studio_trashable", github: "bowerbird-app/RecordingStudio_trashable", tag: "v0.12.3", require: false
gem "view_component", "4.19.0"

gem "devise"
gem "puma"
gem "sprockets-rails"

group :development, :test do
  gem "debug"
  gem "minitest", "< 6"
  gem "recording_studio_api", github: "bowerbird-app/RecordingStudio_api", tag: "v0.21.3", require: false
  gem "recording_studio_icons", github: "bowerbird-app/RecordingStudio_icons", tag: "v0.2.1", require: false
  gem "recording_studio_moveable", github: "bowerbird-app/RecordingStudio_moveable", tag: "v4.1.1", require: false
  gem "simplecov", require: false
end

group :development do
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
end
