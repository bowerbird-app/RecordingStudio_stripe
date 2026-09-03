# frozen_string_literal: true

module RecordingStudioStripe
  class StartPortalSession
    def self.call(root_recording:, return_url:)
      new(root_recording: root_recording, return_url: return_url).call
    end

    def initialize(root_recording:, return_url:)
      @root_recording = root_recording
      @return_url = return_url
    end

    def call
      return { url: @return_url, local: true, unavailable: true } if RecordingStudioStripe.configuration.local_mode?

      customer = Customer.find_by(root_recording_id: @root_recording.id)
      raise NoCustomer unless customer

      session = Client.current.v1.billing_portal.sessions.create(
        customer: customer.stripe_id,
        return_url: @return_url
      )
      { url: session.url }
    end
  end
end
