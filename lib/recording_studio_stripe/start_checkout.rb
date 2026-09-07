# frozen_string_literal: true

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
      validate_price!

      if @price.recurring? && live_subscription
        ChangePlan.call(root_recording: @root_recording, price: @price, actor: @actor)
        return { url: @success_url, session_id: nil, changed: true }
      end

      return complete_locally if RecordingStudioStripe.configuration.local_mode?

      customer = EnsureCustomer.call(root_recording: @root_recording, email: actor_email)
      return start_recurring_checkout(customer) if @price.recurring?

      session = create_checkout_session(customer)
      { url: session.url, session_id: session.id }
    end

    private

    def validate_price!
      raise InvalidPrice, "Price is not for sale" unless @price.active? && @price.product&.active?

      if @price.recurring?
        raise InvalidPrice, "Pick a plan from the list." unless @price.product.plan?
      else
        raise InvalidPrice, "Pick an extra pack from billing." unless @price.product.allowance?
      end
    end

    def start_recurring_checkout(customer)
      type = subscription_type
      ApplicationRecord.transaction do
        AdvisoryLock.hold(ApplicationRecord.connection, "checkout:#{@root_recording.id}:#{type}")
        live = live_subscription
        if live
          ChangePlan.call(root_recording: @root_recording, price: @price, actor: @actor)
          return { url: @success_url, session_id: nil, changed: true }
        end

        confirming = pending_checkout.expire_open!(type)
        return { url: @success_url, session_id: confirming, confirming: true } if confirming

        session = create_checkout_session(customer)
        pending_checkout.persist!(customer, session, type)
        { url: session.url, session_id: session.id }
      end
    end

    def pending_checkout
      PendingCheckout.new(root_recording: @root_recording, price: @price)
    end

    def create_checkout_session(customer)
      Client.current.v1.checkout.sessions.create(
        session_params(customer),
        { idempotency_key: checkout_idempotency_key }
      )
    end

    def live_subscription
      Subscription.current_for(
        root_recording_id: @root_recording.id,
        subscription_type: subscription_type
      )
    end

    def subscription_type
      SubscriptionTypes.normalize(@price.product&.subscription_type)
    end

    def session_params(customer)
      params = {
        mode: checkout_mode,
        customer: customer.stripe_id,
        client_reference_id: @root_recording.id.to_s,
        success_url: @success_url,
        cancel_url: @cancel_url,
        line_items: [{ price: @price.stripe_id, quantity: 1 }],
        metadata: checkout_metadata,
        allow_promotion_codes: RecordingStudioStripe.configuration.allow_promotion_codes
      }
      if RecordingStudioStripe.configuration.automatic_tax
        params[:automatic_tax] = { enabled: true }
        params[:customer_update] = { address: "auto" }
      end
      if @price.recurring?
        params[:subscription_data] = {
          metadata: checkout_metadata.slice(:root_recording_id, :subscription_type)
        }
      end
      params
    end

    def checkout_metadata
      {
        root_recording_id: @root_recording.id.to_s,
        price_id: @price.stripe_id,
        subscription_type: subscription_type
      }
    end

    def checkout_idempotency_key
      "checkout-#{@root_recording.id}-#{@price.stripe_id}-#{SecureRandom.hex(4)}"
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
