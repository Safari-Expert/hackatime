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

  test "returns individual same-day session spans for the attendance timeline" do
    user = User.create!(
      timezone: "UTC",
      account_kind: :external,
      display_name_override: "Session Timeline Worker",
      username: "session-timeline",
      password: "supersecure123"
    )
    user.create_employee_monitoring_profile!

    user.external_work_sessions.create!(
      started_at: Time.utc(2026, 4, 13, 9, 0, 0),
      ended_at: Time.utc(2026, 4, 13, 12, 0, 0),
      close_reason: :user_clock_out
    )
    user.external_work_sessions.create!(
      started_at: Time.utc(2026, 4, 13, 13, 30, 0),
      ended_at: Time.utc(2026, 4, 13, 17, 15, 0),
      close_reason: :user_clock_out
    )

    travel_to Time.utc(2026, 4, 13, 18, 0, 0) do
      payload = SafariExpert::EmployeeMonitoring::ExternalAttendanceQuery.new(user: user, now: Time.current).call
      timeline = payload.dig(:attendance, :timeline)
      sessions = timeline[:sessions]

      assert_equal 2, timeline[:session_count]
      assert_equal 2, sessions.length
      assert_equal 6.hours + 45.minutes, payload.dig(:attendance, :today_seconds)
      assert_equal "2026-04-13T00:00:00Z", timeline[:day_start_at]
      assert_equal "2026-04-14T00:00:00Z", timeline[:day_end_at]
      assert_equal Time.utc(2026, 4, 13, 9, 0, 0).iso8601, sessions.first[:started_at]
      assert_equal Time.utc(2026, 4, 13, 12, 0, 0).iso8601, sessions.first[:ended_at]
      assert_equal 3.hours, sessions.first[:duration_seconds]
      assert_equal Time.utc(2026, 4, 13, 13, 30, 0).iso8601, sessions.last[:display_started_at]
      assert_equal Time.utc(2026, 4, 13, 17, 15, 0).iso8601, sessions.last[:display_ended_at]
      assert_equal "closed", sessions.last[:state]
    end
  end
end
