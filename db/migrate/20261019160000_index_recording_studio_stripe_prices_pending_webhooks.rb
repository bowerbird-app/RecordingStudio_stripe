# frozen_string_literal: true

class IndexRecordingStudioStripePricesPendingWebhooks < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :recording_studio_stripe_webhook_events,
              %i[created_at id],
              where: "event_type = 'invoice.paid' AND (payload #>> '{invoice,prices_pending}') = 'true'",
              algorithm: :concurrently,
              name: "idx_rs_stripe_webhook_events_prices_pending"
  end
end
