# frozen_string_literal: true

module RecordingStudioStripe
  class EnsureCustomer
    def self.call(root_recording:, email: nil)
      new(root_recording: root_recording, email: email).call
    end

    def initialize(root_recording:, email:)
      @root_recording = root_recording
      @email = email
    end

    def call
      existing = Customer.find_by(root_recording_id: @root_recording.id)
      return existing if existing

      stripe_id = create_stripe_customer_id
      Customer.create!(
        root_recording_id: @root_recording.id,
        stripe_id: stripe_id,
        email: @email
      )
    end

    private

    def create_stripe_customer_id
      return "cus_local_#{@root_recording.id.to_s.delete('-')}" if RecordingStudioStripe.configuration.local_mode?

      result = Client.current.v1.customers.create(
        {
          email: @email,
          metadata: { root_recording_id: @root_recording.id.to_s }
        }
      )
      result.id
    end
  end
end
