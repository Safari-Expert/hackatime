class AddChurnAndLanguageBreakdownToEmployeeMonitoringIntervalSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :employee_monitoring_interval_snapshots, :line_additions, :integer, null: false, default: 0
    add_column :employee_monitoring_interval_snapshots, :line_deletions, :integer, null: false, default: 0
    add_column :employee_monitoring_interval_snapshots, :language_breakdown, :jsonb, null: false, default: []
  end
end
