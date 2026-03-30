require 'rails_helper'

RSpec.describe SafariExpert::EmployeeMonitoring::RollupJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  it "persists daily rollups and interval snapshots for monitored users" do
    travel_to Time.utc(2026, 3, 30, 10, 0, 0) do
      user = User.create!(timezone: "UTC", username: "job-rollup", github_username: "job-rollup")
      Heartbeat.create!(
        user: user,
        time: 3.minutes.ago.to_i,
        category: "coding",
        project: "internal_ui",
        language: "Ruby",
        editor: "VS Code",
        entity: "/app/internal_ui/app/page.tsx",
        is_write: true,
        source_type: :test_entry
      )

      expect { described_class.perform_now }
        .to change { EmployeeMonitoringDailyRollup.where(user: user).count }.by(1)
        .and change { EmployeeMonitoringIntervalSnapshot.where(user: user).count }.by(1)
    end
  end
end
