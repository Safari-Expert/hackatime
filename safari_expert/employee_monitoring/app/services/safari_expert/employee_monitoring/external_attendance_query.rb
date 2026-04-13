# frozen_string_literal: true

module SafariExpert
  module EmployeeMonitoring
    class ExternalAttendanceQuery
      def initialize(user:, now: Time.current)
        @user = user
        @now = now
        @profile = EmployeeMonitoringProfile.for_user(@user)
        @timezone = @profile.effective_timezone(@user)
        @zone = ActiveSupport::TimeZone[@timezone] || ActiveSupport::TimeZone["UTC"]
        @sessions = @user.external_work_sessions.ordered.to_a
      end

      def call
        raise ArgumentError, "user must be an external collaborator" unless @user.account_kind_external?

        {
          id: @user.id,
          account_kind: @user.account_kind,
          display_name: @user.display_name,
          username: @user.username,
          avatar_url: @user.avatar_url,
          schedule: schedule_payload,
          attendance: {
            state: open_session.present? ? "clocked_in" : "clocked_out",
            open_session_started_at: open_session&.started_at&.iso8601,
            today_seconds: seconds_for_period(day_range_for(local_today)),
            week_seconds: seconds_for_period(range_for_dates(current_week_start, current_week_end)),
            month_seconds: seconds_for_period(range_for_dates(current_month_start, current_month_end)),
            week_rows: week_rows
          }
        }
      end

      def roster_row
        today_row = day_row(local_today)
        expected_window = @profile.schedule_window(local_today, user: @user)
        expected_seconds = today_row[:expected_seconds].to_i
        actual_seconds = today_row[:actual_seconds].to_i
        after_hours_active = open_session.present? && expected_window.present? && !reference_now.between?(expected_window[:start_at], expected_window[:end_at])
        not_started_yet = expected_window.present? &&
          reference_now > (expected_window[:start_at] + @profile.start_grace_minutes.minutes) &&
          today_row[:actual_start_at].blank?
        ended_early = expected_window.present? &&
          reference_now > expected_window[:end_at] &&
          today_row[:actual_seconds].positive? &&
          actual_seconds + @profile.end_grace_minutes.minutes < expected_seconds &&
          open_session.blank?

        {
          id: @user.id,
          account_kind: @user.account_kind,
          display_name: @user.display_name,
          username: @user.username,
          avatar_url: @user.avatar_url,
          timezone: @timezone,
          local_date: local_today.iso8601,
          expected_start_at: today_row[:expected_start_at],
          expected_end_at: today_row[:expected_end_at],
          schedule_label: @profile.schedule_label(user: @user),
          first_seen_at: today_row[:actual_start_at],
          last_seen_at: today_row[:actual_end_at],
          start_delta_minutes: delta_minutes(today_row[:actual_start_at], today_row[:expected_start_at]),
          end_delta_minutes: delta_minutes(today_row[:actual_end_at], today_row[:expected_end_at]),
          status: roster_status(expected_window),
          not_started_yet: not_started_yet,
          ended_early: ended_early,
          after_hours_active: after_hours_active,
          presence_seconds: actual_seconds,
          coding_seconds: actual_seconds,
          write_heartbeats_count: 0,
          unique_files_count: 0,
          unique_projects_count: 0,
          unique_languages_count: 0,
          session_count: today_row[:session_count],
          gap_count: 0,
          coverage_percent: coverage_percent(actual_seconds, expected_seconds),
          commit_count: 0,
          commit_line_additions: 0,
          commit_line_deletions: 0,
          top_project: nil,
          top_language: nil,
          top_editor: nil,
          attendance_signal: attendance_signal(today_row),
          activity_signal: actual_seconds.positive? ? "steady" : "quiet",
          delivery_signal: actual_seconds.positive? ? "tracked" : "quiet",
          ai_assisted_output_level: "not_applicable",
          ai_assisted_output_ratio: 0.0,
          ai_assisted_output_confidence: 0.0,
          ai_assisted_output_reason: "Attendance-only account"
        }
      end

      private

      def schedule_payload
        {
          monitoring_enabled: @profile.monitoring_enabled,
          timezone_override: @profile.timezone_override,
          effective_timezone: @timezone,
          expected_start_minute_local: @profile.expected_start_minute_local,
          expected_end_minute_local: @profile.expected_end_minute_local,
          workdays: @profile.normalized_workdays,
          schedule_days: @profile.schedule_editor_payload,
          start_grace_minutes: @profile.start_grace_minutes,
          end_grace_minutes: @profile.end_grace_minutes,
          label: @profile.schedule_label(user: @user)
        }
      end

      def week_rows
        (current_week_start..current_week_end).map { |date| day_row(date) }
      end

      def day_row(local_date)
        scheduled_window = @profile.schedule_window(local_date, user: @user)
        day_range = day_range_for(local_date)
        sessions = sessions_for_range(day_range)
        expected_seconds = scheduled_window.present? ? @profile.schedule_day_for(local_date.wday)&.expected_seconds.to_i : 0
        actual_seconds = sessions.sum { |session| overlap_seconds(session, day_range) }
        actual_start_at = sessions.map { |session| [ session.started_at, day_range[:start_at] ].max }.min
        actual_end_at =
          if sessions.any?(&:open_session?)
            nil
          else
            sessions.filter_map { |session|
              next if session.ended_at.blank?

              [ session.ended_at, day_range[:end_at] ].min
            }.max
          end
        auto_closed = sessions.any?(&:close_reason_auto_closed_eod?)

        {
          local_date: local_date.iso8601,
          weekday_label: EmployeeMonitoringProfile::DAY_NAMES.fetch(local_date.wday),
          scheduled: scheduled_window.present?,
          expected_start_at: scheduled_window&.dig(:start_at)&.iso8601,
          expected_end_at: scheduled_window&.dig(:end_at)&.iso8601,
          expected_seconds: expected_seconds,
          actual_start_at: actual_start_at&.iso8601,
          actual_end_at: actual_end_at&.iso8601,
          actual_seconds: actual_seconds,
          start_status: start_status(scheduled_window, actual_start_at),
          hours_status: hours_status(local_date, expected_seconds, actual_seconds, auto_closed: auto_closed),
          auto_closed: auto_closed,
          session_count: sessions.length
        }
      end

      def start_status(scheduled_window, actual_start_at)
        return "not_scheduled" unless scheduled_window
        return "not_started" unless actual_start_at

        actual_start_at > (scheduled_window[:start_at] + @profile.start_grace_minutes.minutes) ? "late" : "on_time"
      end

      def hours_status(local_date, expected_seconds, actual_seconds, auto_closed:)
        return "not_scheduled" if expected_seconds <= 0
        return "not_clocked_out" if auto_closed
        return "met" if actual_seconds >= expected_seconds

        if local_date == local_today && open_session.present?
          "in_progress"
        else
          "short"
        end
      end

      def attendance_signal(today_row)
        return "not_started" if today_row[:start_status] == "not_started"
        return "late_start" if today_row[:start_status] == "late"
        return "completed" if today_row[:hours_status] == "met"

        "on_track"
      end

      def roster_status(expected_window)
        return "active" if open_session.present?
        return "inactive" unless expected_window
        return "before_start" if reference_now < expected_window[:start_at]
        return "after_end" if reference_now > expected_window[:end_at]

        "inactive"
      end

      def coverage_percent(actual_seconds, expected_seconds)
        return 0.0 if expected_seconds <= 0

        [ ((actual_seconds.to_f / expected_seconds) * 100.0), 100.0 ].min.round(2)
      end

      def delta_minutes(actual_at, expected_at)
        return nil if actual_at.blank? || expected_at.blank?

        ((Time.iso8601(actual_at) - Time.iso8601(expected_at)) / 60.0).round
      end

      def seconds_for_period(range)
        @sessions.sum { |session| overlap_seconds(session, range) }
      end

      def overlap_seconds(session, range)
        session_end = session.ended_at || @now
        overlap_started_at = [ session.started_at, range[:start_at] ].max
        overlap_ended_at = [ session_end, range[:end_at] ].min
        return 0 if overlap_ended_at <= overlap_started_at

        (overlap_ended_at - overlap_started_at).to_i
      end

      def sessions_for_range(range)
        @sessions.select do |session|
          session_end = session.ended_at || @now
          session.started_at < range[:end_at] && session_end > range[:start_at]
        end
      end

      def day_range_for(local_date)
        range_for_dates(local_date, local_date)
      end

      def range_for_dates(start_date, end_date)
        {
          start_at: @zone.local(start_date.year, start_date.month, start_date.day),
          end_at: @zone.local(end_date.year, end_date.month, end_date.day) + 1.day
        }
      end

      def reference_now
        @reference_now ||= @now.in_time_zone(@zone)
      end

      def local_today
        reference_now.to_date
      end

      def current_week_start
        local_today.beginning_of_week(:monday)
      end

      def current_week_end
        current_week_start + 6.days
      end

      def current_month_start
        local_today.beginning_of_month
      end

      def current_month_end
        local_today.end_of_month
      end

      def open_session
        @open_session ||= @sessions.find(&:open_session?)
      end
    end
  end
end
