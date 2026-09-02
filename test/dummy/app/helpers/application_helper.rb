module ApplicationHelper
  def dummy_page_nav(title:, back_url: nil, back_label: "Home")
    recording_studio_page_nav(
      title: title,
      page_nav_back_url: back_url,
      page_nav_back_label: back_label
    )

    recording_studio_page_nav_right do
      concat recording_studio_root_switch_dropdown(style: :ghost, size: :md)
      concat render(
        FlatPack::Button::Component.new(
          text: "Sign out",
          style: :ghost,
          size: :md,
          href: main_app.destroy_user_session_path,
          data: { turbo_method: :delete }
        )
      )
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
end
