# frozen_string_literal: true

module SafariExpert
  module EmployeeMonitoring
    class UserDetailQuery
      def initialize(user:, now: Time.current)
        @user = user
        @now = now
      end

      def call
        current_day = RollupBuilder.new(user: @user, now: @now).call
        profile = EmployeeMonitoringProfile.for_user(@user)
        local_date = Date.iso8601(current_day[:local_date])
        history_rows = EmployeeMonitoringDailyRollup.where(user: @user, local_date: (local_date - 29.days)..(local_date - 1.day))
                                                   .order(local_date: :desc)
                                                   .to_a

        {
          id: @user.id,
          display_name: @user.display_name,
          username: @user.username.presence || @user.github_username.presence,
          avatar_url: @user.avatar_url,
          schedule: {
            monitoring_enabled: profile.monitoring_enabled,
            timezone_override: profile.timezone_override,
            effective_timezone: profile.effective_timezone(@user),
            expected_start_minute_local: profile.expected_start_minute_local,
            expected_end_minute_local: profile.expected_end_minute_local,
            workdays: profile.normalized_workdays,
            start_grace_minutes: profile.start_grace_minutes,
            end_grace_minutes: profile.end_grace_minutes,
            label: profile.schedule_label(user: @user)
          },
          current_day: current_day,
          trend_14d: trend_payload(history_rows.first(14), current_day),
          trend_30d: trend_payload(history_rows.first(30), current_day),
          history: history_payload(history_rows, current_day)
        }
      end

      private

      def trend_payload(history_rows, current_day)
        rows = [ current_day_history_row(current_day) ] + history_rows.map { |row| history_row_from_record(row) }
        rows = rows.first(history_rows.length + 1)

        {
          days_sampled: rows.length,
          on_time_days: rows.count { |row| row[:attendance_signal] == "on_track" || row[:attendance_signal] == "completed" },
          late_start_days: rows.count { |row| row[:attendance_signal] == "late_start" },
          absent_days: rows.count { |row| row[:attendance_signal] == "not_started" },
          ended_early_days: rows.count { |row| row[:attendance_signal] == "ended_early" },
          average_coverage: if rows.any?
                              (rows.sum { |row| row[:coverage_percent].to_f } / rows.length).round(2)
                            else
                              0.0
                            end,
          coding_hours: (rows.sum { |row| row[:coding_seconds].to_i } / 3600.0).round(2)
        }
      end

      def history_payload(history_rows, current_day)
        ([ current_day_history_row(current_day) ] + history_rows.map { |row| history_row_from_record(row) }).sort_by { |row| row[:local_date] }.reverse
      end

      def current_day_history_row(current_day)
        {
          local_date: current_day[:local_date],
          attendance_signal: current_day[:attendance_signal],
          coverage_percent: current_day[:coverage_percent],
          coding_seconds: current_day[:coding_seconds],
          commit_count: current_day[:commit_count],
          after_hours_active: current_day[:after_hours_active]
        }
      end

      def history_row_from_record(row)
        {
          local_date: row.local_date.iso8601,
          attendance_signal: row.attendance_signal,
          coverage_percent: row.coverage_percent.to_f,
          coding_seconds: row.coding_seconds.to_i,
          commit_count: row.commit_count.to_i,
          after_hours_active: row.after_hours_active
        }
      end
    end
  end
end
