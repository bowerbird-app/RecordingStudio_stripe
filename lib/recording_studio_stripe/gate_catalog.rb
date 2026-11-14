# frozen_string_literal: true

module RecordingStudioStripe
  class GateCatalog
    Row = Struct.new(:kind, :name, :label, :aggregation, :plan_names, :missing_usage,
                     :ceiling_note, keyword_init: true) do
      def plans
        names = Array(plan_names).uniq.sort
        text = names.empty? ? "No plan" : names.join(", ")
        note = ceiling_note.to_s.strip
        return text if note.empty?

        "#{text} · #{note}"
      end

      def aggregation_label
        return if aggregation.nil?

        label = aggregation == "per_item" ? "per item" : aggregation
        return label unless missing_usage

        "#{label} · No usage reader"
      end
    end

    def self.rows
      new.rows
    end

    def rows
      products = Product.includes(:paywalls, :prices).order(:name).to_a
      paywall_rows(products) + limit_rows(products) + meter_rows(products)
    end

    private

    def paywall_rows(products)
      records = Paywall.order(:name).index_by(&:name)
      declared = config_hash(:paywalls)
      used = Hash.new { |hash, key| hash[key] = [] }
      products.each do |product|
        product.paywalls.each { |paywall| used[paywall.name] << product.name }
      end
      named_rows(kind: "Paywall", names: declared.keys.sort, declared: declared, records: records, used: used)
    end

    def limit_rows(products)
      Limits.all.sort_by(&:name).map do |definition|
        Row.new(
          kind: "Limit",
          name: definition.name,
          label: definition.label,
          aggregation: definition.aggregation,
          plan_names: products.select { |product| product.limit_quantity(definition.name).positive? }.map(&:name),
          missing_usage: quantity_without_reader?(definition),
          ceiling_note: ceiling_note(definition)
        )
      end
    end

    def meter_rows(products)
      records = Meter.order(:name).index_by(&:name)
      declared = config_hash(:meters)
      names = declared.keys.sort
      named_rows(kind: "Meter", names: names, declared: declared, records: records, used: meter_usage(products, names))
    end

    def meter_usage(products, names)
      used = Hash.new { |hash, key| hash[key] = [] }
      products.each do |product|
        names.each do |name|
          next unless product.prices.any? { |price| meter_on_price?(price, name) }

          used[name] << product.name
        end
      end
      used
    end

    def named_rows(kind:, names:, declared:, records:, used:)
      names.map do |name|
        attrs = declared[name] || {}
        Row.new(
          kind: kind,
          name: name,
          label: attrs["label"].presence || records[name]&.label || humanize(name),
          aggregation: nil,
          plan_names: used[name],
          missing_usage: false
        )
      end
    end

    def quantity_without_reader?(definition)
      return false unless definition.quantity?

      RecordingStudioStripe.configuration.limit_usage_for(definition.name).nil?
    end

    def ceiling_note(definition)
      return if definition.no_plan_limit.nil?

      "#{definition.display_quantity(definition.no_plan_limit)} with no plan"
    end

    def meter_on_price?(price, name)
      price.included_quantity(name).positive? ||
        (price.allowance_meter_name == name && price.allowance_quantity.positive?)
    end

    def config_hash(setting)
      RecordingStudioStripe.configuration.public_send(setting).to_h.stringify_keys.transform_values do |value|
        value.to_h.stringify_keys
      end
    end

    def humanize(name)
      name.to_s.tr("_", " ").capitalize
    end
  end
end
