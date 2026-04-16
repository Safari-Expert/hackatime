require "application_system_test_case"

class Admin::EmployeeMonitoringTest < ApplicationSystemTestCase
  test "viewer access stays read only" do
    travel_to monitoring_reference_time do
      viewer = User.create!(timezone: "UTC", admin_level: "viewer", github_username: "viewer-monitoring")
      monitored = create_monitored_user("readonly-dev")

      sign_in_as(viewer)
      visit admin_employee_monitoring_path(user_id: monitored.id)

      assert_text "Employee Monitoring"
      assert_text monitored.display_name
      assert_text "This view is read-only for viewers."
      assert_no_button "Save schedule"
    end
  end

  test "admins can access the schedule editor" do
    travel_to monitoring_reference_time do
      admin = User.create!(timezone: "UTC", admin_level: "admin", github_username: "admin-monitoring")
      monitored = create_monitored_user("editable-dev")

      sign_in_as(admin)
      visit admin_employee_monitoring_path(user_id: monitored.id)

      assert_text monitored.display_name
      assert_text "EDIT SCHEDULE"
      assert_field "Timezone override", with: ""
      assert_selector "input[type='time']", minimum: 10
      assert_button "Save schedule"
    end
  end

  test "admins see the simplified attendance panel for external users" do
    travel_to monitoring_reference_time do
      admin = User.create!(timezone: "UTC", admin_level: "admin", github_username: "admin-ext")
      external_user = User.create!(
        timezone: "UTC",
        account_kind: :external,
        display_name_override: "External Worker",
        username: "ext-work-sys",
        password: "supersecure123"
      )
      external_user.create_employee_monitoring_profile!
      external_user.external_work_sessions.create!(
        started_at: Time.utc(2026, 4, 13, 9, 0, 0),
        ended_at: Time.utc(2026, 4, 13, 12, 0, 0),
        close_reason: :user_clock_out
      )

      sign_in_as(admin)
      visit admin_employee_monitoring_path(user_id: external_user.id)

      assert_text "SELECTED EXTERNAL COLLABORATOR"
      assert_text "Current week"
      assert_text "External Worker"
      assert_text "EXTERNAL"
      assert_text "Today's session timeline"
      assert_selector "[data-external-session-timeline][data-session-count='1']"
      assert_no_text "5-minute activity chart"
    end
  end

  test "activity chart renders today's bucket data and aligned panels" do
    travel_to monitoring_reference_time do
      admin = User.create!(timezone: "UTC", admin_level: "admin", github_username: "admin-monitoring-2")
      monitored = create_monitored_user("active-dev")

      sign_in_as(admin)
      visit admin_employee_monitoring_path(user_id: monitored.id)

      assert_no_text "Search developers"
      assert_no_text "Apply filters"
      assert_no_text "Focused bucket"
      assert_no_text "Session spans"
      assert_no_text "Monitored users"
      assert_no_selector ".summary-card"

      within(:xpath, "//h3[contains(., '5-minute activity chart')]/ancestor::div[contains(@class, 'rounded-2xl')][1]") do
        assert_text "Coding time by language per 5-minute bucket"
        assert_text "Line churn by 5-minute bucket"
        assert_text "Active < 5m · idle < 15m"
        assert_text "5 MIN BUCKETS"
        assert_no_text "PRESENCE STATUS"
        assert_no_text "Before start"
        assert_no_text "After end"
        assert_no_selector ".activity-chart__controls"
        assert_no_selector ".activity-chart__legend-groups"
        assert_text "+20 / -5"
        assert_text "2m"
        assert_text "Ruby"
        assert_text "Go"

        shared_axis = find(".market-chart__x-axis")
        shared_bucket_count = shared_axis["data-bucket-count"].to_i

        assert_equal shared_bucket_count, all(".market-chart__tick-slot").count
        assert_equal shared_bucket_count, find("[data-track='languages']")["data-bucket-count"].to_i
        assert_equal shared_bucket_count, find("[data-track='churn']")["data-bucket-count"].to_i
        assert_equal shared_bucket_count, find("[data-track='status']")["data-bucket-count"].to_i
        assert_equal shared_bucket_count, all("[data-track='status'] .market-chart__slot").count
        assert_operator dom_count(".market-chart__track--languages .market-chart__rect"), :>=, 2
        assert_operator dom_count(".market-chart__track--churn .market-chart__rect"), :>=, 2
        assert_operator dom_count(".market-chart__track--status .status-rail__rect"), :>=, 1
        refute_includes bucket_statuses(".market-chart__track--status"), "before_start"
        refute_includes bucket_statuses(".market-chart__track--status"), "after_end"

        assert_equal 1, all(".market-chart__track--languages .market-chart__slot--active").count
        assert_equal 1, all(".market-chart__track--churn .market-chart__slot--active").count
        assert_equal 1, all(".market-chart__track--status .market-chart__slot--active").count

        bucket_started_at = monitoring_reference_time.change(min: 30, sec: 0).iso8601
        assert_equal [ "Go", "Ruby" ], bucket_series_keys(".market-chart__track--languages", bucket_started_at)
        assert_equal [ "line_additions", "line_deletions" ], bucket_series_keys(".market-chart__track--churn", bucket_started_at)
        assert_operator bucket_rect_heights(".market-chart__track--languages", bucket_started_at).max, :>, 20
        assert_operator bucket_rect_heights(".market-chart__track--churn", bucket_started_at).max, :>, 10
      end

      within(:xpath, "//h3[contains(., 'Delivery detail')]/ancestor::div[contains(@class, 'rounded-2xl')][1]") do
        commits_row = find("span", text: "Commits").find(:xpath, "..")
        commit_additions_row = find("span", text: "Commit additions").find(:xpath, "..")
        commit_deletions_row = find("span", text: "Commit deletions").find(:xpath, "..")
        assert_equal "1", commits_row.find("strong").text
        assert_equal "20", commit_additions_row.find("strong").text
        assert_equal "5", commit_deletions_row.find("strong").text
      end
    end
  end

  private

  def monitoring_reference_time
    Time.utc(2026, 4, 13, 14, 33, 0)
  end

  def create_monitored_user(github_username)
    user = User.create!(timezone: "UTC", github_username: github_username)
    user.create_employee_monitoring_profile!

    bucket_started_at = monitoring_reference_time.change(min: 30, sec: 0)

    Heartbeat.create!(
      user: user,
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
      user: user,
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
    create_commit(user, at: bucket_started_at + 90.seconds)

    user
  end

  def bucket_series_keys(track_selector, bucket_started_at)
    page.evaluate_script(<<~JS)
      Array.from(
        document.querySelectorAll("#{track_selector} [data-bucket-started-at='#{bucket_started_at}'][data-series-key]")
      ).map((element) => element.getAttribute("data-series-key")).sort()
    JS
  end

  def bucket_rect_heights(track_selector, bucket_started_at)
    page.evaluate_script(<<~JS)
      Array.from(
        document.querySelectorAll("#{track_selector} [data-bucket-started-at='#{bucket_started_at}'][data-series-key]")
      ).map((element) => Number(element.getAttribute("height")))
    JS
  end

  def bucket_statuses(track_selector)
    page.evaluate_script(<<~JS)
      Array.from(
        document.querySelectorAll("#{track_selector} [data-status]")
      ).map((element) => element.getAttribute("data-status"))
    JS
  end

  def dom_count(selector)
    page.evaluate_script("document.querySelectorAll(#{selector.to_json}).length")
  end

  def create_commit(user, at:)
    Commit.create!(
      sha: "system-test-sha-#{SecureRandom.hex(4)}",
      user: user,
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
        "html_url" => "https://github.com/Safari-Expert/hackatime/commit/system-test",
        "commit" => {
          "committer" => {
            "date" => at.utc.iso8601
          }
        }
      },
      created_at: at,
      updated_at: at
    )
  end
end
