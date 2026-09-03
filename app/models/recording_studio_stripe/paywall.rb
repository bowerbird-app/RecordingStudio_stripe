# frozen_string_literal: true

module RecordingStudioStripe
  class Paywall < ApplicationRecord
    self.table_name = "recording_studio_stripe_paywalls"

    has_many :product_paywalls, class_name: "RecordingStudioStripe::ProductPaywall", dependent: :delete_all
    has_many :products, through: :product_paywalls, class_name: "RecordingStudioStripe::Product"

    validates :name, presence: true, uniqueness: true
    validates :label, presence: true

    def self.named(name)
      key = name.to_s
      find_by(name: key) || ensure_named!(key)
    end

    def self.sync_from_config!
      RecordingStudioStripe.configuration.paywalls.each_key { |name| ensure_named!(name) }
      all
    end

    def self.ensure_named!(name)
      attrs = RecordingStudioStripe.configuration.paywalls.stringify_keys[name.to_s] || {}
      record = find_or_initialize_by(name: name.to_s)
      record.label = attrs["label"].presence || name.to_s.tr("_", " ").capitalize
      record.save!
      record
    end

    def action_name
      name.to_sym
    end
  end
end
