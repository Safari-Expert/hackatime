require "test_helper"

class SafariExpert::EmployeeMonitoring::ExternalAttendanceQueryTest < ActiveSupport::TestCase
  test "aggregates totals and current week statuses in the user's timezone" do
    user = User.create!(
      timezone: "America/New_York",
      account_kind: :external,
      display_name_override: "External Worker",
      username: "external-worker",
      password: "supersecure123"
    )
    user.create_employee_monitoring_profile!(
      timezone_override: "America/New_York",
      start_grace_minutes: 10,
      end_grace_minutes: 15
    )
    user.employee_monitoring_profile.update_schedule_days!([
      { weekday: 1, expected_start_minute_local: 9 * 60, expected_end_minute_local: 17 * 60 },
      { weekday: 2, expected_start_minute_local: 9 * 60, expected_end_minute_local: 17 * 60 },
      { weekday: 3, expected_start_minute_local: 9 * 60, expected_end_minute_local: 17 * 60 },
      { weekday: 4, expected_start_minute_local: 9 * 60, expected_end_minute_local: 17 * 60 },
      { weekday: 5, expected_start_minute_local: 9 * 60, expected_end_minute_local: 17 * 60 }
    ])

    monday_start = Time.utc(2026, 4, 13, 13, 20, 0) # 09:20 local
    monday_end = Time.utc(2026, 4, 13, 21, 10, 0)   # 17:10 local
    tuesday_start = Time.utc(2026, 4, 14, 20, 0, 0) # 16:00 local

    user.external_work_sessions.create!(started_at: monday_start, ended_at: monday_end, close_reason: :user_clock_out)
    user.external_work_sessions.create!(started_at: tuesday_start, ended_at: Time.utc(2026, 4, 14, 23, 59, 0), close_reason: :auto_closed_eod)

    travel_to Time.utc(2026, 4, 14, 23, 59, 0) do
      payload = SafariExpert::EmployeeMonitoring::ExternalAttendanceQuery.new(user: user, now: Time.current).call
      monday_row = payload.dig(:attendance, :week_rows).find { |row| row[:local_date] == "2026-04-13" }
      tuesday_row = payload.dig(:attendance, :week_rows).find { |row| row[:local_date] == "2026-04-14" }

      assert_equal "clocked_out", payload.dig(:attendance, :state)
      assert_operator payload.dig(:attendance, :week_seconds), :>, 0
      assert_equal payload.dig(:attendance, :week_seconds), payload.dig(:attendance, :month_seconds)
      assert_equal "late", monday_row[:start_status]
      assert_equal "short", monday_row[:hours_status]
      assert_equal "late", tuesday_row[:start_status]
      assert_equal "not_clocked_out", tuesday_row[:hours_status]
    end
  end
end
