# frozen_string_literal: true

module RecordingStudioStripe
  class Error < StandardError; end
  class MissingStripeKey < Error; end
  class Forbidden < Error; end
  class InvalidPrice < Error; end
  class NoSubscription < Error; end
end
