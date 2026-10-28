# frozen_string_literal: true

# Logs, Metrics, Cache, Internationalization, and Root Switchable still require
# recording_studio below 6. Widen that requirement when Bundler loads gemspecs
# so this app can resolve 6.2.0. The widened floor stays >= 6.1.0, which 6.2.0
# satisfies.
module WidenRecordingStudioRequirement
  def add_dependency(name, *requirements)
    if name.to_s == "recording_studio" && requirements.none? { |requirement| requirement.to_s.include?("6") }
      requirements = [">= 6.1.0"]
    end

    super
  end
end

unless Gem::Specification.ancestors.include?(WidenRecordingStudioRequirement)
  Gem::Specification.prepend(WidenRecordingStudioRequirement)
end
