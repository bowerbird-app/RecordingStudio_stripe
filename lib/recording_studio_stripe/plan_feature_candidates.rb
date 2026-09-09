# frozen_string_literal: true

module RecordingStudioStripe
  class PlanFeatureCandidates
    def initialize(product, price, settings)
      @product = product
      @price = price
      @settings = settings
    end

    def lines
      limit_lines + meter_lines + paywall_lines + extra_lines
    end

    private

    def limit_lines
      Limits.for_subscription_type(@product.subscription_type).filter_map do |definition|
        quantity = @product.limit_quantity(definition.name)
        next unless quantity.positive?

        PlanFeatures::Line.new(
          key: "limit:#{definition.name}",
          text: limit_text(definition, quantity),
          icon: definition.icon.presence || PlanFeatures::DEFAULT_ICON
        )
      end
    end

    def meter_lines
      meter_names.filter_map do |name|
        quantity = @price.included_quantity(name)
        next unless quantity.positive?

        attrs = config_attrs(:meters, name)
        PlanFeatures::Line.new(
          key: "meter:#{name}",
          text: meter_text(name, quantity, attrs),
          icon: attrs["icon"].presence || PlanFeatures::DEFAULT_ICON
        )
      end
    end

    def paywall_lines
      Array(paywalls).map do |paywall|
        attrs = config_attrs(:paywalls, paywall.name)
        PlanFeatures::Line.new(
          key: "paywall:#{paywall.name}",
          text: attrs["plan_line"].presence || paywall.label,
          icon: attrs["icon"].presence || PlanFeatures::DEFAULT_ICON
        )
      end
    end

    def extra_lines
      extras.filter_map do |extra|
        text = extra["text"].to_s.strip
        next if text.blank?

        key = extra["key"].to_s.strip.presence || text.parameterize(separator: "_")
        PlanFeatures::Line.new(
          key: "extra:#{key}",
          text: text,
          icon: extra["icon"].presence || PlanFeatures::DEFAULT_ICON
        )
      end
    end

    def limit_text(definition, quantity)
      qty = PlanFeatures.quantity_label(quantity)
      if definition.plan_line.present?
        interpolate(definition.plan_line, quantity: qty, label: definition.label)
      else
        "#{qty} #{definition.label.downcase}"
      end
    end

    def meter_text(name, quantity, attrs)
      qty = PlanFeatures.quantity_label(quantity)
      label = attrs["label"].presence || name.to_s.tr("_", " ")
      if attrs["plan_line"].present?
        interpolate(attrs["plan_line"], quantity: qty, label: label)
      else
        "#{qty} #{label.downcase}"
      end
    end

    def interpolate(template, quantity:, label:)
      format(template.to_s, quantity: quantity, label: label)
    rescue KeyError, ArgumentError
      template.to_s
    end

    def meter_names
      configured = RecordingStudioStripe.configuration.meters.to_h.stringify_keys.keys
      extra = included_meter_names - configured
      configured + extra
    end

    def included_meter_names
      price_metadata.keys.grep(/\Aincluded_/).map { |key| key.delete_prefix("included_") }
    end

    def price_metadata
      return {} unless @price.respond_to?(:metadata)

      @price.metadata.to_h.stringify_keys
    end

    def paywalls
      collection = @product.paywalls
      return [] if collection.blank?
      return collection.order(:name) if collection.respond_to?(:order)

      Array(collection)
    end

    def extras
      Array(@settings["extras"]).map { |extra| extra.to_h.stringify_keys }
    end

    def config_attrs(kind, name)
      RecordingStudioStripe.configuration.public_send(kind).to_h.stringify_keys[name.to_s].to_h.stringify_keys
    end
  end
end
