# frozen_string_literal: true

module SafariExpert
  module EmployeeMonitoring
    class OverviewQuery
      def initialize(now: Time.current, search: nil, status: nil)
        @now = now
        @search = search
        @status = status.to_s.presence
      end

      def call
        users = UserScope.new(search: @search).relation.to_a
        roster = users.map do |user|
          if user.account_kind_external?
            ExternalAttendanceQuery.new(user: user, now: @now).roster_row
          else
            RollupBuilder.new(user: user, now: @now).call
          end
        end
        filtered_roster = filter_roster(roster)

        {
          generated_at: @now.iso8601,
          timezone: Time.zone.name,
          filters: {
            search: @search.to_s,
            status: @status.to_s
          },
          summary: {
            monitored_users: roster.length,
            active_in_window: roster.count { |row| row[:status] == "active" && !row[:after_hours_active] },
            idle_in_window: roster.count { |row| row[:status] == "idle" && !row[:after_hours_active] },
            not_started_yet: roster.count { |row| row[:not_started_yet] },
            ended_early: roster.count { |row| row[:ended_early] },
            after_hours_active: roster.count { |row| row[:after_hours_active] }
          },
          roster: filtered_roster.sort_by { |row| roster_sort_key(row) }
        }
      end

      private

      def filter_roster(roster)
        return roster unless @status

        roster.select do |row|
          case @status
          when "not_started_yet"
            row[:not_started_yet]
          when "ended_early"
            row[:ended_early]
          when "after_hours"
            row[:after_hours_active]
          else
            row[:status] == @status
          end
        end
      end

      def roster_sort_key(row)
        [
          status_rank(row[:status], row[:after_hours_active]),
          row[:not_started_yet] ? 0 : 1,
          -(row[:coverage_percent].to_f),
          row[:display_name]
        ]
      end

      def status_rank(status, after_hours_active)
        return 0 if after_hours_active

        {
          "active" => 1,
          "idle" => 2,
          "inactive" => 3,
          "before_start" => 4,
          "after_end" => 5
        }.fetch(status, 9)
      end
    end
  end
end
