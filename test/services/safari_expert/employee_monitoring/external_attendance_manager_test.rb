require "test_helper"

class SafariExpert::EmployeeMonitoring::ExternalAttendanceManagerTest < ActiveSupport::TestCase
  test "prevents overlapping open sessions" do
    user = User.create!(
      timezone: "UTC",
      account_kind: :external,
      display_name_override: "Overlap Tester",
      username: "overlap-tester",
      password: "supersecure123"
    )

    travel_to Time.utc(2026, 4, 13, 9, 0, 0) do
      manager = SafariExpert::EmployeeMonitoring::ExternalAttendanceManager.new(user: user, now: Time.current)
      manager.clock_in!

      error = assert_raises(SafariExpert::EmployeeMonitoring::ExternalAttendanceManager::Error) do
        manager.clock_in!
      end

      assert_equal "You are already clocked in.", error.message
    end
  end

  test "allows a second session after clocking out" do
    user = User.create!(
      timezone: "UTC",
      account_kind: :external,
      display_name_override: "Sequential Sessions",
      username: "sequential-sessions",
      password: "supersecure123"
    )

    travel_to Time.utc(2026, 4, 13, 9, 0, 0) do
      SafariExpert::EmployeeMonitoring::ExternalAttendanceManager.new(user: user, now: Time.current).clock_in!
    end

    travel_to Time.utc(2026, 4, 13, 12, 0, 0) do
      SafariExpert::EmployeeMonitoring::ExternalAttendanceManager.new(user: user, now: Time.current).clock_out!
    end

    travel_to Time.utc(2026, 4, 13, 13, 0, 0) do
      SafariExpert::EmployeeMonitoring::ExternalAttendanceManager.new(user: user, now: Time.current).clock_in!
    end

    assert_equal 2, user.external_work_sessions.count
    assert_equal 1, user.external_work_sessions.open.count
    assert_equal Time.utc(2026, 4, 13, 9, 0, 0), user.external_work_sessions.ordered.first.started_at
    assert_equal Time.utc(2026, 4, 13, 13, 0, 0), user.external_work_sessions.ordered.last.started_at
  end
end
