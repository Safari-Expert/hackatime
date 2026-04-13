# frozen_string_literal: true

module SafariExpert
  module EmployeeMonitoring
    class ProfileUpdater
      BOOLEAN = ActiveModel::Type::Boolean.new

      def initialize(user:, params:)
        @user = user
        @params =
          if params.respond_to?(:to_h)
            params.to_h.with_indifferent_access
          else
            ActiveSupport::HashWithIndifferentAccess.new
          end
      end

      def call
        profile = EmployeeMonitoringProfile.for_user(@user)
        schedule_days = parsed_schedule_days

        if !schedule_days.nil? && schedule_days.empty?
          profile.errors.add(:base, "At least one scheduled day is required")
          raise ActiveRecord::RecordInvalid, profile
        end

        profile.assign_attributes(profile_attributes(schedule_days))

        profile.transaction do
          profile.save!
          profile.update_schedule_days!(schedule_days) if schedule_days
        end

        profile
      end

      private

      def profile_attributes(schedule_days)
        attributes = {}
        attributes[:monitoring_enabled] = BOOLEAN.cast(@params[:monitoring_enabled]) if @params.key?(:monitoring_enabled)
        attributes[:timezone_override] = @params[:timezone_override].presence if @params.key?(:timezone_override)
        if schedule_days.present?
          first_day = schedule_days.first
          attributes[:expected_start_minute_local] = first_day.fetch(:expected_start_minute_local)
          attributes[:expected_end_minute_local] = first_day.fetch(:expected_end_minute_local)
          attributes[:workdays] = schedule_days.map { |entry| entry.fetch(:weekday) }
        elsif @params.key?(:expected_start_minute_local)
          parsed_start = parse_minute_value(@params[:expected_start_minute_local])
          attributes[:expected_start_minute_local] = parsed_start unless parsed_start.nil?
        end
        if schedule_days.blank? && @params.key?(:expected_end_minute_local)
          parsed_end = parse_minute_value(@params[:expected_end_minute_local])
          attributes[:expected_end_minute_local] = parsed_end unless parsed_end.nil?
        end
        if @params.key?(:start_grace_minutes)
          parsed_start_grace = parse_integer(@params[:start_grace_minutes])
          attributes[:start_grace_minutes] = parsed_start_grace unless parsed_start_grace.nil?
        end
        if @params.key?(:end_grace_minutes)
          parsed_end_grace = parse_integer(@params[:end_grace_minutes])
          attributes[:end_grace_minutes] = parsed_end_grace unless parsed_end_grace.nil?
        end
        attributes[:workdays] = parse_workdays(@params[:workdays]) if schedule_days.blank? && @params.key?(:workdays)
        attributes
      end

      def parsed_schedule_days
        return nil unless @params.key?(:schedule_days)

        raw_entries =
          case @params[:schedule_days]
          when Hash
            @params[:schedule_days].values
          else
            Array.wrap(@params[:schedule_days])
          end

        schedule_days = raw_entries.flat_map do |entry|
          schedule_day_entry(entry)
        end

        schedule_days.sort_by { |entry| entry.fetch(:weekday) }
      end

      def schedule_day_entry(entry)
        payload = entry.respond_to?(:to_h) ? entry.to_h.with_indifferent_access : {}
        weekday = parse_integer(payload[:weekday])
        enabled = BOOLEAN.cast(payload[:enabled])
        return [] unless weekday&.between?(0, 6) && enabled

        start_minute = parse_minute_value(payload[:expected_start_minute_local])
        end_minute = parse_minute_value(payload[:expected_end_minute_local])
        return [] if start_minute.nil? || end_minute.nil?

        [ {
          weekday: weekday,
          expected_start_minute_local: start_minute,
          expected_end_minute_local: end_minute
        } ]
      end

      def parse_integer(value)
        return nil if value.blank?

        Integer(value, 10, exception: false)
      end

      def parse_minute_value(value)
        return nil if value.blank?
        return value if value.is_a?(Integer)

        if value.to_s.include?(":")
          hours, minutes = value.to_s.split(":", 2).map { |segment| Integer(segment, 10, exception: false) }
          return nil unless hours && minutes

          return (hours * 60) + minutes
        end

        parse_integer(value)
      end

      def parse_workdays(value)
        Array(value).flat_map { |entry| entry.to_s.split(",") }
                    .filter_map { |entry| Integer(entry, 10, exception: false) }
                    .uniq
                    .sort
      end
    end
  end
end
