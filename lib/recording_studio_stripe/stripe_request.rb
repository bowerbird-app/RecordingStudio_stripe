# frozen_string_literal: true

module RecordingStudioStripe
  module StripeRequest
    def stripe_get(object, key)
      return if object.nil?
      return object[key] || object[key.to_s] || object[key.to_sym] if object.is_a?(Hash)

      object.public_send(key)
    rescue NoMethodError
      object[key] || object[key.to_s] if object.respond_to?(:[])
    end

    def stripe_list_items(list)
      return [] if list.nil?
      return list if list.is_a?(Array)

      data = list.respond_to?(:data) ? list.data : stripe_get(list, :data)
      return Array(data) if data

      list.respond_to?(:to_a) ? list.to_a : Array(list)
    end

    def stripe_list_first(list)
      stripe_list_items(list).first
    end

    def stringify_metadata(metadata)
      return {} if metadata.blank?

      metadata.to_h.stringify_keys
    end

    def item_price_id(item)
      price = stripe_get(item, :price)
      return if price.blank?
      return price.to_s if price.is_a?(String)

      (stripe_get(price, :id) || price).to_s
    end
  end
end
