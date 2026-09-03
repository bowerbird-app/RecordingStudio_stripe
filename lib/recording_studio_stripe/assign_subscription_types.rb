# frozen_string_literal: true

module RecordingStudioStripe
  class AssignSubscriptionTypes
    def self.call
      new.call
    end

    def call
      return unless Product.table_exists?
      return unless Product.column_names.include?("subscription_type")

      default_type = SubscriptionTypes.keys.first
      Product.where(subscription_type: [nil, ""]).update_all(subscription_type: default_type)
      remap_implied_when_one_type(default_type)
      copy_type_from_products
    end

    private

    def remap_implied_when_one_type(default_type)
      return unless SubscriptionTypes.keys == [default_type]
      return if default_type == SubscriptionTypes::IMPLIED_KEY

      Product.where(subscription_type: SubscriptionTypes::IMPLIED_KEY).update_all(subscription_type: default_type)
      Subscription.where(subscription_type: SubscriptionTypes::IMPLIED_KEY).update_all(subscription_type: default_type)
    end

    def copy_type_from_products
      Subscription.joins(:price).find_each do |subscription|
        type = subscription.price.product&.subscription_type
        next if type.blank? || subscription.subscription_type == type

        subscription.update_column(:subscription_type, type)
      end
    end
  end
end
