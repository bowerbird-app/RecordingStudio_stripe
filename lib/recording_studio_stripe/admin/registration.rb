# frozen_string_literal: true

module RecordingStudioStripe
  module Admin
    class Registration
      def self.register!
        return unless defined?(::RecordingStudioAdmin::Section)

        Definitions.ensure!
        RecordingStudioAdmin.register_section(Definitions::StripeSection)
        RecordingStudioAdmin.register_screen(Definitions::ProductsScreen)
        RecordingStudioAdmin.register_screen(Definitions::PricesScreen)
        RecordingStudioAdmin.register_screen(Definitions::MetersScreen)
        RecordingStudioAdmin.register_screen(Definitions::PaywallsScreen)
        RecordingStudioAdmin.register_screen(Definitions::CustomersScreen)
        RecordingStudioAdmin.register_screen(Definitions::SubscriptionsScreen)
        RecordingStudioAdmin.register_widget(Definitions::PastDueWidget)
        RecordingStudioAdmin.register_widget(Definitions::ActiveSubscriptionsWidget)
      end
    end
  end
end
