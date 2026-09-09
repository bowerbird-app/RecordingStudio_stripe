# frozen_string_literal: true

module RecordingStudioStripe
  class PlanCardSettings
    def self.normalize(settings)
      data = settings.to_h.deep_stringify_keys
      {
        "hide" => Array(data["hide"]).map(&:to_s).reject(&:blank?),
        "order" => order_rows(data["order"]),
        "extras" => extra_rows(data["extras"]).filter_map { |extra| extra_row(extra) }
      }
    end

    def self.order_rows(value)
      rows = value.is_a?(Array) ? value : value.to_s.split(/\r?\n/)
      rows.map(&:to_s).map(&:strip).reject(&:blank?)
    end
    private_class_method :order_rows

    def self.extra_rows(raw)
      case raw
      when Hash then raw.values
      else Array(raw)
      end
    end
    private_class_method :extra_rows

    def self.extra_row(extra)
      row = extra.to_h.stringify_keys
      text = row["text"].to_s.strip
      return if text.blank?

      {
        "key" => row["key"].to_s.strip.presence || text.parameterize(separator: "_"),
        "text" => text,
        "icon" => row["icon"].to_s.strip.presence
      }.compact
    end
    private_class_method :extra_row
  end
end
