# frozen_string_literal: true

require Rails.root.join("lib/tailwind_gem_sources")

namespace :tailwindcss do
  desc "Link installed FlatPack and Recording Studio gems for Tailwind @source"
  task link_gem_sources: :environment do
    TailwindGemSources.link!(Rails.root.join("app/assets/tailwind/gem_sources").to_s)
  end
end

%w[build watch].each do |name|
  Rake::Task["tailwindcss:#{name}"].enhance(["tailwindcss:link_gem_sources"])
end
