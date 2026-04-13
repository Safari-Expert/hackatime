class AddExternalAttendanceMode < ActiveRecord::Migration[8.1]
  class MigrationUser < ApplicationRecord
    self.table_name = "users"
  end

  class MigrationProfile < ApplicationRecord
    self.table_name = "employee_monitoring_profiles"
  end

  class MigrationScheduleDay < ApplicationRecord
    self.table_name = "employee_monitoring_schedule_days"
  end

  def up
    add_column :users, :account_kind, :integer, null: false, default: 0
    add_column :users, :password_digest, :string

    create_table :employee_monitoring_schedule_days do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :weekday, null: false
      t.integer :expected_start_minute_local, null: false
      t.integer :expected_end_minute_local, null: false
      t.timestamps
    end
    add_index :employee_monitoring_schedule_days, [ :user_id, :weekday ], unique: true, name: "index_employee_monitoring_schedule_days_on_user_and_weekday"

    create_table :external_work_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.integer :close_reason
      t.timestamps
    end
    add_index :external_work_sessions, [ :user_id, :started_at ], name: "index_external_work_sessions_on_user_and_started_at"
    add_index :external_work_sessions, :user_id, unique: true, where: "ended_at IS NULL", name: "index_external_work_sessions_on_open_user"

    backfill_schedule_days!
  end

  def down
    remove_index :external_work_sessions, name: "index_external_work_sessions_on_open_user"
    remove_index :external_work_sessions, name: "index_external_work_sessions_on_user_and_started_at"
    drop_table :external_work_sessions

    remove_index :employee_monitoring_schedule_days, name: "index_employee_monitoring_schedule_days_on_user_and_weekday"
    drop_table :employee_monitoring_schedule_days

    remove_column :users, :password_digest
    remove_column :users, :account_kind
  end

  private

  def backfill_schedule_days!
    MigrationUser.reset_column_information
    MigrationProfile.reset_column_information
    MigrationScheduleDay.reset_column_information

    MigrationProfile.find_each do |profile|
      workdays = Array(profile.workdays).presence || [ 1, 2, 3, 4, 5 ]

      workdays.each do |weekday|
        MigrationScheduleDay.find_or_create_by!(user_id: profile.user_id, weekday: weekday) do |schedule_day|
          schedule_day.expected_start_minute_local = profile.expected_start_minute_local
          schedule_day.expected_end_minute_local = profile.expected_end_minute_local
        end
      end
    end
  end
end
