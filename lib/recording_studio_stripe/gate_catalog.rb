# frozen_string_literal: true

module RecordingStudioStripe
  class GateCatalog
    Row = Struct.new(:kind, :name, :label, :aggregation, :plan_names, :in_config, :missing_usage,
                     keyword_init: true) do
      def plans
        names = Array(plan_names).uniq.sort
        names.empty? ? "No plan" : names.join(", ")
      end

      def aggregation_label
        aggregation.presence || "—"
      end

      def note
        return "Not in config" unless in_config
        return "No usage reader" if missing_usage

        nil
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
      names = union_names(declared, records)
      used = Hash.new { |hash, key| hash[key] = [] }
      products.each do |product|
        product.paywalls.each { |paywall| used[paywall.name] << product.name }
      end
      named_rows(kind: "Paywall", names: names, declared: declared, records: records, used: used)
    end

    def limit_rows(products)
      Limits.all.sort_by(&:name).map do |definition|
        Row.new(
          kind: "Limit",
          name: definition.name,
          label: definition.label,
          aggregation: definition.aggregation,
          plan_names: products.select { |product| product.limit_quantity(definition.name).positive? }.map(&:name),
          in_config: true,
          missing_usage: quantity_without_reader?(definition)
        )
      end
    end

    def meter_rows(products)
      records = Meter.order(:name).index_by(&:name)
      declared = config_hash(:meters)
      names = union_names(declared, records)
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
          in_config: declared.key?(name),
          missing_usage: false
        )
      end
    end

    def union_names(declared, records)
      (declared.keys + records.keys).uniq.sort
    end

    def quantity_without_reader?(definition)
      return false unless definition.quantity?

      RecordingStudioStripe.configuration.limit_usage_for(definition.name).nil?
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
