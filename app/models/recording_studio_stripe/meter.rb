# frozen_string_literal: true

module RecordingStudioStripe
  class Meter < ApplicationRecord
    self.table_name = "recording_studio_stripe_meters"

    has_many :usage_entries, class_name: "RecordingStudioStripe::UsageEntry", dependent: :delete_all
    has_many :allowance_purchases, class_name: "RecordingStudioStripe::AllowancePurchase", dependent: :delete_all

    validates :name, presence: true, uniqueness: true
    validates :label, presence: true

    def self.named(name)
      key = name.to_s
      find_by(name: key) || ensure_named!(key)
    end

    def self.sync_from_config!
      RecordingStudioStripe.configuration.meters.each_key { |name| ensure_named!(name) }
      all
    end

    def self.ensure_named!(name)
      attrs = RecordingStudioStripe.configuration.meters.stringify_keys[name.to_s] || {}
      record = find_or_initialize_by(name: name.to_s)
      record.label = attrs["label"].presence || name.to_s.tr("_", " ").capitalize
      record.save!
      record
    end
  end
end
