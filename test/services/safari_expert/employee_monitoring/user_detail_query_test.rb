require "test_helper"

class SafariExpert::EmployeeMonitoring::UserDetailQueryTest < ActiveSupport::TestCase
  test "returns schedule and commit metrics for the selected user" do
    travel_to Time.utc(2026, 3, 30, 9, 12, 0) do
      user = User.create!(timezone: "UTC", github_username: "detail-query")
      EmployeeMonitoringProfile.for_user(user).save!

      create_heartbeat(user, at: Time.utc(2026, 3, 30, 9, 0, 0), additions: 12)
      create_heartbeat(user, at: Time.utc(2026, 3, 30, 9, 4, 0), additions: 8)

      Commit.create!(
        sha: "detail-query-sha",
        user: user,
        github_raw: {
          "stats" => {
            "additions" => 120,
            "deletions" => 20
          },
          "html_url" => "https://github.com/Safari-Expert/hackatime/commit/detail-query-sha",
          "commit" => {
            "committer" => {
              "date" => "2026-03-30T09:06:00Z"
            }
          }
        },
        created_at: Time.utc(2026, 3, 30, 9, 6, 0),
        updated_at: Time.utc(2026, 3, 30, 9, 6, 0)
      )

      payload = SafariExpert::EmployeeMonitoring::UserDetailQuery.new(
        user: user,
        now: Time.current
      ).call

      assert_equal user.id, payload[:id]
      assert_equal "Mon-Fri · 09:00-17:00", payload[:schedule][:label]
      assert_equal 1, payload[:current_day][:commit_count]
      assert_equal 120, payload[:current_day][:commit_line_additions]
      assert_equal 20, payload[:current_day][:commit_line_deletions]
      assert_equal 1, payload[:current_day][:project_mix].length
      assert_equal 1, payload[:current_day][:language_mix].length
      assert_equal 1, payload[:current_day][:editor_mix].length
      assert_equal 1, payload[:current_day][:commit_markers].length
      assert_equal "detail-query-sha", payload[:current_day][:commit_markers].first[:sha]
      assert_equal payload[:current_day][:local_date], payload[:history].first[:local_date]

      bucket = payload[:current_day][:timeline_buckets].find { |entry| entry[:bucket_started_at] == "2026-03-30T09:00:00Z" }

      assert_not_nil bucket
      assert_equal 20, bucket[:line_additions]
      assert_equal 0, bucket[:line_deletions]
      assert_equal [ "Ruby" ], bucket[:languages]
      assert_equal(
        [
          {
            language: "Ruby",
            coding_seconds: 180,
            line_additions: 20,
            line_deletions: 0
          }
        ],
        bucket[:language_breakdown]
      )
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
