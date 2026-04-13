require "test_helper"

class Admin::EmployeeMonitoringControllerTest < ActionDispatch::IntegrationTest
  setup do
    @search_term = "employee-monitoring-controller-spec"
    @viewer = User.create!(timezone: "UTC", admin_level: "viewer", github_username: "viewer-user")
    @admin = User.create!(timezone: "UTC", admin_level: "admin", github_username: "admin-user")
    @regular_user = User.create!(timezone: "UTC", github_username: "regular-user")
    @monitored = User.create!(timezone: "UTC", github_username: "#{@search_term}-monitored")
    @monitored.create_employee_monitoring_profile!
    bucket_started_at = monitoring_reference_time.change(min: 30, sec: 0)
    Heartbeat.create!(
      user: @monitored,
      time: (bucket_started_at + 30.seconds).to_i,
      category: "coding",
      project: "internal_ui",
      language: "Ruby",
      editor: "VS Code",
      entity: "/app/internal_ui/app/page.tsx",
      is_write: true,
      line_additions: 0,
      line_deletions: 0,
      source_type: :test_entry
    )
    Heartbeat.create!(
      user: @monitored,
      time: (bucket_started_at + 2.minutes).to_i,
      category: "coding",
      project: "internal_ui",
      language: "Go",
      editor: "VS Code",
      entity: "/app/internal_ui/app/page.tsx",
      is_write: true,
      line_additions: 0,
      line_deletions: 0,
      source_type: :test_entry
    )
    Commit.create!(
      sha: "controller-monitoring-commit",
      user: @monitored,
      github_raw: {
        "files" => [
          {
            "filename" => "app/internal_ui/app/page.tsx",
            "additions" => 12,
            "deletions" => 3
          },
          {
            "filename" => "app/internal_ui/app/table.tsx",
            "additions" => 8,
            "deletions" => 2
          }
        ],
        "html_url" => "https://github.com/Safari-Expert/internal_ui/commit/controller-monitoring-commit",
        "commit" => {
          "committer" => {
            "date" => (bucket_started_at + 90.seconds).utc.iso8601
          }
        }
      },
      created_at: bucket_started_at + 90.seconds,
      updated_at: bucket_started_at + 90.seconds
    )
    sign_in_as(@viewer)
  end

  test "renders the employee monitoring page for viewers" do
    travel_to monitoring_reference_time do
      get employee_monitoring_path(user_id: @monitored.id, search: @search_term)

      assert_response :success
      assert_inertia_component "SafariExpert/EmployeeMonitoring/Index"
      assert_equal "Employee Monitoring", inertia_page.dig("props", "page_title")
      assert_equal false, inertia_page.dig("props", "can_edit_schedule")
      assert_equal @monitored.id, inertia_page.dig("props", "selected_user", "id")
      assert_equal 1, inertia_page.dig("props", "overview", "summary", "monitored_users")
      assert_equal 1, inertia_page.dig("props", "overview", "roster").length
      assert_not_nil inertia_page.dig("props", "selected_user", "current_day", "write_heartbeats_count")
      assert_not_nil inertia_page.dig("props", "selected_user", "schedule", "label")

      current_bucket = inertia_page.dig("props", "selected_user", "current_day", "timeline_buckets")
                                  .find { |bucket| bucket["bucket_started_at"] == "2026-04-13T14:30:00Z" }

      assert_not_nil current_bucket
      assert_equal 20, current_bucket["line_additions"]
      assert_equal 5, current_bucket["line_deletions"]
      assert_equal 150, current_bucket["coding_seconds"]
      assert_equal [ "Ruby", "Go" ], current_bucket["languages"]
      assert_equal(
        [
          {
            "language" => "Ruby",
            "coding_seconds" => 90,
            "line_additions" => 0,
            "line_deletions" => 0
          },
          {
            "language" => "Go",
            "coding_seconds" => 60,
            "line_additions" => 0,
            "line_deletions" => 0
          }
        ],
        current_bucket["language_breakdown"]
      )
    end
  end

  test "renders the employee monitoring page read-only for regular users" do
    travel_to monitoring_reference_time do
      sign_in_as(@regular_user)

      get employee_monitoring_path(user_id: @monitored.id, search: @search_term)

      assert_response :success
      assert_inertia_component "SafariExpert/EmployeeMonitoring/Index"
      assert_equal false, inertia_page.dig("props", "can_edit_schedule")
      assert_equal @monitored.id, inertia_page.dig("props", "selected_user", "id")
    end
  end

  test "keeps after-hours bucket status active on the timeline payload" do
    travel_to Time.utc(2026, 4, 13, 20, 3, 0) do
      Heartbeat.create!(
        user: @monitored,
        time: Time.utc(2026, 4, 13, 20, 0, 0).to_i,
        category: "coding",
        project: "internal_ui",
        language: "Ruby",
        editor: "VS Code",
        entity: "/app/internal_ui/app/page.tsx",
        is_write: true,
        line_additions: 3,
        line_deletions: 1,
        source_type: :test_entry
      )

      get employee_monitoring_path(user_id: @monitored.id, search: @search_term)

      assert_response :success
      assert_equal "after_end", inertia_page.dig("props", "selected_user", "current_day", "status")

      current_bucket = inertia_page.dig("props", "selected_user", "current_day", "timeline_buckets")
                                  .find { |bucket| bucket["bucket_started_at"] == "2026-04-13T20:00:00Z" }

      assert_not_nil current_bucket
      assert_equal "active", current_bucket["status"]
      assert_equal false, current_bucket["in_window"]
    end
  end

  test "legacy admin path redirects to the canonical employee monitoring path" do
    travel_to monitoring_reference_time do
      get admin_employee_monitoring_path(user_id: @monitored.id, search: @search_term)

      assert_response :redirect
      assert_redirected_to employee_monitoring_path(user_id: @monitored.id, search: @search_term)
    end
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
        start_grace_minutes: 5,
        end_grace_minutes: 10,
        schedule_days: {
          "0" => {
            weekday: 1,
            enabled: "true",
            expected_start_minute_local: "08:30",
            expected_end_minute_local: "17:30"
          },
          "1" => {
            weekday: 2,
            enabled: "true",
            expected_start_minute_local: "08:30",
            expected_end_minute_local: "17:30"
          },
          "2" => {
            weekday: 3,
            enabled: "true",
            expected_start_minute_local: "08:30",
            expected_end_minute_local: "17:30"
          },
          "3" => {
            weekday: 4,
            enabled: "true",
            expected_start_minute_local: "08:30",
            expected_end_minute_local: "17:30"
          },
          "4" => {
            weekday: 5,
            enabled: "true",
            expected_start_minute_local: "08:30",
            expected_end_minute_local: "17:30"
          }
        }
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
    assert_equal [ 1, 2, 3, 4, 5 ], @monitored.employee_monitoring_schedule_days.ordered.pluck(:weekday)
    assert_equal [ 510 ], @monitored.employee_monitoring_schedule_days.distinct.pluck(:expected_start_minute_local)
    assert_equal [ 1050 ], @monitored.employee_monitoring_schedule_days.distinct.pluck(:expected_end_minute_local)
  end

  test "renders the simplified detail payload for external users" do
    external_user = User.create!(
      timezone: "UTC",
      account_kind: :external,
      display_name_override: "External Worker",
      username: "external-worker",
      password: "supersecure123"
    )
    external_user.create_employee_monitoring_profile!
    external_user.external_work_sessions.create!(
      started_at: Time.utc(2026, 4, 13, 9, 0, 0),
      ended_at: Time.utc(2026, 4, 13, 12, 0, 0),
      close_reason: :user_clock_out
    )

    travel_to monitoring_reference_time do
      sign_in_as(@admin)

      get employee_monitoring_path(user_id: external_user.id)

      assert_response :success
      assert_equal "external", inertia_page.dig("props", "selected_user", "account_kind")
      assert_equal "clocked_out", inertia_page.dig("props", "selected_user", "attendance", "state")
      assert_equal 3.hours.to_i, inertia_page.dig("props", "selected_user", "attendance", "today_seconds")
      assert_equal true, inertia_page.dig("props", "overview", "roster").any? { |row| row["id"] == external_user.id && row["account_kind"] == "external" }
      assert_equal 7, inertia_page.dig("props", "selected_user", "schedule", "schedule_days").length
    end
  end

  test "external users get a self-only dashboard and can clock in and out" do
    external_user = User.create!(
      timezone: "UTC",
      account_kind: :external,
      display_name_override: "External Worker",
      username: "external-self",
      password: "supersecure123"
    )
    external_user.create_employee_monitoring_profile!
    sign_in_as(external_user)

    get employee_monitoring_path(user_id: @monitored.id)

    assert_response :success
    assert_inertia_component "SafariExpert/EmployeeMonitoring/ExternalDashboard"
    assert_equal external_user.id, inertia_page.dig("props", "user", "id")

    travel_to Time.utc(2026, 4, 13, 9, 0, 0) do
      post employee_monitoring_clock_in_path
    end

    assert_redirected_to employee_monitoring_path
    assert external_user.external_work_sessions.open.exists?

    travel_to Time.utc(2026, 4, 13, 17, 0, 0) do
      post employee_monitoring_clock_out_path
    end

    assert_redirected_to employee_monitoring_path
    assert_not external_user.external_work_sessions.open.exists?
  end

  private

  def monitoring_reference_time
    Time.utc(2026, 4, 13, 14, 33, 0)
  end
end
