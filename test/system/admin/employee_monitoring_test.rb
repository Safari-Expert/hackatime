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

  test "activity chart and commit counts render when activity exists" do
    admin = User.create!(timezone: "UTC", admin_level: "admin", github_username: "admin-monitoring-2")
    monitored = create_monitored_user("active-dev")
    create_commit(monitored, at: 1.minute.ago)

    sign_in_as(admin)
    visit admin_employee_monitoring_path(user_id: monitored.id)

    within(:xpath, "//h3[contains(., '5-minute activity chart')]/ancestor::div[contains(@class, 'rounded-2xl')][1]") do
      assert_button "Adds / Deletes"
      assert_button "Languages"
      assert_text "Line churn by 5-minute bucket"
      assert_text "Presence status"

      status_rail = find(".status-rail")
      assert_equal status_rail["data-bucket-count"].to_i, all(".status-rail__segment").count
    end

    within(:xpath, "//h3[contains(., 'Delivery detail')]/ancestor::div[contains(@class, 'rounded-2xl')][1]") do
      commits_row = find("span", text: "Commits").find(:xpath, "..")
      assert_equal "1", commits_row.find("strong").text
    end
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

  def create_commit(user, at:)
    Commit.create!(
      sha: "system-test-sha-#{SecureRandom.hex(4)}",
      user: user,
      github_raw: {
        "stats" => {
          "additions" => 12,
          "deletions" => 3
        },
        "html_url" => "https://github.com/Safari-Expert/hackatime/commit/system-test",
        "commit" => {
          "committer" => {
            "date" => at.utc.iso8601
          }
        }
      },
      created_at: at,
      updated_at: at
    )
  end
end
