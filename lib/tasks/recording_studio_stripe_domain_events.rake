# frozen_string_literal: true

namespace :recording_studio_stripe do
  desc "Publish domain events left unpublished after a subscriber error"
  task publish_pending_domain_events: :environment do
    older_than = Integer(ENV.fetch("OLDER_THAN_SECONDS", "300"))
    RecordingStudioStripe::DomainEvents.publish_pending!(older_than: older_than)
  end
end
