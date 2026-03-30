# frozen_string_literal: true

class EmployeeMonitoringDailyRollup < ApplicationRecord
  belongs_to :user

  validates :local_date, presence: true, uniqueness: { scope: :user_id }
  validates :timezone, presence: true
  validates :status, inclusion: { in: SafariExpert::EmployeeMonitoring::Constants::STATUSES }
  validates :ai_assisted_output_level, inclusion: { in: SafariExpert::EmployeeMonitoring::Constants::AI_SIGNAL_LEVELS }
end
