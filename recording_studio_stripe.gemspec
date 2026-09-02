# frozen_string_literal: true

require_relative "lib/recording_studio_stripe/version"

Gem::Specification.new do |spec|
  spec.name        = "recording_studio_stripe"
  spec.version     = RecordingStudioStripe::VERSION
  spec.authors     = ["Bowerbird"]
  spec.homepage    = "https://github.com/bowerbird-app/RecordingStudio_stripe"
  spec.summary     = "Stripe billing for Recording Studio roots"
  spec.description = "Stripe Products, Prices, Checkout, subscriptions, and local usage remaining " \
                     "for Recording Studio workspaces."
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/bowerbird-app/RecordingStudio_stripe"
  spec.metadata["changelog_uri"] = "https://github.com/bowerbird-app/RecordingStudio_stripe/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"].reject do |path|
      path == ".cursor" || path.start_with?(".cursor/")
    end
  end

  spec.add_dependency "rails", "~> 8.1.0"
  spec.add_dependency "recording_studio", "~> 4.1"
  spec.add_dependency "stripe", ">= 13.0", "< 20"
end
