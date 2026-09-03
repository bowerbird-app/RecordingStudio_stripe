# frozen_string_literal: true

require "securerandom"

module RecordingStudioStripe
  class StartCheckout
    def self.call(root_recording:, price:, actor:, success_url:, cancel_url:)
      new(
        root_recording: root_recording,
        price: price,
        actor: actor,
        success_url: success_url,
        cancel_url: cancel_url
      ).call
    end

    def initialize(root_recording:, price:, actor:, success_url:, cancel_url:)
      @root_recording = root_recording
      @price = price
      @actor = actor
      @success_url = success_url
      @cancel_url = cancel_url
    end

    def call
      raise InvalidPrice, "Price is not for sale" unless @price.active?

      return complete_locally if RecordingStudioStripe.configuration.local_mode?

      customer = EnsureCustomer.call(root_recording: @root_recording, email: actor_email)
      session = Client.current.v1.checkout.sessions.create(session_params(customer))
      { url: session.url, session_id: session.id }
    end

    private

    def session_params(customer)
      params = {
        mode: checkout_mode,
        customer: customer.stripe_id,
        client_reference_id: @root_recording.id.to_s,
        success_url: @success_url,
        cancel_url: @cancel_url,
        line_items: [{ price: @price.stripe_id, quantity: 1 }],
        metadata: {
          root_recording_id: @root_recording.id.to_s,
          price_id: @price.stripe_id
        },
        integration_identifier: "recording-studio-#{SecureRandom.alphanumeric(8).downcase}"
      }
      if @price.recurring?
        params[:subscription_data] = {
          metadata: { root_recording_id: @root_recording.id.to_s }
        }
      end
      params
    end

    def checkout_mode
      @price.recurring? ? "subscription" : "payment"
    end

    def actor_email
      @actor.respond_to?(:email) ? @actor.email : nil
    end

    def complete_locally
      if @price.recurring?
        ApplySubscription.call(root_recording: @root_recording, price: @price, email: actor_email)
      else
        ApplyAllowance.call(root_recording: @root_recording, price: @price, email: actor_email)
      end
      { url: @success_url, session_id: nil, local: true }
    end
  end
end
