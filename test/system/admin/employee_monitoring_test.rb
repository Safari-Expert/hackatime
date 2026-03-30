require "application_system_test_case"

class Admin::EmployeeMonitoringTest < ApplicationSystemTestCase
  test "viewer access stays read only" do
    viewer = User.create!(timezone: "UTC", admin_level: "viewer", github_username: "viewer-monitoring")
    monitored = create_monitored_user("readonly-dev")

    sign_in_as(viewer)
    visit admin_employee_monitoring_path(user_id: monitored.id)

    assert_text "Employee Monitoring"
    assert_text monitored.display_name
    assert_text "This view is read-only for viewers."
    assert_no_button "Save schedule"
  end

  test "admins can access the schedule editor" do
    admin = User.create!(timezone: "UTC", admin_level: "admin", github_username: "admin-monitoring")
    monitored = create_monitored_user("editable-dev")

    sign_in_as(admin)
    visit admin_employee_monitoring_path(user_id: monitored.id)

    assert_text monitored.display_name
    assert_text "EDIT SCHEDULE"
    assert_field "Timezone override", with: ""
    assert_field "Expected start", with: "09:00"
    assert_field "Expected finish", with: "17:00"
    assert_button "Save schedule"
  end

  private

  def create_monitored_user(github_username)
    user = User.create!(timezone: "UTC", github_username: github_username)
    user.create_employee_monitoring_profile!

    Heartbeat.create!(
      user: user,
      time: 4.minutes.ago.to_i,
      category: "coding",
      project: "internal_ui",
      language: "Ruby",
      editor: "VS Code",
      entity: "/app/internal_ui/app/page.tsx",
      is_write: true,
      line_additions: 12,
      source_type: :test_entry
    )
    Heartbeat.create!(
      user: user,
      time: 2.minutes.ago.to_i,
      category: "coding",
      project: "internal_ui",
      language: "Ruby",
      editor: "VS Code",
      entity: "/app/internal_ui/app/page.tsx",
      is_write: true,
      line_additions: 8,
      source_type: :test_entry
    )

    user
  end
end
