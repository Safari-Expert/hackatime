require "test_helper"

class SafariExpert::EmployeeMonitoring::RollupBuilderTest < ActiveSupport::TestCase
  test "builds attendance activity and delivery signals from heartbeats and commits" do
    travel_to Time.utc(2026, 3, 30, 9, 12, 0) do
      user = User.create!(timezone: "UTC", github_username: "rollup-signals")
      profile = EmployeeMonitoringProfile.for_user(user)
      profile.save!

      create_heartbeat(user, at: Time.utc(2026, 3, 30, 9, 0, 0), additions: 18)
      create_heartbeat(user, at: Time.utc(2026, 3, 30, 9, 2, 0), additions: 18)
      create_heartbeat(user, at: Time.utc(2026, 3, 30, 9, 4, 0), additions: 18)
      create_heartbeat(user, at: Time.utc(2026, 3, 30, 9, 6, 0), additions: 18)
      create_heartbeat(user, at: Time.utc(2026, 3, 30, 9, 8, 0), additions: 18)
      create_heartbeat(
        user,
        at: Time.utc(2026, 3, 30, 9, 10, 0),
        category: "writing docs",
        is_write: false,
        additions: 0,
        deletions: 0
      )
      Commit.create!(
        sha: "rollup-signals-sha",
        user: user,
        github_raw: {
          "stats" => {
            "additions" => 120,
            "deletions" => 20
          },
          "html_url" => "https://github.com/Safari-Expert/internal_ui/commit/rollup-signals-sha",
          "commit" => {
            "committer" => {
              "date" => "2026-03-30T09:09:00Z"
            }
          }
        },
        created_at: Time.utc(2026, 3, 30, 9, 9, 0),
        updated_at: Time.utc(2026, 3, 30, 9, 9, 0)
      )

      payload = SafariExpert::EmployeeMonitoring::RollupBuilder.new(
        user: user,
        now: Time.current
      ).call

      assert_equal "active", payload[:status]
      assert_equal false, payload[:not_started_yet]
      assert_equal 1, payload[:commit_count]
      assert_equal 120, payload[:commit_line_additions]
      assert_equal 20, payload[:commit_line_deletions]
      assert_equal "high", payload[:activity_signal]
      assert_equal "steady", payload[:delivery_signal]
      assert_equal "moderate", payload[:ai_assisted_output_level]
      assert_equal 100.0, payload[:coverage_percent]
      assert_equal 16, payload[:timeline_buckets].length
      assert_equal 1, payload[:session_count]
    end
  end

  test "marks users as not started once the grace window passes" do
    travel_to Time.utc(2026, 3, 30, 9, 20, 0) do
      user = User.create!(timezone: "UTC", github_username: "rollup-no-start")
      EmployeeMonitoringProfile.for_user(user).save!

      payload = SafariExpert::EmployeeMonitoring::RollupBuilder.new(
        user: user,
        now: Time.current
      ).call

      assert_equal "inactive", payload[:status]
      assert payload[:not_started_yet]
      assert_equal "not_started", payload[:attendance_signal]
      assert_equal 0, payload[:presence_seconds]
      assert_equal 0, payload[:commit_count]
    end
  end

  private

  def create_heartbeat(user, at:, category: "coding", is_write: true, additions: 0, deletions: 0)
    Heartbeat.create!(
      user: user,
      time: at.to_i,
      category: category,
      source_type: :test_entry,
      project: "internal_ui",
      language: "Ruby",
      editor: "VS Code",
      entity: "/app/internal_ui/app/models/employee.rb",
      is_write: is_write,
      line_additions: additions,
      line_deletions: deletions
    )
  end
end
