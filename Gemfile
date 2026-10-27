# frozen_string_literal: true

source "https://rubygems.org"

require_relative "test/support/widen_recording_studio_requirement"

# Specify your gem's dependencies in recording_studio_stripe.gemspec
gemspec

# recording_studio is not published to RubyGems; resolve the gemspec pin from GitHub.
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v6.1.0"
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.22.0"
# Required by accessible >= 0.22.0 (not on RubyGems)
gem "recording_studio_trashable", github: "bowerbird-app/RecordingStudio_trashable", tag: "v0.12.0", require: false
# FlatPack main is 0.1.319. The newest tag is v0.1.315.
gem "flat_pack", github: "bowerbird-app/flatpack", ref: "1fcbafe94f8eb118f0a22182f63f5110fcc97a56"
gem "recording_studio_metrics", github: "bowerbird-app/RecordingStudio_metrics", tag: "v0.6.1", require: false
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
