# frozen_string_literal: true

class EmployeeMonitoringScheduleDay < ApplicationRecord
  DAY_NAMES = {
    0 => "Sun",
    1 => "Mon",
    2 => "Tue",
    3 => "Wed",
    4 => "Thu",
    5 => "Fri",
    6 => "Sat"
  }.freeze

  belongs_to :user

  validates :weekday, inclusion: { in: 0..6 }
  validates :expected_start_minute_local, :expected_end_minute_local, inclusion: { in: 0..1439 }
  validates :weekday, uniqueness: { scope: :user_id }
  validate :expected_end_after_start

  scope :ordered, -> { order(:weekday) }

  def label
    "#{DAY_NAMES.fetch(weekday)} #{format_minute(expected_start_minute_local)}-#{format_minute(expected_end_minute_local)}"
  end

  def expected_seconds
    (expected_end_minute_local - expected_start_minute_local).minutes.to_i
  end

  private

  def expected_end_after_start
    return if expected_end_minute_local.to_i > expected_start_minute_local.to_i

    errors.add(:expected_end_minute_local, "must be after the start minute")
  end

  def format_minute(total_minutes)
    hours = total_minutes.to_i / 60
    minutes = total_minutes.to_i % 60
    format("%02d:%02d", hours, minutes)
  end
end
