# frozen_string_literal: true

require "fileutils"

# Links installed gems to stable directories so Tailwind @source can scan them.
# @source does not expand globs, so the link target is the real gem path.
module TailwindGemSources
  GEMS = %w[
    flat_pack
    recording_studio
    recording_studio_admin
    recording_studio_accessible
    recording_studio_root_switchable
    recording_studio_logs
  ].freeze

  def self.link!(directory, specs: Gem.loaded_specs)
    FileUtils.mkdir_p(directory)

    GEMS.each do |gem_name|
      spec = specs[gem_name]
      next unless spec

      destination = File.join(directory, gem_name)
      FileUtils.rm_rf(destination) if File.symlink?(destination)
      File.symlink(spec.full_gem_path, destination)
    end
  end
end
