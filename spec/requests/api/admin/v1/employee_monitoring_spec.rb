require "swagger_helper"

RSpec.describe "Api::Admin::V1::EmployeeMonitoring", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:Authorization) { "Bearer dev-admin-api-key-12345" }

  before do
    travel_to Time.utc(2026, 3, 30, 10, 0, 0)
  end

  after do
    travel_back
  end

  let!(:monitored_user) do
    User.create!(timezone: "UTC", username: "monitoring-dev", github_username: "monitoring-dev").tap do |user|
      user.create_employee_monitoring_profile!
      create_heartbeat(user, 4.minutes.ago, line_additions: 12)
      create_heartbeat(user, 2.minutes.ago, line_additions: 8)
      Commit.create!(
        sha: "monitoring-dev-sha",
        user: user,
        github_raw: {
          "stats" => { "additions" => 20, "deletions" => 4 },
          "html_url" => "https://github.com/Safari-Expert/internal_ui/commit/monitoring-dev-sha",
          "commit" => { "committer" => { "date" => 90.minutes.ago.utc.iso8601 } }
        },
        created_at: 90.minutes.ago,
        updated_at: 90.minutes.ago
      )
    end
  end

  path "/api/admin/v1/employee_monitoring/summary" do
    get("Employee monitoring summary") do
      tags "Employee Monitoring"
      security [ AdminToken: [] ]
      produces "application/json"

      response(200, "successful") do
        schema type: :object,
          properties: {
            generated_at: { type: :string, format: :date_time },
            timezone: { type: :string },
            monitored_users: { type: :integer },
            active_in_window: { type: :integer },
            idle_in_window: { type: :integer },
            not_started_yet: { type: :integer },
            ended_early: { type: :integer },
            after_hours_active: { type: :integer },
            monitoring_path: { type: :string },
            users: { type: :array, items: { type: :object } }
          }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["monitored_users"]).to be >= 1
          expect(body["users"].first["id"]).to eq(monitored_user.id)
        end
      end
    end
  end

  path "/api/admin/v1/employee_monitoring/overview" do
    get("Employee monitoring overview") do
      tags "Employee Monitoring"
      security [ AdminToken: [] ]
      produces "application/json"
      parameter name: :status, in: :query, type: :string, required: false

      response(200, "successful") do
        let(:status) { "active" }
        schema type: :object,
          properties: {
            generated_at: { type: :string, format: :date_time },
            timezone: { type: :string },
            summary: { type: :object },
            roster: { type: :array, items: { type: :object } }
          }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["roster"]).not_to be_empty
          expect(body["roster"].first["status"]).to eq("active")
        end
      end
    end
  end

  path "/api/admin/v1/employee_monitoring/users/{id}" do
    parameter name: :id, in: :path, type: :integer

    get("Employee monitoring detail") do
      tags "Employee Monitoring"
      security [ AdminToken: [] ]
      produces "application/json"

      response(200, "successful") do
        let(:id) { monitored_user.id }
        schema type: :object,
          properties: {
            id: { type: :integer },
            display_name: { type: :string },
            schedule: { type: :object },
            current_day: {
              type: :object,
              properties: {
                commit_count: { type: :integer },
                commit_line_additions: { type: :integer },
                commit_line_deletions: { type: :integer },
                timeline_buckets: {
                  type: :array,
                  items: {
                    type: :object,
                    properties: {
                      bucket_started_at: { type: :string, format: :date_time },
                      status: { type: :string },
                      in_window: { type: :boolean },
                      presence_seconds: { type: :integer },
                      coding_seconds: { type: :integer },
                      write_heartbeats_count: { type: :integer },
                      line_additions: { type: :integer },
                      line_deletions: { type: :integer },
                      categories: { type: :object },
                      projects: { type: :array, items: { type: :string } },
                      languages: { type: :array, items: { type: :string } },
                      language_breakdown: {
                        type: :array,
                        items: {
                          type: :object,
                          properties: {
                            language: { type: :string },
                            coding_seconds: { type: :integer },
                            line_additions: { type: :integer },
                            line_deletions: { type: :integer }
                          }
                        }
                      }
                    }
                  }
                }
              }
            },
            trend_14d: { type: :object },
            trend_30d: { type: :object },
            history: { type: :array, items: { type: :object } }
          }

        run_test! do |response|
          body = JSON.parse(response.body)
          expect(body["id"]).to eq(monitored_user.id)
          expect(body["current_day"]["commit_count"]).to eq(1)
        end
      end
    end
  end

  path "/api/admin/v1/employee_monitoring/users/{id}/profile" do
    parameter name: :id, in: :path, type: :integer

    patch("Update employee monitoring profile") do
      tags "Employee Monitoring"
      security [ AdminToken: [] ]
      consumes "application/json"
      produces "application/json"

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          timezone_override: { type: :string },
          expected_start_minute_local: { type: :integer },
          expected_end_minute_local: { type: :integer },
          start_grace_minutes: { type: :integer },
          end_grace_minutes: { type: :integer },
          workdays: { type: :array, items: { type: :integer } }
        }
      }

      response(200, "successful") do
        let(:id) { monitored_user.id }
        let(:payload) do
          {
            timezone_override: "Africa/Nairobi",
            expected_start_minute_local: 510,
            expected_end_minute_local: 1050,
            start_grace_minutes: 5,
            end_grace_minutes: 10,
            workdays: [ 1, 2, 3, 4, 5 ]
          }
        end

        schema type: :object,
          properties: {
            success: { type: :boolean },
            profile: { type: :object }
          }

        run_test! do |_response|
          monitored_user.employee_monitoring_profile.reload
          expect(monitored_user.employee_monitoring_profile.timezone_override).to eq("Africa/Nairobi")
          expect(monitored_user.employee_monitoring_profile.expected_start_minute_local).to eq(510)
        end
      end
    end
  end

  def create_heartbeat(user, at, line_additions: 0, line_deletions: 0)
    Heartbeat.create!(
      user: user,
      time: at.to_i,
      category: "coding",
      project: "internal_ui",
      language: "Ruby",
      editor: "VS Code",
      entity: "/app/internal_ui/app/page.tsx",
      is_write: true,
      line_additions: line_additions,
      line_deletions: line_deletions,
      source_type: :test_entry
    )
  end
end
