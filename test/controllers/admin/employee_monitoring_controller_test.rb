require "test_helper"

class Admin::EmployeeMonitoringControllerTest < ActionDispatch::IntegrationTest
  setup do
    @search_term = "employee-monitoring-controller-spec"
    @viewer = User.create!(timezone: "UTC", admin_level: "viewer", github_username: "viewer-user")
    @admin = User.create!(timezone: "UTC", admin_level: "admin", github_username: "admin-user")
    @regular_user = User.create!(timezone: "UTC", github_username: "regular-user")
    @monitored = User.create!(timezone: "UTC", github_username: "#{@search_term}-monitored")
    @monitored.create_employee_monitoring_profile!
    Heartbeat.create!(
      user: @monitored,
      time: 5.minutes.ago.to_i,
      category: "coding",
      project: "internal_ui",
      language: "Ruby",
      editor: "VS Code",
      entity: "/app/internal_ui/app/page.tsx",
      is_write: true,
      source_type: :test_entry
    )
    sign_in_as(@viewer)
  end

  test "renders the employee monitoring page for viewers" do
    get employee_monitoring_path(user_id: @monitored.id, search: @search_term)

    assert_response :success
    assert_inertia_component "SafariExpert/EmployeeMonitoring/Index"
    assert_equal "Employee Monitoring", inertia_page.dig("props", "page_title")
    assert_equal false, inertia_page.dig("props", "can_edit_schedule")
    assert_equal @monitored.id, inertia_page.dig("props", "selected_user", "id")
    assert_equal 1, inertia_page.dig("props", "overview", "summary", "monitored_users")
    assert_equal 1, inertia_page.dig("props", "overview", "roster").length
    assert_not_nil inertia_page.dig("props", "selected_user", "current_day", "write_heartbeats_count")
    assert_not_nil inertia_page.dig("props", "selected_user", "current_day", "timeline_buckets", 0, "line_additions")
    assert_not_nil inertia_page.dig("props", "selected_user", "current_day", "timeline_buckets", 0, "language_breakdown")
    assert_not_nil inertia_page.dig("props", "selected_user", "schedule", "label")
  end

  test "renders the employee monitoring page read-only for regular users" do
    sign_in_as(@regular_user)

    get employee_monitoring_path(user_id: @monitored.id, search: @search_term)

    assert_response :success
    assert_inertia_component "SafariExpert/EmployeeMonitoring/Index"
    assert_equal false, inertia_page.dig("props", "can_edit_schedule")
    assert_equal @monitored.id, inertia_page.dig("props", "selected_user", "id")
  end

  test "legacy admin path redirects to the canonical employee monitoring path" do
    get admin_employee_monitoring_path(user_id: @monitored.id, search: @search_term)

    assert_response :redirect
    assert_redirected_to employee_monitoring_path(user_id: @monitored.id, search: @search_term)
  end

  test "prevents viewers from updating schedules" do
    patch admin_employee_monitoring_user_profile_path(id: @monitored.id), params: {
      profile: {
        timezone_override: "Africa/Nairobi"
      }
    }

    assert_redirected_to employee_monitoring_path(user_id: @monitored.id)
    assert_nil @monitored.employee_monitoring_profile.reload.timezone_override
  end

  test "prevents regular users from updating schedules" do
    sign_in_as(@regular_user)

    patch admin_employee_monitoring_user_profile_path(id: @monitored.id), params: {
      profile: {
        timezone_override: "Africa/Nairobi"
      }
    }

    assert_response :not_found
    assert_nil @monitored.employee_monitoring_profile.reload.timezone_override
  end

  test "allows admins to update schedules" do
    sign_in_as(@admin)

    patch admin_employee_monitoring_user_profile_path(id: @monitored.id), params: {
      profile: {
        timezone_override: "Africa/Nairobi",
        expected_start_minute_local: "08:30",
        expected_end_minute_local: "17:30",
        start_grace_minutes: 5,
        end_grace_minutes: 10,
        workdays: [ 1, 2, 3, 4, 5 ]
      }
    }

    assert_redirected_to employee_monitoring_path(user_id: @monitored.id)
    profile = @monitored.employee_monitoring_profile.reload
    assert_equal "Africa/Nairobi", profile.timezone_override
    assert_equal 510, profile.expected_start_minute_local
    assert_equal 1050, profile.expected_end_minute_local
    assert_equal 5, profile.start_grace_minutes
    assert_equal 10, profile.end_grace_minutes
    assert_equal [ 1, 2, 3, 4, 5 ], profile.normalized_workdays
  end
end
