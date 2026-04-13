# frozen_string_literal: true

class ExternalWorkSession < ApplicationRecord
  belongs_to :user

  enum :close_reason, {
    user_clock_out: 0,
    auto_closed_eod: 1
  }, prefix: true

  validates :started_at, presence: true
  validate :ended_at_after_start
  validate :single_open_session, if: :open_session?

  scope :open, -> { where(ended_at: nil) }
  scope :closed, -> { where.not(ended_at: nil) }
  scope :ordered, -> { order(:started_at) }

  def open_session?
    ended_at.nil?
  end

  def duration_seconds(reference_time: Time.current)
    end_time = ended_at || reference_time
    [ end_time.to_i - started_at.to_i, 0 ].max
  end

  private

  def ended_at_after_start
    return if ended_at.blank? || ended_at > started_at

    errors.add(:ended_at, "must be after the start time")
  end

  def single_open_session
    return unless user_id.present?

    existing_open_scope = self.class.open.where(user_id: user_id)
    existing_open_scope = existing_open_scope.where.not(id: id) if persisted?

    errors.add(:base, "An open work session already exists") if existing_open_scope.exists?
  end
end
