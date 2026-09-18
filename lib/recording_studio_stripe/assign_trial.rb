# frozen_string_literal: true

module RecordingStudioStripe
  class AssignTrial
    def self.call(product:, days:, unit_amount: 0)
      new(product: product, days: days, unit_amount: unit_amount).call
    end

    def initialize(product:, days:, unit_amount:)
      @product = product
      @days = days
      @unit_amount = unit_amount
    end

    def call
      raise InvalidPrice, "Trials belong on a plan" unless @product.plan?

      if days.positive?
        write_offer
        rotate_fee_price
      else
        clear_offer
        deactivate_fee_prices
      end
      @product.save!
      @product
    end

    private

    def days
      parse_int(@days)
    end

    def unit_amount
      parse_int(@unit_amount)
    end

    def write_offer
      data = stringify(@product.metadata)
      data["trial_days"] = days.to_s
      data["trial_unit_amount"] = unit_amount.to_s
      @product.metadata = data
    end

    def clear_offer
      data = stringify(@product.metadata)
      data.delete("trial_days")
      data.delete("trial_unit_amount")
      @product.metadata = data
    end

    def rotate_fee_price
      if unit_amount.positive?
        keep = matching_fee_price
        deactivate_fee_prices(except: keep)
        create_fee_price unless keep
      else
        deactivate_fee_prices
      end
    end

    def matching_fee_price
      trial.fee_prices.find { |price| price.active? && price.unit_amount == unit_amount }
    end

    def create_fee_price
      CreatePrice.call(
        product: @product,
        unit_amount: unit_amount,
        currency: fee_currency,
        metadata: { "kind" => Trial::FEE_KIND }
      )
    end

    def deactivate_fee_prices(except: nil)
      trial.fee_prices.each do |price|
        next if except && price.id == except.id
        next unless price.active?

        price.update!(active: false)
        next if RecordingStudioStripe.configuration.local_mode?

        Client.current.v1.prices.update(price.stripe_id, { active: false })
      end
    end

    def fee_currency
      @product.monthly_price&.currency.presence || @product.prices.active.first&.currency.presence || "usd"
    end

    def trial
      Trial.for(@product)
    end

    def stringify(metadata)
      (metadata || {}).to_h.stringify_keys
    end

    def parse_int(value)
      return 0 if value.blank?

      Integer(value)
    rescue ArgumentError, TypeError
      raise InvalidPrice, "Trial days and amount must be whole numbers."
    end
  end
end
