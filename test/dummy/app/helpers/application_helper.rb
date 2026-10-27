module ApplicationHelper
  def dummy_sidebar_title
    current_root_recording&.recordable&.try(:name).presence || "This workspace"
  end

  def dummy_billing_path
    RecordingStudioStripe.configuration.mount_path
  end

  def dummy_usage_path
    recording_studio_stripe.usage_path
  end

  def dummy_usage_current?
    path = dummy_usage_path
    request.path == path || request.path.start_with?("#{path}/")
  end

  def dummy_billing_current?
    return false if dummy_usage_current?

    request.path.start_with?(dummy_billing_path)
  end

  def dummy_page_nav(title:, subtitle: nil, back_url: nil, back_label: "Home")
    content_for(:title, title)
    content_for(:subtitle, subtitle) if subtitle.present?

    flat_pack_page_nav(
      round: true,
      style: :default,
      back_href: back_url,
      back_tooltip: back_label,
      anchor_href: root_path,
      anchor_tooltip: t("recording_studio.stripe.nav.close")
    )

    content_for :page_nav_right do
      safe_join([
        recording_studio_root_switch_dropdown(style: :ghost, size: :md),
        render(
          FlatPack::Button::Component.new(
            text: "Sign out",
            style: :ghost,
            size: :md,
            href: main_app.destroy_user_session_path,
            data: { turbo_method: :delete }
          )
        )
      ].compact)
    end
  end

  def dummy_admin_button
    admin_recording = studio_admin_recording
    return unless admin_recording

    if current_root_recording&.id == admin_recording.id
      render FlatPack::Button::Component.new(text: "Admin", style: :ghost, size: :md, href: "/admin")
    else
      button_to "/recording_studio_root_switchable/v1/root_switch",
                method: :patch,
                params: {
                  scope: "all_workspaces",
                  root_switch: {
                    root_recording_id: admin_recording.id,
                    return_to: "/admin"
                  }
                },
                class: "inline-flex" do
        render FlatPack::Button::Component.new(text: "Admin", style: :ghost, size: :md, type: "submit")
      end
    end
  end

  def studio_admin_recording
    admin_root = AdminRoot.find_by(name: "Studio Admin")
    RecordingStudio.root_recording_for(admin_root) if admin_root
  end

  def dummy_show_press_kits?
    RecordingStudioStripe::Limits.known?(:press_kits) && current_root_recording&.recordable.is_a?(Workspace)
  end

  def dummy_press_kit_recordings
    return RecordingStudio::Recording.none unless current_root_recording

    RecordingStudio::Recording.for_root(current_root_recording.id).of_type("PressKit").where(trashed_at: nil).order(:created_at)
  end

  def dummy_press_kits_subtitle
    return "Pick a plan to add press kits." unless current_root_recording&.recordable.respond_to?(:billing)

    handle = current_root_recording.recordable.billing.limit(:press_kits)
    if handle.included <= 0
      "Pick a plan to add press kits."
    else
      "#{handle.used} of #{handle.included} on this plan."
    end
  end

  def dummy_home_plan_names
    recordable = current_root_recording&.recordable
    return [] unless recordable.respond_to?(:billing)

    recordable.billing.active_lines.filter_map { |line| line.subscription.price&.product&.name }
  end

  def dummy_locale_attributes
    return {} unless respond_to?(:recording_studio_locale_attributes)

    recording_studio_locale_attributes
  end

  def dummy_home_subtitle
    names = dummy_home_plan_names
    return "Pricing, billing, and usage live on their own pages." if names.empty?

    "You're on #{names.to_sentence}."
  end
end
