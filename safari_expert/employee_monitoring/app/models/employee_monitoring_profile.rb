# frozen_string_literal: true

class EmployeeMonitoringProfile < ApplicationRecord
  DEFAULT_WORKDAYS = [ 1, 2, 3, 4, 5 ].freeze
  DAY_NAMES = {
    0 => "Sun",
    1 => "Mon",
    2 => "Tue",
    3 => "Wed",
    4 => "Thu",
    5 => "Fri",
    6 => "Sat"
  }.freeze

  attribute :monitoring_enabled, default: true
  attribute :expected_start_minute_local, default: 9.hours.to_i / 60
  attribute :expected_end_minute_local, default: 17.hours.to_i / 60
  attribute :workdays, default: -> { DEFAULT_WORKDAYS.dup }
  attribute :start_grace_minutes, default: 15
  attribute :end_grace_minutes, default: 15

  belongs_to :user

  before_validation :normalize_profile_values

  validates :user_id, uniqueness: true
  validates :timezone_override, inclusion: { in: TZInfo::Timezone.all_identifiers }, allow_blank: true
  validates :expected_start_minute_local, :expected_end_minute_local, inclusion: { in: 0..1439 }
  validates :start_grace_minutes, :end_grace_minutes, inclusion: { in: 0..240 }
  validates :workdays, presence: true
  validate :expected_end_after_start
  validate :workdays_are_supported

  def self.for_user(user)
    user.employee_monitoring_profile || user.build_employee_monitoring_profile
  end

  def effective_timezone(fallback_user = user)
    timezone_override.presence || fallback_user&.timezone.presence || "UTC"
  end

  def normalized_workdays
    Array(workdays).filter_map { |value|
      integer = Integer(value, exception: false)
      integer if integer&.between?(0, 6)
    }.uniq.sort
  end

  def workday?(local_date)
    normalized_workdays.include?(local_date.wday)
  end

  def schedule_window(local_date, user: self.user)
    return nil unless workday?(local_date)

    zone = ActiveSupport::TimeZone[effective_timezone(user)] || ActiveSupport::TimeZone["UTC"]
    day_start = zone.local(local_date.year, local_date.month, local_date.day)

    {
      start_at: day_start + expected_start_minute_local.minutes,
      end_at: day_start + expected_end_minute_local.minutes
    }
  end

  def schedule_label(user: self.user)
    workday_label =
      if normalized_workdays.empty?
        "No schedule"
      elsif normalized_workdays == DEFAULT_WORKDAYS
        "Mon-Fri"
      else
        normalized_workdays.map { |day| DAY_NAMES.fetch(day) }.join(", ")
      end

    "#{workday_label} · #{format_minute(expected_start_minute_local)}-#{format_minute(expected_end_minute_local)}"
  end

  private

  def normalize_profile_values
    self.timezone_override = timezone_override.presence
    self.monitoring_enabled = true if monitoring_enabled.nil?
    self.expected_start_minute_local = expected_start_minute_local.to_i
    self.expected_end_minute_local = expected_end_minute_local.to_i
    self.start_grace_minutes = start_grace_minutes.to_i
    self.end_grace_minutes = end_grace_minutes.to_i
    self.workdays = normalized_workdays.presence || DEFAULT_WORKDAYS
  end

  def expected_end_after_start
    return if expected_end_minute_local.to_i > expected_start_minute_local.to_i

    errors.add(:expected_end_minute_local, "must be after the start minute")
  end

  def workdays_are_supported
    return if normalized_workdays.length == Array(workdays).compact.length

    errors.add(:workdays, "must only include values from 0 to 6")
  end

  def format_minute(total_minutes)
    hours = total_minutes.to_i / 60
    minutes = total_minutes.to_i % 60
    format("%02d:%02d", hours, minutes)
  end
end
