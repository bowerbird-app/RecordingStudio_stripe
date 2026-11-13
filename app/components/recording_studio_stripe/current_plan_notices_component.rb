# frozen_string_literal: true

module RecordingStudioStripe
  class CurrentPlanNoticesComponent < ViewComponent::Base
    include RecordingStudioStripe::ApplicationHelper

    def initialize(subscription:)
      super()
      @state = CurrentPlanState.new(subscription)
    end

    def render?
      @state.group_label? || @state.past_due? || @state.trial_ending? || @state.canceled? ||
        @state.show_period_end? || @state.scheduled_change? || usage_alert?
    end

    def call
      return pieces.first if pieces.one?

      render FlatPack::Collection::Component.new(as: :list, layout: :stack, gap: :md) do |stack|
        pieces.each { |piece| stack.with_item { piece } }
      end
    end

    private

    def pieces
      @pieces ||= [
        group_label,
        alert(:past_due, @state.past_due?),
        alert(:trial_ending, @state.trial_ending?),
        alert(:canceled, @state.canceled?),
        period_end_notice,
        scheduled_notice,
        *usage_notices
      ].compact
    end

    def group_label
      return unless @state.group_label?

      render FlatPack::Text::Component.new(text: @state.group_label, size: :xs, style: :muted)
    end

    def alert(status, show)
      return unless show

      render FlatPack::Billing::StatusAlert::Component.new(status: status)
    end

    def period_end_notice
      return unless @state.show_period_end?

      render FlatPack::Billing::StatusAlert::Component.new(
        style: :warning,
        title: Copy.t("billing.ends_this_period"),
        description: @state.period_end_description
      )
    end

    def scheduled_notice
      return unless @state.scheduled_change?

      render FlatPack::Billing::StatusAlert::Component.new(
        style: :info,
        title: Copy.t("billing.change_scheduled"),
        description: Copy.t("billing.scheduled", name: @state.scheduled_name)
      )
    end

    def usage_notices
      usage_handles.filter_map do |handle|
        notice = LimitStatusComponent.new(handle: handle)
        render(notice) if notice.render?
      end
    end

    def usage_alert?
      usage_handles.any? { |handle| LimitStatusComponent.new(handle: handle).render? }
    end

    def usage_handles
      return @usage_handles if defined?(@usage_handles)

      recording = RecordingStudio::Recording.find_by(id: @state.root_recording_id)
      return @usage_handles = [] unless recording

      line = RecordingStudioStripe::Billing.for_recording(recording).line(@state.subscription_type)
      @usage_handles = billing_line_limits(line) + billing_line_meters(line)
    end
  end
end
