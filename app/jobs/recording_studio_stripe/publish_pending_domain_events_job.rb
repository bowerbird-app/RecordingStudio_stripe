# frozen_string_literal: true

module RecordingStudioStripe
  class PublishPendingDomainEventsJob < ActiveJob::Base
    queue_as :default

    def perform(older_than_seconds = 300)
      DomainEvents.publish_pending!(older_than: Integer(older_than_seconds))
    end
  end
end
