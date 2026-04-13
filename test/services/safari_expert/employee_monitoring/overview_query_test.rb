require "test_helper"

class SafariExpert::EmployeeMonitoring::OverviewQueryTest < ActiveSupport::TestCase
  test "summarizes roster status counts" do
    travel_to Time.utc(2026, 3, 30, 9, 20, 0) do
      search_term = "employee-monitoring-spec"

      active_user = User.create!(timezone: "UTC", github_username: "#{search_term}-active-user")
      EmployeeMonitoringProfile.for_user(active_user).save!
      create_heartbeat(active_user, at: Time.utc(2026, 3, 30, 9, 18, 0))

      idle_user = User.create!(timezone: "UTC", github_username: "#{search_term}-idle-user")
      EmployeeMonitoringProfile.for_user(idle_user).save!
      create_heartbeat(idle_user, at: Time.utc(2026, 3, 30, 9, 5, 0))

      no_show_user = User.create!(timezone: "UTC", github_username: "#{search_term}-no-show-user")
      EmployeeMonitoringProfile.for_user(no_show_user).save!

      overview = SafariExpert::EmployeeMonitoring::OverviewQuery.new(
        now: Time.current,
        search: search_term
      ).call

      assert_equal 3, overview[:summary][:monitored_users]
      assert_equal 1, overview[:summary][:active_in_window]
      assert_equal 1, overview[:summary][:idle_in_window]
      assert_equal 2, overview[:summary][:not_started_yet]
      assert_equal 0, overview[:summary][:ended_early]
      assert_equal 3, overview[:roster].length
      assert_equal active_user.id, overview[:roster].first[:id]
    end
  end

  test "counts after-hours and ended-early states separately" do
    travel_to Time.utc(2026, 3, 30, 18, 5, 0) do
      search_term = "employee-monitoring-after-hours-spec"

      after_hours_user = User.create!(timezone: "UTC", github_username: "#{search_term}-after-hours-user")
      EmployeeMonitoringProfile.for_user(after_hours_user).save!
      create_heartbeat(after_hours_user, at: Time.utc(2026, 3, 30, 18, 0, 0))

      ended_early_user = User.create!(timezone: "UTC", github_username: "#{search_term}-ended-early-user")
      EmployeeMonitoringProfile.for_user(ended_early_user).save!
      create_heartbeat(ended_early_user, at: Time.utc(2026, 3, 30, 16, 30, 0))

      no_show_user = User.create!(timezone: "UTC", github_username: "#{search_term}-no-show-user")
      EmployeeMonitoringProfile.for_user(no_show_user).save!

      overview = SafariExpert::EmployeeMonitoring::OverviewQuery.new(
        now: Time.current,
        search: search_term
      ).call

      assert_equal 3, overview[:summary][:monitored_users]
      assert_equal 0, overview[:summary][:active_in_window]
      assert_equal 0, overview[:summary][:idle_in_window]
      assert_equal 3, overview[:summary][:not_started_yet]
      assert_equal 1, overview[:summary][:ended_early]
      assert_equal 1, overview[:summary][:after_hours_active]
    end
  end

  private

  def create_heartbeat(user, at:, category: "coding", is_write: true, additions: 0, deletions: 0)
    Heartbeat.create!(
      user: user,
      time: at.to_i,
      category: category,
      source_type: :test_entry,
      project: "hackatime",
      language: "Ruby",
      editor: "VS Code",
      entity: "/app/hackatime/app/models/user.rb",
      is_write: is_write,
      line_additions: additions,
      line_deletions: deletions
    )
  end
end
