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
end
