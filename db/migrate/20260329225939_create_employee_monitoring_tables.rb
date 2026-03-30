class CreateEmployeeMonitoringTables < ActiveRecord::Migration[8.1]
  def change
    create_table :employee_monitoring_profiles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.boolean :monitoring_enabled, null: false, default: true
      t.string :timezone_override
      t.integer :expected_start_minute_local, null: false, default: 540
      t.integer :expected_end_minute_local, null: false, default: 1020
      t.integer :workdays, array: true, null: false, default: [ 1, 2, 3, 4, 5 ]
      t.integer :start_grace_minutes, null: false, default: 15
      t.integer :end_grace_minutes, null: false, default: 15
      t.timestamps
    end

    create_table :employee_monitoring_daily_rollups do |t|
      t.references :user, null: false, foreign_key: true
      t.date :local_date, null: false
      t.string :timezone, null: false
      t.datetime :scheduled_start_at
      t.datetime :scheduled_end_at
      t.datetime :first_seen_at
      t.datetime :last_seen_at
      t.string :status, null: false, default: "inactive"
      t.boolean :not_started_yet, null: false, default: false
      t.boolean :ended_early, null: false, default: false
      t.boolean :after_hours_active, null: false, default: false
      t.integer :presence_seconds, null: false, default: 0
      t.integer :coding_seconds, null: false, default: 0
      t.integer :write_heartbeats_count, null: false, default: 0
      t.integer :unique_files_count, null: false, default: 0
      t.integer :unique_projects_count, null: false, default: 0
      t.integer :unique_languages_count, null: false, default: 0
      t.integer :session_count, null: false, default: 0
      t.integer :gap_count, null: false, default: 0
      t.integer :active_bucket_count, null: false, default: 0
      t.integer :idle_bucket_count, null: false, default: 0
      t.decimal :coverage_percent, precision: 5, scale: 2, null: false, default: 0
      t.integer :commit_count, null: false, default: 0
      t.integer :commit_line_additions, null: false, default: 0
      t.integer :commit_line_deletions, null: false, default: 0
      t.string :attendance_signal, null: false, default: "in_progress"
      t.string :activity_signal, null: false, default: "low"
      t.string :delivery_signal, null: false, default: "quiet"
      t.string :ai_assisted_output_level, null: false, default: "insufficient"
      t.decimal :ai_assisted_output_ratio, precision: 6, scale: 2, null: false, default: 0
      t.decimal :ai_assisted_output_confidence, precision: 4, scale: 2, null: false, default: 0
      t.text :ai_assisted_output_reason
      t.jsonb :project_mix, null: false, default: []
      t.jsonb :language_mix, null: false, default: []
      t.jsonb :editor_mix, null: false, default: []
      t.jsonb :commit_markers, null: false, default: []
      t.jsonb :session_spans, null: false, default: []
      t.jsonb :timeline_buckets, null: false, default: []
      t.timestamps
    end
    add_index :employee_monitoring_daily_rollups, [ :user_id, :local_date ], unique: true, name: "index_employee_monitoring_rollups_on_user_and_local_date"

    create_table :employee_monitoring_interval_snapshots do |t|
      t.references :user, null: false, foreign_key: true
      t.datetime :bucket_started_at, null: false
      t.date :local_date, null: false
      t.string :timezone, null: false
      t.string :status, null: false, default: "inactive"
      t.boolean :in_window, null: false, default: false
      t.integer :presence_seconds, null: false, default: 0
      t.integer :coding_seconds, null: false, default: 0
      t.integer :write_heartbeats_count, null: false, default: 0
      t.jsonb :categories, null: false, default: {}
      t.jsonb :projects, null: false, default: []
      t.jsonb :languages, null: false, default: []
      t.timestamps
    end
    add_index :employee_monitoring_interval_snapshots, [ :user_id, :bucket_started_at ], unique: true, name: "index_employee_monitoring_snapshots_on_user_and_bucket"
  end
end
