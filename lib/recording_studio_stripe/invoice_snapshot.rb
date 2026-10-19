# frozen_string_literal: true

module RecordingStudioStripe
  # Minimal invoice fields kept on the webhook row so a replay can rebuild
  # invoice_paid without calling Stripe.
  class InvoiceSnapshot
    include StripeRequest

    def self.from(invoice)
      new(invoice).to_h
    end

    def initialize(invoice)
      @invoice = invoice
    end

    def to_h
      {
        "amount_paid" => amount_paid,
        "currency" => currency,
        "invoice_id" => stripe_get(@invoice, :id).to_s,
        "customer" => id_from(stripe_get(@invoice, :customer)),
        "subscription" => subscription_id,
        "lines" => lines,
        "trial_fee" => trial_fee?
      }
    end

    def subscription_id
      parent = stripe_get(@invoice, :parent)
      details = stripe_get(parent, :subscription_details)
      id_from(stripe_get(details, :subscription) || stripe_get(@invoice, :subscription))
    end

    private

    def amount_paid
      stripe_get(@invoice, :amount_paid)&.to_i
    end

    def currency
      stripe_get(@invoice, :currency).to_s.downcase.presence
    end

    def lines
      stripe_list_items(stripe_get(@invoice, :lines)).filter_map { |line| line_snapshot(line) }
    end

    def line_snapshot(line)
      price_id = line_price_id(line)
      return if price_id.blank?

      { "price_id" => price_id, "amount" => line_amount(line) }
    end

    def line_amount(line)
      value = stripe_get(line, :amount)
      value.nil? ? 0 : value.to_i
    end

    def line_price_id(line)
      priced = stripe_get(stripe_get(stripe_get(line, :pricing), :price_details), :price)
      return id_from(priced) if priced.present?

      item_price_id(line)
    end

    def id_from(value)
      return if value.blank?
      return value.to_s if value.is_a?(String)

      stripe_get(value, :id).presence&.to_s || value.to_s
    end

    def trial_fee?
      TrialFeeInvoice.trial_fee?(lines: line_entries, fee_price_ids: fee_price_ids)
    end

    def line_entries
      lines.map { |line| { price_id: line["price_id"], amount: line["amount"] } }
    end

    def fee_price_ids
      ids = lines.map { |line| line["price_id"] }
      return [] if ids.empty?

      Price.where(stripe_id: ids).filter_map { |price| price.stripe_id if fee_price?(price) }
    end

    def fee_price?(price)
      price.metadata.to_h.stringify_keys["kind"] == Trial::FEE_KIND
    end
  end
end
