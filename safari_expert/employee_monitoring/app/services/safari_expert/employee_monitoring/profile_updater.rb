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
        profile.assign_attributes(profile_attributes)
        profile.save!
        profile
      end

      private

      def profile_attributes
        attributes = {}
        attributes[:monitoring_enabled] = BOOLEAN.cast(@params[:monitoring_enabled]) if @params.key?(:monitoring_enabled)
        attributes[:timezone_override] = @params[:timezone_override].presence if @params.key?(:timezone_override)
        if @params.key?(:expected_start_minute_local)
          parsed_start = parse_minute_value(@params[:expected_start_minute_local])
          attributes[:expected_start_minute_local] = parsed_start unless parsed_start.nil?
        end
        if @params.key?(:expected_end_minute_local)
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
        attributes[:workdays] = parse_workdays(@params[:workdays]) if @params.key?(:workdays)
        attributes
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
