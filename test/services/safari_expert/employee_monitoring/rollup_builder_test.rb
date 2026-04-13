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
      create_commit(
        user,
        at: Time.utc(2026, 3, 30, 9, 9, 0),
        additions: 120,
        deletions: 20,
        stats: false,
        sha: "rollup-signals-sha"
      )

      payload = SafariExpert::EmployeeMonitoring::RollupBuilder.new(
        user: user,
        now: Time.current
      ).call

      assert_equal "active", payload[:status]
      assert_equal false, payload[:not_started_yet]
      assert_equal 5, payload[:write_heartbeats_count]
      assert_equal 1, payload[:unique_files_count]
      assert_equal 1, payload[:unique_projects_count]
      assert_equal 1, payload[:unique_languages_count]
      assert_equal 0, payload[:gap_count]
      assert_equal 1, payload[:commit_count]
      assert_equal 120, payload[:commit_line_additions]
      assert_equal 20, payload[:commit_line_deletions]
      assert_equal "high", payload[:activity_signal]
      assert_equal "steady", payload[:delivery_signal]
      assert_equal "moderate", payload[:ai_assisted_output_level]
      assert_equal 100.0, payload[:coverage_percent]
      assert_equal 16, payload[:timeline_buckets].length
      assert_equal 1, payload[:session_count]
      assert_equal 1, payload[:commit_markers].length
      assert_equal "rollup-signals-sha", payload[:commit_markers].first[:sha]
    end
  end

  test "builds bucket churn and language breakdown and persists the current snapshot" do
    travel_to Time.utc(2026, 3, 30, 9, 4, 30) do
      user = User.create!(timezone: "UTC", github_username: "bucket-breakdown-user")
      EmployeeMonitoringProfile.for_user(user).save!

      create_heartbeat(
        user,
        at: Time.utc(2026, 3, 30, 9, 0, 0),
        language: nil,
        additions: 10,
        deletions: 2
      )
      create_heartbeat(
        user,
        at: Time.utc(2026, 3, 30, 9, 4, 0),
        language: "Ruby",
        additions: 6,
        deletions: 1
      )

      payload = SafariExpert::EmployeeMonitoring::RollupBuilder.new(
        user: user,
        now: Time.current,
        persist: true
      ).call

      bucket = payload[:timeline_buckets].find { |entry| entry[:bucket_started_at] == "2026-03-30T09:00:00Z" }

      assert_not_nil bucket
      assert_equal 150, bucket[:presence_seconds]
      assert_equal 150, bucket[:coding_seconds]
      assert_equal 2, bucket[:write_heartbeats_count]
      assert_equal 16, bucket[:line_additions]
      assert_equal 3, bucket[:line_deletions]
      assert_equal [ "Unknown", "Ruby" ], bucket[:languages]
      assert_equal(
        [
          {
            language: "Unknown",
            coding_seconds: 120,
            line_additions: 10,
            line_deletions: 2
          },
          {
            language: "Ruby",
            coding_seconds: 30,
            line_additions: 6,
            line_deletions: 1
          }
        ],
        bucket[:language_breakdown]
      )

      snapshot = EmployeeMonitoringIntervalSnapshot.find_by!(user: user, bucket_started_at: Time.utc(2026, 3, 30, 9, 0, 0))
      assert_equal 16, snapshot.line_additions
      assert_equal 3, snapshot.line_deletions
      assert_equal [ "Unknown", "Ruby" ], snapshot.languages
      assert_equal bucket[:language_breakdown].map(&:deep_stringify_keys), snapshot.language_breakdown
    end
  end

  test "uses commit churn in bucket totals when heartbeat deltas are blank" do
    travel_to Time.utc(2026, 3, 30, 9, 4, 30) do
      user = User.create!(timezone: "UTC", github_username: "commit-bucket-user")
      EmployeeMonitoringProfile.for_user(user).save!

      create_heartbeat(
        user,
        at: Time.utc(2026, 3, 30, 9, 0, 0),
        language: "Ruby",
        additions: 0,
        deletions: 0
      )
      create_heartbeat(
        user,
        at: Time.utc(2026, 3, 30, 9, 4, 0),
        language: "Go",
        additions: 0,
        deletions: 0
      )
      create_commit(
        user,
        at: Time.utc(2026, 3, 30, 9, 3, 0),
        additions: 20,
        deletions: 5,
        stats: false
      )

      payload = SafariExpert::EmployeeMonitoring::RollupBuilder.new(
        user: user,
        now: Time.current,
        persist: true
      ).call

      bucket = payload[:timeline_buckets].find { |entry| entry[:bucket_started_at] == "2026-03-30T09:00:00Z" }

      assert_not_nil bucket
      assert_equal 20, bucket[:line_additions]
      assert_equal 5, bucket[:line_deletions]
      assert_equal 20, payload[:commit_line_additions]
      assert_equal 5, payload[:commit_line_deletions]
      assert_equal(
        [
          {
            language: "Ruby",
            coding_seconds: 120,
            line_additions: 0,
            line_deletions: 0
          },
          {
            language: "Go",
            coding_seconds: 30,
            line_additions: 0,
            line_deletions: 0
          }
        ],
        bucket[:language_breakdown]
      )

      snapshot = EmployeeMonitoringIntervalSnapshot.find_by!(user: user, bucket_started_at: Time.utc(2026, 3, 30, 9, 0, 0))
      assert_equal 20, snapshot.line_additions
      assert_equal 5, snapshot.line_deletions
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

  test "flags after-hours activity when the last heartbeat is outside the schedule window" do
    travel_to Time.utc(2026, 3, 30, 18, 3, 0) do
      user = User.create!(timezone: "UTC", github_username: "after-hours-user")
      EmployeeMonitoringProfile.for_user(user).save!

      create_heartbeat(user, at: Time.utc(2026, 3, 30, 18, 0, 0))

      payload = SafariExpert::EmployeeMonitoring::RollupBuilder.new(
        user: user,
        now: Time.current
      ).call

      assert_equal "after_end", payload[:status]
      assert payload[:after_hours_active]
      assert_equal false, payload[:ended_early]
    end
  end

  test "marks users as ended early when activity stops before the end window" do
    travel_to Time.utc(2026, 3, 30, 17, 30, 0) do
      user = User.create!(timezone: "UTC", github_username: "ended-early-user")
      EmployeeMonitoringProfile.for_user(user).save!

      create_heartbeat(user, at: Time.utc(2026, 3, 30, 16, 30, 0))

      payload = SafariExpert::EmployeeMonitoring::RollupBuilder.new(
        user: user,
        now: Time.current
      ).call

      assert_equal "after_end", payload[:status]
      assert payload[:ended_early]
      assert_equal false, payload[:after_hours_active]
    end
  end

  test "builds presence buckets with active and idle states when heartbeats drift" do
    travel_to Time.utc(2026, 3, 30, 9, 20, 0) do
      user = User.create!(timezone: "UTC", github_username: "bucket-status-user")
      EmployeeMonitoringProfile.for_user(user).save!

      create_heartbeat(user, at: Time.utc(2026, 3, 30, 9, 0, 0))
      create_heartbeat(user, at: Time.utc(2026, 3, 30, 9, 19, 0))

      payload = SafariExpert::EmployeeMonitoring::RollupBuilder.new(
        user: user,
        now: Time.current
      ).call

      statuses = payload[:timeline_buckets].map { |bucket| bucket[:status] }.uniq
      assert_includes statuses, "active"
      assert_includes statuses, "idle"
    end
  end

  test "keeps timeline buckets active after scheduled hours when activity continues" do
    travel_to Time.utc(2026, 3, 30, 20, 3, 0) do
      user = User.create!(timezone: "UTC", github_username: "after-hours-bucket-user")
      EmployeeMonitoringProfile.for_user(user).save!

      create_heartbeat(user, at: Time.utc(2026, 3, 30, 20, 0, 0))

      payload = SafariExpert::EmployeeMonitoring::RollupBuilder.new(
        user: user,
        now: Time.current
      ).call

      bucket = payload[:timeline_buckets].find { |entry| entry[:bucket_started_at] == "2026-03-30T20:00:00Z" }

      assert_not_nil bucket
      assert_equal "active", bucket[:status]
      assert_equal false, bucket[:in_window]
      assert_equal "after_end", payload[:status]
      assert payload[:after_hours_active]
    end
  end

  private

  def create_heartbeat(user, at:, category: "coding", language: "Ruby", is_write: true, additions: 0, deletions: 0)
    Heartbeat.create!(
      user: user,
      time: at.to_i,
      category: category,
      source_type: :test_entry,
      project: "internal_ui",
      language: language,
      editor: "VS Code",
      entity: "/app/internal_ui/app/models/employee.rb",
      is_write: is_write,
      line_additions: additions,
      line_deletions: deletions
    )
  end

  def create_commit(user, at:, additions:, deletions:, stats: true, sha: "rollup-commit-#{SecureRandom.hex(4)}")
    raw = {
      "html_url" => "https://github.com/Safari-Expert/internal_ui/commit/#{SecureRandom.hex(4)}",
      "commit" => {
        "committer" => {
          "date" => at.utc.iso8601
        }
      }
    }

    if stats
      raw["stats"] = {
        "additions" => additions,
        "deletions" => deletions
      }
    else
      raw["files"] = [
        {
          "filename" => "app/models/employee.rb",
          "additions" => additions - 8,
          "deletions" => deletions - 2
        },
        {
          "filename" => "app/controllers/employee_controller.rb",
          "additions" => 8,
          "deletions" => 2
        }
      ]
    end

    Commit.create!(
      sha: sha,
      user: user,
      github_raw: raw,
      created_at: at,
      updated_at: at
    )
  end
end
