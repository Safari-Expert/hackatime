# frozen_string_literal: true

module SafariExpert
  module EmployeeMonitoring
    class ExternalAttendanceManager
      class Error < StandardError; end

      def initialize(user:, now: Time.current)
        @user = user
        @now = now
      end

      def clock_in!
        raise Error, "Only external collaborators can clock in." unless @user.account_kind_external?
        raise Error, "You are already clocked in." if open_session

        @user.external_work_sessions.create!(started_at: @now)
      end

      def clock_out!
        raise Error, "Only external collaborators can clock out." unless @user.account_kind_external?

        session = open_session
        raise Error, "You are not currently clocked in." unless session

        session.update!(ended_at: @now, close_reason: :user_clock_out)
        session
      end

      private

      def open_session
        @open_session ||= @user.external_work_sessions.open.order(started_at: :desc).first
      end
    end
  end
end
