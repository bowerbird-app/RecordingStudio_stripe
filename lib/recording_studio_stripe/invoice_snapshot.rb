# frozen_string_literal: true

module RecordingStudioStripe
  # Minimal invoice fields kept on the webhook row so a replay can rebuild
  # invoice_paid without calling Stripe. Stripe's webhook includes the first
  # page of lines (10). When `lines_has_more` is true, a later page is not here.
  class InvoiceSnapshot
    include StripeRequest

    def self.from(invoice)
      new(invoice).to_h
    end

    def self.ensure_prices_known!(snapshot)
      ids = Array(snapshot.to_h["lines"]).filter_map { |line| line.to_h["price_id"].presence }.uniq
      return if ids.empty?

      known = Price.where(stripe_id: ids).pluck(:stripe_id)
      return if (ids - known).empty?

      raise DeferredWebhook, "Price is not in the catalogue yet"
    end

    def initialize(invoice)
      @invoice = invoice
    end

    def to_h
      parsed = lines
      {
        "amount_paid" => amount_paid,
        "currency" => currency,
        "invoice_id" => stripe_get(@invoice, :id).to_s,
        "customer" => id_from(stripe_get(@invoice, :customer)),
        "subscription" => subscription_id,
        "billing_reason" => stripe_get(@invoice, :billing_reason).to_s,
        "lines" => parsed,
        "lines_has_more" => lines_has_more?,
        "trial_fee" => trial_fee?(parsed)
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
      @lines ||= stripe_list_items(stripe_get(@invoice, :lines)).map { |line| line_snapshot(line) }
    end

    def lines_has_more?
      stripe_get(stripe_get(@invoice, :lines), :has_more) == true
    end

    def line_snapshot(line)
      { "price_id" => line_price_id(line).to_s, "amount" => line_amount(line) }
    end

    def line_amount(line)
      value = stripe_get(line, :amount)
      value.nil? ? 0 : value.to_i
    end

    def line_price_id(line)
      priced = stripe_get(stripe_get(stripe_get(line, :pricing), :price_details), :price)
      return id_from(priced) if priced.present?

      item_price_id(line).to_s
    end

    def id_from(value)
      return if value.blank?
      return value.to_s if value.is_a?(String)

      stripe_get(value, :id).presence&.to_s || value.to_s
    end

    def trial_fee?(parsed)
      TrialFeeInvoice.trial_fee?(lines: parsed, fee_price_ids: fee_price_ids(parsed))
    end

    def fee_price_ids(parsed)
      ids = parsed.filter_map { |line| line["price_id"].presence }
      return [] if ids.empty?

      Price.where(stripe_id: ids).filter_map { |price| price.stripe_id if Trial.fee_kind?(price) }
    end
  end
end
