# frozen_string_literal: true

class EmployeeMonitoringIntervalSnapshot < ApplicationRecord
  belongs_to :user

  validates :bucket_started_at, presence: true, uniqueness: { scope: :user_id }
  validates :local_date, presence: true
  validates :timezone, presence: true
  validates :status, inclusion: { in: SafariExpert::EmployeeMonitoring::Constants::STATUSES }
end
