# frozen_string_literal: true

module SafariExpert
  module EmployeeMonitoring
    module Constants
      ACTIVE_WINDOW_MINUTES = 5
      IDLE_WINDOW_MINUTES = 15
      SESSION_TIMEOUT_MINUTES = 10
      BUCKET_SIZE_MINUTES = 5
      MAX_HEARTBEAT_GAP_SECONDS = 120

      STATUSES = %w[active idle inactive before_start after_end].freeze
      AI_SIGNAL_LEVELS = %w[insufficient low moderate high].freeze

      ATTENDANCE_SIGNALS = %w[in_progress on_track late_start not_started ended_early completed].freeze
      ACTIVITY_SIGNALS = %w[low medium high].freeze
      DELIVERY_SIGNALS = %w[quiet steady strong].freeze
    end
  end
end
