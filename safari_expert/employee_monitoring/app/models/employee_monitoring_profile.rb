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
  after_create_commit :ensure_persisted_schedule_days!

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
    persisted_days = persisted_schedule_days
    return persisted_days.map(&:weekday) if persisted_days.any?

    Array(workdays).filter_map { |value|
      integer = Integer(value, exception: false)
      integer if integer&.between?(0, 6)
    }.uniq.sort
  end

  def workday?(local_date)
    schedule_day_for(local_date.wday).present?
  end

  def schedule_days
    persisted_days = persisted_schedule_days
    return persisted_days if persisted_days.any?

    normalized_workdays.map do |weekday|
      EmployeeMonitoringScheduleDay.new(
        user: user,
        weekday: weekday,
        expected_start_minute_local: expected_start_minute_local,
        expected_end_minute_local: expected_end_minute_local
      )
    end
  end

  def schedule_day_for(weekday)
    schedule_days.find { |entry| entry.weekday == weekday.to_i }
  end

  def schedule_window(local_date, user: self.user)
    schedule_day = schedule_day_for(local_date.wday)
    return nil unless schedule_day

    zone = ActiveSupport::TimeZone[effective_timezone(user)] || ActiveSupport::TimeZone["UTC"]
    day_start = zone.local(local_date.year, local_date.month, local_date.day)

    {
      start_at: day_start + schedule_day.expected_start_minute_local.minutes,
      end_at: day_start + schedule_day.expected_end_minute_local.minutes
    }
  end

  def schedule_label(user: self.user)
    rows = schedule_days
    return "No schedule" if rows.empty?

    if rows.map(&:weekday) == DEFAULT_WORKDAYS &&
       rows.map(&:expected_start_minute_local).uniq == [ expected_start_minute_local ] &&
       rows.map(&:expected_end_minute_local).uniq == [ expected_end_minute_local ]
      return "Mon-Fri · #{format_minute(expected_start_minute_local)}-#{format_minute(expected_end_minute_local)}"
    end

    grouped_rows = rows.group_by { |row| [ row.expected_start_minute_local, row.expected_end_minute_local ] }
    if grouped_rows.length == 1
      workday_label = rows.map { |row| DAY_NAMES.fetch(row.weekday) }.join(", ")
      start_minute, end_minute = grouped_rows.keys.first
      return "#{workday_label} · #{format_minute(start_minute)}-#{format_minute(end_minute)}"
    end

    rows.map(&:label).join(" · ")
  end

  def schedule_day_payload
    schedule_days.map do |schedule_day|
      {
        weekday: schedule_day.weekday,
        day_label: DAY_NAMES.fetch(schedule_day.weekday),
        expected_start_minute_local: schedule_day.expected_start_minute_local,
        expected_end_minute_local: schedule_day.expected_end_minute_local,
        expected_seconds: schedule_day.expected_seconds
      }
    end
  end

  def update_schedule_days!(entries)
    transaction do
      user.employee_monitoring_schedule_days.delete_all
      entries.each do |entry|
        user.employee_monitoring_schedule_days.create!(
          weekday: entry.fetch(:weekday),
          expected_start_minute_local: entry.fetch(:expected_start_minute_local),
          expected_end_minute_local: entry.fetch(:expected_end_minute_local)
        )
      end
      sync_legacy_schedule_fields!
    end
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

  def persisted_schedule_days
    return [] unless user&.persisted?

    @persisted_schedule_days ||= user.employee_monitoring_schedule_days.ordered.to_a
  end

  def ensure_persisted_schedule_days!
    return if user.employee_monitoring_schedule_days.exists?

    user.employee_monitoring_schedule_days.insert_all!(
      normalized_workdays.map do |weekday|
        {
          user_id: user.id,
          weekday: weekday,
          expected_start_minute_local: expected_start_minute_local,
          expected_end_minute_local: expected_end_minute_local,
          created_at: Time.current,
          updated_at: Time.current
        }
      end
    )
    @persisted_schedule_days = nil
  end

  def sync_legacy_schedule_fields!
    ordered_days = user.employee_monitoring_schedule_days.ordered.to_a
    return if ordered_days.empty?

    first_day = ordered_days.first
    update!(
      workdays: ordered_days.map(&:weekday),
      expected_start_minute_local: first_day.expected_start_minute_local,
      expected_end_minute_local: first_day.expected_end_minute_local
    )
    @persisted_schedule_days = ordered_days
  end

  def format_minute(total_minutes)
    hours = total_minutes.to_i / 60
    minutes = total_minutes.to_i % 60
    format("%02d:%02d", hours, minutes)
  end
end
