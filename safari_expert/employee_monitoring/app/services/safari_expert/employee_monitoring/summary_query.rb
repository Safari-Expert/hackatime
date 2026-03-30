# frozen_string_literal: true

module SafariExpert
  module EmployeeMonitoring
    class SummaryQuery
      def initialize(now: Time.current)
        @now = now
      end

      def call
        overview = OverviewQuery.new(now: @now).call

        {
          generated_at: overview[:generated_at],
          timezone: overview[:timezone],
          monitored_users: overview.dig(:summary, :monitored_users).to_i,
          active_in_window: overview.dig(:summary, :active_in_window).to_i,
          idle_in_window: overview.dig(:summary, :idle_in_window).to_i,
          not_started_yet: overview.dig(:summary, :not_started_yet).to_i,
          ended_early: overview.dig(:summary, :ended_early).to_i,
          after_hours_active: overview.dig(:summary, :after_hours_active).to_i,
          users: overview[:roster].first(6)
        }
      end
    end
  end
end
