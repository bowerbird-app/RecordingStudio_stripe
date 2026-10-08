# frozen_string_literal: true

module RecordingStudioStripe
  module Copy
    PREFIX = "recording_studio.stripe"
    UNSET = Object.new.freeze

    module_function

    def t(key, **)
      I18n.t("#{PREFIX}.#{key}", **)
    end

    def l(object, **)
      I18n.l(object, **)
    end

    def provided?(value)
      !value.equal?(UNSET)
    end

    def value(override, key, **)
      provided?(override) ? override : t(key, **)
    end

    def long_date(value)
      return unless value

      l(value.to_date, format: :long)
    end
  end
end
