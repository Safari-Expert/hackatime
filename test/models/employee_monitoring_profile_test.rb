require "test_helper"

class EmployeeMonitoringProfileTest < ActiveSupport::TestCase
  test "provides a default weekday schedule for new monitored users" do
    user = User.create!(timezone: "UTC", github_username: "profile-defaults")

    profile = EmployeeMonitoringProfile.for_user(user)

    assert profile.monitoring_enabled
    assert_equal [ 1, 2, 3, 4, 5 ], profile.normalized_workdays
    assert_equal "Mon-Fri · 09:00-17:00", profile.schedule_label(user: user)
  end

  test "calculates schedule windows across dst boundaries" do
    user = User.create!(timezone: "UTC", github_username: "profile-dst")
    profile = EmployeeMonitoringProfile.for_user(user)
    profile.timezone_override = "America/New_York"
    profile.workdays = [ 0, 1, 2, 3, 4, 5, 6 ]

    pre_dst_window = profile.schedule_window(Date.new(2026, 3, 7), user: user)
    post_dst_window = profile.schedule_window(Date.new(2026, 3, 9), user: user)

    assert_equal "2026-03-07T14:00:00Z", pre_dst_window[:start_at].utc.iso8601
    assert_equal "2026-03-09T13:00:00Z", post_dst_window[:start_at].utc.iso8601
  end

  test "rejects an end minute before the start minute" do
    user = User.create!(timezone: "UTC", github_username: "profile-invalid")
    profile = EmployeeMonitoringProfile.for_user(user)
    profile.expected_start_minute_local = 1020
    profile.expected_end_minute_local = 540

    assert_not profile.valid?
    assert_includes profile.errors[:expected_end_minute_local], "must be after the start minute"
  end
end
