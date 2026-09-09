# frozen_string_literal: true

module RecordingStudioStripe
  class PlanCardOptions
    def self.hide_list(subscription_type:)
      type = subscription_type.to_s
      limit_options(type) + meter_options + paywall_options
    end

    def self.limit_options(type)
      Limits.for_subscription_type(type).map { |definition| ["limit:#{definition.name}", definition.label] }
    end
    private_class_method :limit_options

    def self.meter_options
      named_options(:meters, meter_rows, "meter")
    end
    private_class_method :meter_options

    def self.paywall_options
      named_options(:paywalls, paywall_rows, "paywall")
    end
    private_class_method :paywall_options

    def self.named_options(kind, rows, prefix)
      named = {}
      RecordingStudioStripe.configuration.public_send(kind).to_h.stringify_keys.each do |name, attrs|
        named[name] = attrs.to_h.stringify_keys["label"].presence || name.tr("_", " ")
      end
      rows.each { |name, label| named[name] ||= label }
      named.map { |name, label| ["#{prefix}:#{name}", label] }
    end
    private_class_method :named_options

    def self.meter_rows
      named_rows(:Meter)
    end
    private_class_method :meter_rows

    def self.paywall_rows
      named_rows(:Paywall)
    end
    private_class_method :paywall_rows

    def self.named_rows(const_name)
      return [] unless RecordingStudioStripe.const_defined?(const_name)

      klass = RecordingStudioStripe.const_get(const_name)
      return [] unless klass.respond_to?(:order)

      klass.order(:name).map { |row| [row.name, row.label] }
    rescue NameError
      []
    end
    private_class_method :named_rows
  end
end
