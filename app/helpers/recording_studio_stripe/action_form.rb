# frozen_string_literal: true

module RecordingStudioStripe
  module ActionForm
    def stripe_action_form(url, method: :post, hidden: {}, turbo: true, &block)
      options = { url: url, method: method, class: "inline-flex" }
      options[:data] = { turbo: false } unless turbo
      form_with(**options) do
        fields = hidden.map { |name, value| hidden_field_tag(name, value) }
        safe_join(fields + [capture(&block)])
      end
    end
  end
end
